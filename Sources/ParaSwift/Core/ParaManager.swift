import SwiftUI
import AuthenticationServices
import WebKit
import os

#if os(iOS)
@available(iOS 16.4,*)
@MainActor
/// Para Manager class for interacting with Para services
///
/// This class provides a comprehensive interface for applications to interact with
/// Para wallet services, including authentication, wallet management, and transaction signing.
public class ParaManager: NSObject, ObservableObject {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
    
    /// Available Para wallets connected to this instance
    @Published public var wallets: [Wallet] = []
    
    /// Current state of the Para Manager session
    @Published public var sessionState: ParaSessionState = .unknown
    
    /// Indicates if the ParaManager is ready to receive requests
    public var isReady: Bool {
        return paraWebView.isReady
    }
    
    /// Current package version
    public static let packageVersion = "1.2.1"
    
    /// Para environment configuration
    public var environment: ParaEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    
    /// API key for Para services
    public var apiKey: String
    
    /// Internal passkeys manager for handling authentication
    private let passkeysManager: PasskeysManager
    
    /// Web view interface for communicating with Para services
    private let paraWebView: ParaWebView
    
    /// Deep link for app authentication flows
    internal let deepLink: String
    
    // MARK: - Initialization
    
    /// Initialize a new Para manager
    /// - Parameters:
    ///   - environment: The Para Environment enum
    ///   - apiKey: Your Para API key
    ///   - deepLink: An optional deepLink for your application. Defaults to the app's Bundle Identifier.
    public init(environment: ParaEnvironment, apiKey: String, deepLink: String? = nil) {
        self.environment = environment
        self.apiKey = apiKey
        self.passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        self.paraWebView = ParaWebView(environment: environment, apiKey: apiKey)
        self.deepLink = deepLink ?? Bundle.main.bundleIdentifier!
        super.init()
        Task {
            await waitForParaReady()
        }
    }
    
    // MARK: - Internal Utilities
    
    /// Waits for the Para web view to be ready with a timeout
    private func waitForParaReady() async {
        let startTime = Date()
        let maxWaitDuration: TimeInterval = 30.0
        
        while !paraWebView.isReady && paraWebView.initializationError == nil && paraWebView.lastError == nil {
            if Date().timeIntervalSince(startTime) > maxWaitDuration {
                sessionState = .inactive
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if paraWebView.initializationError != nil || paraWebView.lastError != nil {
            sessionState = .inactive
            return
        }

        if let active = try? await isSessionActive(), active {
            if let loggedIn = try? await isFullyLoggedIn(), loggedIn {
                sessionState = .activeLoggedIn
            } else {
                sessionState = .active
            }
        } else {
            sessionState = .inactive
        }
    }
    
    /// Ensure that the web view is ready before sending messages
    func ensureWebViewReady() async throws {
        if !paraWebView.isReady {
            logger.debug("Waiting for WebView initialization...")
            await waitForParaReady()
            guard paraWebView.isReady else {
                throw ParaError.bridgeError("WebView failed to initialize")
            }
        }
    }
    
    /// Posts a message to the Para bridge
    /// - Parameters:
    ///   - method: The method name to call
    ///   - arguments: The arguments to pass
    /// - Returns: The response from the bridge
    internal func postMessage(method: String, arguments: [Encodable]) async throws -> Any? {
        logger.debug("Posting message to bridge - Method: \(method), Arguments: \(arguments)")
        
        do {
            let result = try await paraWebView.postMessage(method: method, arguments: arguments)
            logger.debug("Bridge response for method \(method): \(String(describing: result))")
            return result
        } catch {
            logger.error("Bridge error for method \(method): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Decodes a result from the bridge to the expected type
    /// - Parameters:
    ///   - result: The result from the bridge
    ///   - expectedType: The expected type
    ///   - method: The method name for error reporting
    /// - Returns: The decoded result
    internal func decodeResult<T>(_ result: Any?, expectedType: T.Type, method: String) throws -> T {
        guard let value = result as? T else {
            throw ParaError.bridgeError("METHOD_ERROR<\(method)>: Invalid result format expected \(T.self), but got \(String(describing: result))")
        }
        return value
    }
    
    /// Decodes a dictionary result from the bridge and extracts a specific key
    /// - Parameters:
    ///   - result: The result from the bridge
    ///   - expectedType: The expected type of the value
    ///   - method: The method name for error reporting
    ///   - key: The key to extract
    /// - Returns: The decoded value
    internal func decodeDictionaryResult<T>(_ result: Any?, expectedType: T.Type, method: String, key: String) throws -> T {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)
        guard let value = dict[key] as? T else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-\(key)>: Missing or invalid key result")
        }
        return value
    }
}

// MARK: - Authentication Methods

@available(iOS 16.4,*)
extension ParaManager {
    /// Helper function for extracting authentication information
    private func authInfoHelper(authInfo: AuthInfo?) async throws -> Any? {
        if let authInfo = authInfo as? EmailAuthInfo {
            return try await postMessage(method: "getWebChallenge", arguments: [authInfo])
        }
        
        if let authInfo = authInfo as? PhoneAuthInfo {
            return try await postMessage(method: "getWebChallenge", arguments: [authInfo])
        }
        
        return try await postMessage(method: "getWebChallenge", arguments: [])
    }
    
    /// Login with passkey authentication
    /// - Parameters:
    ///   - authorizationController: The controller to handle authorization UI
    ///   - authInfo: Optional authentication information (email or phone)
    @available(macOS 13.3, iOS 16.4, *)
    @MainActor
    public func login(authorizationController: AuthorizationController, authInfo: AuthInfo?) async throws {
        let getWebChallengeResult = try await authInfoHelper(authInfo: authInfo)
        let challenge = try decodeDictionaryResult(getWebChallengeResult, expectedType: String.self, method: "getWebChallenge", key: "challenge")
        let allowedPublicKeys = try decodeDictionaryResult(getWebChallengeResult, expectedType: [String]?.self, method: "getWebChallenge", key: "allowedPublicKeys") ?? []
        
        let signIntoPasskeyAccountResult = try await passkeysManager.signIntoPasskeyAccount(
            authorizationController: authorizationController,
            challenge: challenge,
            allowedPublicKeys: allowedPublicKeys
        )
        
        let id = signIntoPasskeyAccountResult.credentialID.base64URLEncodedString()
        let authenticatorData = signIntoPasskeyAccountResult.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = signIntoPasskeyAccountResult.rawClientDataJSON.base64URLEncodedString()
        let signature = signIntoPasskeyAccountResult.signature.base64URLEncodedString()
        
        let verifyWebChallengeResult = try await postMessage(
            method: "verifyWebChallenge", 
            arguments: [id, authenticatorData, clientDataJSON, signature]
        )
        let userId = try decodeResult(verifyWebChallengeResult, expectedType: String.self, method: "verifyWebChallenge")
        
        _ = try await postMessage(
            method: "loginV2", 
            arguments: [userId, id, signIntoPasskeyAccountResult.userID.base64URLEncodedString()]
        )
        self.wallets = try await fetchWallets()
        sessionState = .activeLoggedIn
    }
    
    /// Generate a new passkey for authentication
    /// - Parameters:
    ///   - identifier: The user identifier
    ///   - biometricsId: The biometrics ID for the passkey
    ///   - authorizationController: The controller to handle authorization UI
    @available(macOS 13.3, iOS 16.4, *)
    public func generatePasskey(identifier: String, biometricsId: String, authorizationController: AuthorizationController) async throws {
        try await ensureWebViewReady()
        var userHandle = Data(count: 32)
        _ = userHandle.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        let userHandleEncoded = userHandle.base64URLEncodedString()
        let result = try await passkeysManager.createPasskeyAccount(
            authorizationController: authorizationController,
            username: identifier,
            userHandle: userHandle
        )

        guard let rawAttestation = result.rawAttestationObject else {
            throw ParaError.bridgeError("Missing attestation object")
        }
        let rawClientData = result.rawClientDataJSON
        let credID = result.credentialID

        let attestationObjectEncoded = rawAttestation.base64URLEncodedString()
        let clientDataJSONEncoded = rawClientData.base64URLEncodedString()
        let credentialIDEncoded = credID.base64URLEncodedString()

        _ = try await postMessage(
            method: "generatePasskeyV2",
            arguments: [
                attestationObjectEncoded,
                clientDataJSONEncoded,
                credentialIDEncoded,
                userHandleEncoded,
                biometricsId
            ]
        )
    }
    
    /// Signs up a new user or logs in an existing user
    /// - Parameter auth: Authentication information (email or phone)
    /// - Returns: AuthState object containing information about the next steps
    public func signUpOrLogIn(auth: Auth) async throws -> AuthState {
        try await ensureWebViewReady()
        
        // Create a properly structured Encodable payload
        let payload = createSignUpOrLogInPayload(from: auth)
        
        let result = try await postMessage(method: "signUpOrLogIn", arguments: [payload])
        let authState = try parseAuthStateFromResult(result)
        
        if authState.stage == .verify || authState.stage == .login {
            self.sessionState = .active
        }
        
        return authState
    }
    
    /// Verifies a new account with the provided verification code
    /// - Parameter verificationCode: The verification code sent to the user
    /// - Returns: AuthState object containing information about the next steps
    public func verifyNewAccount(verificationCode: String) async throws -> AuthState {
        try await ensureWebViewReady()
        
        let result = try await postMessage(method: "verifyNewAccount", arguments: [verificationCode])
        let authState = try parseAuthStateFromResult(result)
        
        if authState.stage == .signup {
            self.sessionState = .active
        }
        
        return authState
    }
    
    /// Setup two-factor authentication
    /// - Returns: URI for configuring 2FA in an authenticator app
    public func setup2FA() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "setup2FA", arguments: [])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "setup2FA", key: "uri")
    }
    
    /// Enable two-factor authentication after setup
    public func enable2FA() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "enable2FA", arguments: [])
    }
    
    /// Check if two-factor authentication is set up
    /// - Returns: True if 2FA is set up
    public func is2FASetup() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "check2FAStatus", arguments: [])
        return try decodeDictionaryResult(result, expectedType: Bool.self, method: "check2FAStatus", key: "isSetup")
    }
    
    /// Resend verification code for account verification
    public func resendVerificationCode() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "resendVerificationCode", arguments: [])
    }
    
    /// Check if the user is fully logged in
    /// - Returns: True if the user is fully logged in
    public func isFullyLoggedIn() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isFullyLoggedIn", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isFullyLoggedIn")
    }
    
    /// Check if the session is active
    /// - Returns: True if the session is active
    public func isSessionActive() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isSessionActive", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isSessionActive")
    }
    
    /// Export the current session for backup or transfer
    /// - Returns: Session data as a string
    public func exportSession() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "exportSession", arguments: [])
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }
    
    /// Logs out the current user and clears all session data
    public func logout() async throws {
        _ = try await postMessage(method: "logout", arguments: [])
        
        // Clear web data store
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        
        // Reset state
        wallets = []
        self.sessionState = .inactive
    }
    
    /// Logs in with an external wallet address
    /// - Parameters:
    ///   - externalAddress: The external wallet address
    ///   - type: The type of wallet (e.g. "EVM")
    internal func externalWalletLogin(externalAddress: String, type: String) async throws {
        try await ensureWebViewReady()
        
        // Create proper Encodable structs for the parameters
        struct ExternalWallet: Encodable {
            let address: String
            let type: String
        }
        
        struct LoginExternalWalletParams: Encodable {
            let externalWallet: ExternalWallet
        }
        
        let params = LoginExternalWalletParams(
            externalWallet: ExternalWallet(
                address: externalAddress,
                type: type
            )
        )
        
        _ = try await postMessage(method: "loginExternalWallet", arguments: [params])
        self.sessionState = .activeLoggedIn
        
        logger.debug("External wallet login completed for address: \(externalAddress)")
    }
    
    // MARK: - Auth Helper Methods
    
    // Private struct for the signUpOrLogIn payload
    private struct SignUpOrLogInPayload: Encodable {
        let auth: AuthPayload
        
        struct AuthPayload: Encodable {
            let email: String?
            let phone: String?
            
            init(email: String? = nil, phone: String? = nil) {
                self.email = email
                self.phone = phone
            }
        }
    }
    
    private func createSignUpOrLogInPayload(from auth: Auth) -> SignUpOrLogInPayload {
        switch auth {
        case .email(let emailAddress):
            return SignUpOrLogInPayload(auth: SignUpOrLogInPayload.AuthPayload(email: emailAddress))
        case .phone(let phoneNumber):
            return SignUpOrLogInPayload(auth: SignUpOrLogInPayload.AuthPayload(phone: phoneNumber))
        }
    }
    
    private func parseAuthStateFromResult(_ result: Any?) throws -> AuthState {
        guard let resultDict = result as? [String: Any] else {
            throw ParaError.bridgeError("Invalid result format from authentication call")
        }
        
        guard let stageString = resultDict["stage"] as? String,
              let stage = AuthStage(rawValue: stageString),
              let userId = resultDict["userId"] as? String else {
            throw ParaError.bridgeError("Missing required fields in authentication response")
        }
        
        let passkeyUrl = resultDict["passkeyUrl"] as? String
        let passkeyId = resultDict["passkeyId"] as? String
        let passwordUrl = resultDict["passwordUrl"] as? String
        let passkeyKnownDeviceUrl = resultDict["passkeyKnownDeviceUrl"] as? String
        
        // Extract biometric hints if available
        var biometricHints: [AuthState.BiometricHint]?
        if let hintsArray = resultDict["biometricHints"] as? [[String: Any]] {
            biometricHints = hintsArray.compactMap { hint in
                let aaguid = hint["aaguid"] as? String
                let userAgent = hint["userAgent"] as? String ?? hint["useragent"] as? String
                
                guard aaguid != nil || userAgent != nil else {
                    return nil
                }
                return AuthState.BiometricHint(aaguid: aaguid, userAgent: userAgent)
            }
        }
        
        // Extract email if available
        var email: String? = nil
        if let auth = resultDict["auth"] as? [String: Any] {
            email = auth["email"] as? String
        }
        
        return AuthState(
            stage: stage,
            userId: userId,
            email: email,
            passkeyUrl: passkeyUrl,
            passkeyId: passkeyId,
            passkeyKnownDeviceUrl: passkeyKnownDeviceUrl,
            passwordUrl: passwordUrl,
            biometricHints: biometricHints
        )
    }
}

// MARK: - Wallet Management

@available(iOS 16.4,*)
extension ParaManager {
    /// Create a new wallet of the specified type
    /// - Parameters:
    ///   - type: The type of wallet to create
    ///   - skipDistributable: Whether to skip distributable shares
    @MainActor
    public func createWallet(type: WalletType, skipDistributable: Bool) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "createWallet", arguments: [type.rawValue, skipDistributable])
        self.wallets = try await fetchWallets()
        self.sessionState = .activeLoggedIn
    }
    
    /// Fetch all wallets associated with the current user
    /// - Returns: Array of wallet objects
    public func fetchWallets() async throws -> [Wallet] {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "fetchWallets", arguments: [])
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }
    
    /// Distribute a new wallet share to another user
    /// - Parameters:
    ///   - walletId: The ID of the wallet to share
    ///   - userShare: The user share
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "distributeNewWalletShare", arguments: [walletId, userShare])
    }
    
    /// Get the current user's email address
    /// - Returns: Email address as a string
    public func getEmail() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "getEmail", arguments: [])
        return try decodeResult(result, expectedType: String.self, method: "getEmail")
    }
}

// MARK: - Signing Operations

@available(iOS 16.4,*)
extension ParaManager {
    /// Sign a message with a wallet
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing
    ///   - message: The message to sign
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation
    /// - Returns: The signature as a string
    public func signMessage(walletId: String, message: String, timeoutMs: Int? = nil) async throws -> String {
        try await ensureWebViewReady()
        
        // Create proper Encodable struct for parameters
        struct SignMessageParams: Encodable {
            let walletId: String
            let messageBase64: String
            let timeoutMs: Int?
        }
        
        let messageBase64 = message.toBase64()
        let params = SignMessageParams(
            walletId: walletId,
            messageBase64: messageBase64,
            timeoutMs: timeoutMs
        )
        
        let result = try await postMessage(method: "signMessage", arguments: [params])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signMessage", key: "signature")
    }
    
    /// Sign a transaction with a wallet
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing
    ///   - rlpEncodedTx: The RLP-encoded transaction
    ///   - chainId: The chain ID
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation
    /// - Returns: The signature as a string
    public func signTransaction(walletId: String, rlpEncodedTx: String, chainId: String, timeoutMs: Int? = nil) async throws -> String {
        try await ensureWebViewReady()
        
        // Create proper Encodable struct for parameters
        struct SignTransactionParams: Encodable {
            let walletId: String
            let rlpEncodedTxBase64: String
            let chainId: String
            let timeoutMs: Int?
        }
        
        let params = SignTransactionParams(
            walletId: walletId,
            rlpEncodedTxBase64: rlpEncodedTx.toBase64(),
            chainId: chainId,
            timeoutMs: timeoutMs
        )
        
        let result = try await postMessage(method: "signTransaction", arguments: [params])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signTransaction", key: "signature")
    }
}

// MARK: - Utility Methods

@available(iOS 16.4,*)
extension ParaManager {
    /// Formats a phone number into the international format required by Para
    /// - Parameters:
    ///   - phoneNumber: The national phone number (without country code)
    ///   - countryCode: The country code (without the plus sign)
    /// - Returns: Formatted phone number in international format (+${countryCode}${phoneNumber})
    /// - Note: This method is provided as a convenience for formatting phone numbers correctly.
    ///         All Para authentication methods expect phone numbers in international format.
    ///         Example: formatPhoneNumber(phoneNumber: "5551234", countryCode: "1") returns "+15551234"
    public func formatPhoneNumber(phoneNumber: String, countryCode: String) -> String {
        return "+\(countryCode)\(phoneNumber)"
    }
}

// MARK: - High-Level Authentication Flows

@available(iOS 16.4,*)
extension ParaManager {
    /// Handles the complete email authentication flow, including signup/login decision and verification if needed.
    /// - Parameters:
    ///   - email: The user's email address
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage
    ///   - authorizationController: The AuthorizationController to use for passkey operations
    /// - Returns: A tuple containing the authentication status, next required action, and any error message
    public func handleEmailAuth(
        email: String,
        verificationCode: String? = nil,
        authorizationController: AuthorizationController
    ) async -> (status: EmailAuthStatus, errorMessage: String?) {
        do {
            // If verification code is provided, handle verification flow
            if let code = verificationCode {
                return try await handleVerification(code: code, email: email, authorizationController: authorizationController)
            }
            
            // Otherwise start the initial auth flow
            let authState = try await signUpOrLogIn(auth: .email(email))
            
            switch authState.stage {
            case .verify:
                // New user that needs to verify email
                return (.needsVerification, nil)
                
            case .login:
                // Existing user, handle passkey login
                if authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil {
                    try await login(authorizationController: authorizationController, authInfo: EmailAuthInfo(email: email))
                    return (.success, nil)
                } else {
                    return (.error, "Unable to get passkey authentication URL")
                }
                
            case .signup:
                // This shouldn't happen directly from signUpOrLogIn with email
                return (.error, "Unexpected authentication state")
            }
        } catch {
            return (.error, String(describing: error))
        }
    }
    
    private func handleVerification(
        code: String,
        email: String,
        authorizationController: AuthorizationController
    ) async throws -> (status: EmailAuthStatus, errorMessage: String?) {
        let authState = try await verifyNewAccount(verificationCode: code)
        
        // Check if we're in the signup stage
        guard authState.stage == .signup else {
            return (.error, "Unexpected auth stage: \(authState.stage)")
        }
        
        // If we have a passkeyId, use it to generate a passkey
        if let passkeyId = authState.passkeyId {
            try await generatePasskey(
                identifier: authState.email ?? email,
                biometricsId: passkeyId,
                authorizationController: authorizationController
            )
            
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else if authState.passwordUrl != nil {
            // In a real app, you would open this URL in a new window
            // For this example, we'll just create a wallet directly
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else {
            return (.error, "No authentication method available")
        }
    }
    
    /// Status of the email authentication process
    public enum EmailAuthStatus {
        /// Authentication successful
        case success
        /// User needs to verify their email
        case needsVerification
        /// Error occurred during authentication
        case error
    }
    
    /// Handles the complete phone authentication flow, including signup/login decision and verification if needed.
    /// - Parameters:
    ///   - phoneNumber: The user's phone number (without country code)
    ///   - countryCode: The country code (without the + prefix)
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage
    ///   - authorizationController: The AuthorizationController to use for passkey operations
    /// - Returns: A tuple containing the authentication status, next required action, and any error message
    public func handlePhoneAuth(
        phoneNumber: String,
        countryCode: String,
        verificationCode: String? = nil,
        authorizationController: AuthorizationController
    ) async -> (status: PhoneAuthStatus, errorMessage: String?) {
        do {
            // Format the phone number in international format
            let formattedPhoneNumber = formatPhoneNumber(phoneNumber: phoneNumber, countryCode: countryCode)
            
            // If verification code is provided, handle verification flow
            if let code = verificationCode {
                return try await handlePhoneVerification(
                    code: code,
                    phoneNumber: phoneNumber,
                    countryCode: countryCode,
                    authorizationController: authorizationController
                )
            }
            
            // Otherwise start the initial auth flow
            let authState = try await signUpOrLogIn(auth: .phone(formattedPhoneNumber))
            
            switch authState.stage {
            case .verify:
                // New user that needs to verify phone
                return (.needsVerification, nil)
                
            case .login:
                // Existing user, handle passkey login
                if authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil {
                    try await login(
                        authorizationController: authorizationController,
                        authInfo: PhoneAuthInfo(phone: phoneNumber, countryCode: countryCode)
                    )
                    return (.success, nil)
                } else {
                    return (.error, "Unable to get passkey authentication URL")
                }
                
            case .signup:
                // This shouldn't happen directly from signUpOrLogIn with phone
                return (.error, "Unexpected authentication state")
            }
        } catch {
            return (.error, String(describing: error))
        }
    }
    
    private func handlePhoneVerification(
        code: String,
        phoneNumber: String,
        countryCode: String,
        authorizationController: AuthorizationController
    ) async throws -> (status: PhoneAuthStatus, errorMessage: String?) {
        let authState = try await verifyNewAccount(verificationCode: code)
        
        // Check if we're in the signup stage
        guard authState.stage == .signup else {
            return (.error, "Unexpected auth stage: \(authState.stage)")
        }
        
        // If we have a passkeyId, use it to generate a passkey
        if let passkeyId = authState.passkeyId {
            let identifier = formatPhoneNumber(phoneNumber: phoneNumber, countryCode: countryCode)
            try await generatePasskey(
                identifier: identifier,
                biometricsId: passkeyId,
                authorizationController: authorizationController
            )
            
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else if authState.passwordUrl != nil {
            // In a real app, you would open this URL in a new window
            // For this example, we'll just create a wallet directly
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else {
            return (.error, "No authentication method available")
        }
    }
    
    /// Status of the phone authentication process
    public enum PhoneAuthStatus {
        /// Authentication successful
        case success
        /// User needs to verify their phone number
        case needsVerification
        /// Error occurred during authentication
        case error
    }
}

// MARK: - Deprecated Methods

@available(iOS 16.4,*)
extension ParaManager {
    /// Deprecated: Use `signUpOrLogIn` instead
    @available(*, deprecated, message: "Use signUpOrLogIn instead to align with V2 authentication flow")
    public func checkIfUserExists(email: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExists", arguments: [email])
        return try decodeResult(result, expectedType: Bool.self, method: "checkIfUserExists")
    }
    
    /// Deprecated: Use `signUpOrLogIn` instead
    @available(*, deprecated, message: "Use signUpOrLogIn instead to align with V2 authentication flow")
    public func checkIfUserExistsByPhone(phoneNumber: String, countryCode: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExistsByPhone", arguments: [phoneNumber, countryCode])
        return try decodeResult(result, expectedType: Bool.self, method: "checkIfUserExistsByPhone")
    }
    
    /// Deprecated: Use `signUpOrLogIn` instead
    @available(*, deprecated, message: "Use signUpOrLogIn instead to align with V2 authentication flow")
    public func createUser(email: String) async throws {
        _ = try await postMessage(method: "createUser", arguments: [email])
    }
    
    /// Deprecated: Use `signUpOrLogIn` instead
    @available(*, deprecated, message: "Use signUpOrLogIn instead to align with V2 authentication flow")
    public func createUserByPhone(phoneNumber: String, countryCode: String) async throws {
        _ = try await postMessage(method: "createUserByPhone", arguments: [phoneNumber, countryCode])
    }
    
    /// Deprecated: Use `verifyNewAccount` instead
    @available(*, deprecated, message: "Use verifyNewAccount instead to align with V2 authentication flow")
    public func verify(verificationCode: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "verifyEmail", arguments: [verificationCode])
        let resultString = try decodeResult(result, expectedType: String.self, method: "verifyEmail")
        
        let paths = resultString.split(separator: "/")
        guard let lastPath = paths.last,
              let biometricsId = lastPath.split(separator: "?").first else {
            throw ParaError.bridgeError("Invalid path format in result")
        }
        
        return String(biometricsId)
    }
    
    /// Deprecated: Use `verifyNewAccount` instead
    @available(*, deprecated, message: "Use verifyNewAccount instead to align with V2 authentication flow")
    public func verifyByPhone(verificationCode: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "verifyPhone", arguments: [verificationCode])
        let resultString = try decodeResult(result, expectedType: String.self, method: "verifyPhone")
        
        let paths = resultString.split(separator: "/")
        guard let lastPath = paths.last,
              let biometricsId = lastPath.split(separator: "?").first else {
            throw ParaError.bridgeError("Invalid path format in result")
        }
        
        return String(biometricsId)
    }
}

// MARK: - Error Handling

public enum ParaError: Error, CustomStringConvertible {
    case bridgeError(String)
    case bridgeTimeoutError
    case error(String)
    
    public var description: String {
        switch self {
        case .bridgeError(let info):
            return "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            return "The javascript bridge did not respond in time and the continuation has been cancelled."
        case .error(let info):
            return "An error occurred: \(info)"
        }
    }
}
#endif
