import SwiftUI
import AuthenticationServices
import WebKit
import os

#if os(iOS)
@available(iOS 16.4,*)
@MainActor
/// Manages Para wallet services including authentication, wallet management, and transaction signing.
///
/// This class provides a comprehensive interface for applications to interact with Para wallet services.
/// It handles authentication flows, wallet creation and management, and transaction signing operations.
public class ParaManager: NSObject, ObservableObject {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
    
    /// Available Para wallets connected to this instance.
    @Published public var wallets: [Wallet] = []
    
    /// Current state of the Para Manager session.
    @Published public var sessionState: ParaSessionState = .unknown
    
    /// Indicates if the ParaManager is ready to receive requests.
    public var isReady: Bool {
        return paraWebView.isReady
    }
    
    /// Current package version.
    public static let packageVersion = "1.2.1"
    
    /// Para environment configuration.
    public var environment: ParaEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    
    /// API key for Para services.
    public var apiKey: String
    
    /// Internal passkeys manager for handling authentication.
    private let passkeysManager: PasskeysManager
    
    /// Web view interface for communicating with Para services.
    internal let paraWebView: ParaWebView
    
    /// Deep link for app authentication flows.
    internal let deepLink: String
    
    // MARK: - Initialization
    
    /// Creates a new Para manager instance.
    ///
    /// - Parameters:
    ///   - environment: The Para environment configuration.
    ///   - apiKey: Your Para API key.
    ///   - deepLink: Optional deep link for your application. Defaults to the app's bundle identifier.
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
    ///   - payload: The payload to pass
    /// - Returns: The response from the bridge
    internal func postMessage(method: String, payload: Encodable) async throws -> Any? {
        // Log payload as JSON string
        var payloadString = "<encoding error>"
        if let data = try? JSONEncoder().encode(AnyEncodable(payload)),
           let jsonString = String(data: data, encoding: .utf8) {
            payloadString = jsonString
        }
        logger.debug("Posting message to bridge - Method: \(method), Payload: \(payloadString)")
        
        do {
            // Call the ParaWebView postMessage with payload
            let result: Any? = try await paraWebView.postMessage(method: method, payload: payload)
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
    /// Extracts authentication information and gets a web challenge.
    ///
    /// - Parameter authInfo: Optional authentication information (email or phone).
    /// - Returns: The web challenge result.
    private func authInfoHelper(authInfo: AuthInfo?) async throws -> Any? {
        let emailArg: String?
        // TODO: Add phone support when bridge supports it
        if let emailInfo = authInfo as? EmailAuthInfo {
            emailArg = emailInfo.email
        } else {
            emailArg = nil
        }
        let payload = GetWebChallengeArgs(email: emailArg)
        // Use the wrapper with payload
        return try await postMessage(method: "getWebChallenge", payload: payload)
    }
    
    /// Logs in with passkey authentication.
    ///
    /// - Parameters:
    ///   - authorizationController: The controller to handle authorization UI.
    ///   - authInfo: Optional authentication information (email or phone).
    @available(macOS 13.3, iOS 16.4, *)
    @MainActor
    public func loginWithPasskey(authorizationController: AuthorizationController, authInfo: AuthInfo?) async throws {
        let getWebChallengeResult = try await authInfoHelper(authInfo: authInfo)
        let challenge = try decodeDictionaryResult(
            getWebChallengeResult,
            expectedType: String.self,
            method: "getWebChallenge",
            key: "challenge"
        )
        let allowedPublicKeys = try decodeDictionaryResult(
            getWebChallengeResult,
            expectedType: [String]?.self,
            method: "getWebChallenge",
            key: "allowedPublicKeys"
        ) ?? []
        
        let signIntoPasskeyAccountResult = try await passkeysManager.signIntoPasskeyAccount(
            authorizationController: authorizationController,
            challenge: challenge,
            allowedPublicKeys: allowedPublicKeys
        )
        
        let id = signIntoPasskeyAccountResult.credentialID.base64URLEncodedString()
        let authenticatorData = signIntoPasskeyAccountResult.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = signIntoPasskeyAccountResult.rawClientDataJSON.base64URLEncodedString()
        let signature = signIntoPasskeyAccountResult.signature.base64URLEncodedString()
        
        let verifyArgs = VerifyWebChallengeArgs(
            publicKey: id,
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            signature: signature
        )
        // Use the wrapper with payload
        let verifyWebChallengeResult = try await postMessage(
            method: "verifyWebChallenge",
            payload: verifyArgs
        )
        // Decode the result directly as a String (userId)
        let userId = try decodeResult(verifyWebChallengeResult, expectedType: String.self, method: "verifyWebChallenge")
        
        let loginArgs = LoginWithPasskeyArgs(
            userId: userId,
            credentialsId: id,
            userHandle: signIntoPasskeyAccountResult.userID.base64URLEncodedString()
        )
        // Use the wrapper with payload
        let loginResult = try await postMessage(
            method: "loginWithPasskey",
            payload: loginArgs
        )
        if let walletDict = loginResult as? [String: Any] {
            logger.debug("loginWithPasskey bridge call returned wallet data: \(walletDict)")
        }

        self.wallets = try await fetchWallets()
        sessionState = .activeLoggedIn
    }
    
    /// Generate a new passkey for authentication
    /// - Parameters:
    ///   - identifier: The user identifier
    ///   - biometricsId: The biometrics ID for the passkey
    ///   - authorizationController: The controller to handle authorization UI
    @available(macOS 13.3, iOS 16.4, *)
    internal func generatePasskey(identifier: String, biometricsId: String, authorizationController: AuthorizationController) async throws {
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

        let generateArgs = GeneratePasskeyArgs(
            attestationObject: attestationObjectEncoded,
            clientDataJson: clientDataJSONEncoded,
            credentialsId: credentialIDEncoded,
            userHandle: userHandleEncoded,
            biometricsId: biometricsId
        )
        // Use the wrapper with payload
        _ = try await postMessage(
            method: "generatePasskey",
            payload: generateArgs
        )
    }
    
    /// Signs up a new user or logs in an existing user
    /// - Parameter auth: Authentication information (email or phone)
    /// - Returns: AuthState object containing information about the next steps
    internal func signUpOrLogIn(auth: Auth) async throws -> AuthState {
        try await ensureWebViewReady()
        
        // Create a properly structured Encodable payload
        let payload = createSignUpOrLogInPayload(from: auth)
        
        let result = try await postMessage(method: "signUpOrLogIn", payload: payload)
        let authState = try parseAuthStateFromResult(result)
        
        if authState.stage == .verify || authState.stage == .login {
            self.sessionState = .active
        }
        
        return authState
    }
    
    /// Verifies a new account with the provided verification code
    /// - Parameter verificationCode: The verification code sent to the user
    /// - Returns: AuthState object containing information about the next steps
    internal func verifyNewAccount(verificationCode: String) async throws -> AuthState {
        try await ensureWebViewReady()
        
        let result = try await postMessage(method: "verifyNewAccount", payload: VerifyNewAccountArgs(verificationCode: verificationCode))
        let authState = try parseAuthStateFromResult(result)
        
        if authState.stage == .signup {
            self.sessionState = .active
        }
        
        return authState
    }
    
    /// Setup two-factor authentication
    /// - Returns: Response indicating if 2FA is already set up or needs to be configured
    public func setup2fa() async throws -> TwoFactorSetupResponse {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "setup2fa", payload: EmptyPayload())
        guard let dict = result as? [String: Any] else {
            throw ParaError.bridgeError("Invalid result format from setup2fa")
        }
        
        if let isSetup = dict["isSetup"] as? Bool, isSetup {
            return .alreadySetup
        }
        
        let uri = try decodeDictionaryResult(result, expectedType: String.self, method: "setup2fa", key: "uri")
        return .needsSetup(uri: uri)
    }
    
    /// Enable two-factor authentication after setup
    /// - Parameter verificationCode: The code from the user's authenticator app.
    public func enable2fa(verificationCode: String) async throws {
        try await ensureWebViewReady()
        // Define the payload structure expected by the bridge
        struct Enable2faArgs: Encodable {
            let verificationCode: String
        }
        let payload = Enable2faArgs(verificationCode: verificationCode)
        _ = try await postMessage(method: "enable2fa", payload: payload)
    }
    
    /// Resend verification code for account verification
    public func resendVerificationCode() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "resendVerificationCode", payload: EmptyPayload())
    }
    
    /// Check if the user is fully logged in
    /// - Returns: True if the user is fully logged in
    public func isFullyLoggedIn() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isFullyLoggedIn", payload: EmptyPayload())
        return try decodeResult(result, expectedType: Bool.self, method: "isFullyLoggedIn")
    }
    
    /// Check if the session is active
    /// - Returns: True if the session is active
    public func isSessionActive() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isSessionActive", payload: EmptyPayload())
        return try decodeResult(result, expectedType: Bool.self, method: "isSessionActive")
    }
    
    /// Export the current session for backup or transfer
    /// - Returns: Session data as a string
    public func exportSession() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "exportSession", payload: EmptyPayload())
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }
    
    /// Logs out the current user and clears all session data
    public func logout() async throws {
        _ = try await postMessage(method: "logout", payload: EmptyPayload())
        
        // Clear web data store
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        
        // Reset state
        wallets = []
        self.sessionState = .inactive
    }
    
    /// Logs in using an external wallet
    /// - Parameters:
    ///   - wallet: Information about the external wallet
    internal func loginExternalWallet(wallet: ExternalWalletInfo) async throws {
        try await ensureWebViewReady()
        
        // Create proper Encodable payload using ExternalWalletIdentity
        let identity = ExternalWalletIdentity(wallet: wallet)
        let params = SignUpOrLogInPayload(auth: identity)
        
        // Explicitly type the result from postMessage
        let authStateResult: Any? = try await postMessage(method: "loginExternalWallet", payload: params)
        
        // Parse the returned AuthState
        do {
            let authState = try parseAuthStateFromResult(authStateResult)
            let logMessage = "loginExternalWallet completed. Returned AuthState: Stage=\(authState.stage), UserId=\(authState.userId)"
            logger.debug("\(logMessage)") // Log the pre-formatted string
        } catch let parseError {
            logger.error("loginExternalWallet: Failed to parse AuthState result: \(parseError.localizedDescription)")
        }
        
        self.sessionState = .activeLoggedIn
        
        logger.debug("External wallet login completed for address: \(wallet.address)")
    }
    
    /// Logs in with an external wallet address (legacy version)
    /// - Parameters:
    ///   - externalAddress: The external wallet address
    ///   - type: The type of wallet (e.g. "EVM")
    internal func loginExternalWallet(externalAddress: String, type: String) async throws {
        let walletType = ExternalWalletType(rawValue: type) ?? .evm
        let wallet = ExternalWalletInfo(address: externalAddress, type: walletType)
        try await loginExternalWallet(wallet: wallet)
    }
    
    // MARK: - Auth Helper Methods
    
    // Private struct for the signUpOrLogIn payload
    private struct SignUpOrLogInPayload: Encodable {
        let auth: AnyEncodable
        
        init(auth: Encodable) {
            self.auth = AnyEncodable(auth)
        }
    }
    
    private func createSignUpOrLogInPayload(from auth: Auth) -> SignUpOrLogInPayload {
        switch auth {
        case .email(let emailAddress):
            return SignUpOrLogInPayload(auth: EmailIdentity(email: emailAddress))
        case .phone(let phoneNumber):
            return SignUpOrLogInPayload(auth: PhoneIdentity(phone: phoneNumber, countryCode: phoneNumber.hasPrefix("+") ? "" : ""))
        case .farcaster(let fid):
            return SignUpOrLogInPayload(auth: FarcasterIdentity(fid: fid))
        case .telegram(let id):
            return SignUpOrLogInPayload(auth: TelegramIdentity(id: id))
        case .externalWallet(let wallet):
            return SignUpOrLogInPayload(auth: ExternalWalletIdentity(wallet: wallet))
        case .identity(let identity):
            return SignUpOrLogInPayload(auth: identity)
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
        let displayName = resultDict["displayName"] as? String
        let pfpUrl = resultDict["pfpUrl"] as? String
        let username = resultDict["username"] as? String
        let signatureVerificationMessage = resultDict["signatureVerificationMessage"] as? String
        
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
        
        // Extract auth identity and external wallet if available
        var authIdentity: AuthIdentity? = nil
        var externalWalletInfo: ExternalWalletInfo? = nil
        
        if let auth = resultDict["auth"] as? [String: Any] {
            // Determine the type of auth identity
            if let email = auth["email"] as? String {
                authIdentity = EmailIdentity(email: email)
            } else if let phone = auth["phone"] as? String, let countryCode = auth["countryCode"] as? String {
                authIdentity = PhoneIdentity(phone: phone, countryCode: countryCode)
            } else if let fid = auth["fid"] as? String {
                authIdentity = FarcasterIdentity(fid: fid)
            } else if let telegramId = auth["id"] as? String, auth["type"] as? String == "telegram" {
                authIdentity = TelegramIdentity(id: telegramId)
            } else if let wallet = auth["wallet"] as? [String: Any] {
                if let address = wallet["address"] as? String,
                   let typeString = wallet["type"] as? String,
                   let type = ExternalWalletType(rawValue: typeString) {
                    let provider = wallet["provider"] as? String
                    let walletInfo = ExternalWalletInfo(address: address, type: type, provider: provider)
                    authIdentity = ExternalWalletIdentity(wallet: walletInfo)
                    externalWalletInfo = walletInfo
                }
            }
        } else if let externalWallet = resultDict["externalWallet"] as? [String: Any] {
            // Handle direct externalWallet in the result
            if let address = externalWallet["address"] as? String,
               let typeString = externalWallet["type"] as? String,
               let type = ExternalWalletType(rawValue: typeString) {
                let provider = externalWallet["provider"] as? String
                let walletInfo = ExternalWalletInfo(address: address, type: type, provider: provider) 
                authIdentity = ExternalWalletIdentity(wallet: walletInfo)
                externalWalletInfo = walletInfo
            }
        }
        
        return AuthState(
            stage: stage,
            userId: userId,
            authIdentity: authIdentity,
            displayName: displayName,
            pfpUrl: pfpUrl,
            username: username,
            externalWalletInfo: externalWalletInfo,
            signatureVerificationMessage: signatureVerificationMessage,
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
    /// Creates a new wallet of the specified type and returns it along with any recovery secret.
    ///
    /// - Parameters:
    ///   - type: The type of wallet to create.
    ///   - skipDistributable: Whether to skip distributable shares.
    /// - Returns: A tuple containing the new `Wallet` object and an optional recovery secret string.
    @MainActor
    public func createWallet(type: WalletType, skipDistributable: Bool) async throws -> (newWallet: Wallet, recoverySecret: String?) {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "createWallet", payload: CreateWalletArgs(type: type.rawValue, skipDistributable: skipDistributable))
        
        // The bridge returns an array: [WalletDictionary, optionalRecoverySecretString]
        guard let resultArray = result as? [Any], !resultArray.isEmpty else {
            throw ParaError.bridgeError("METHOD_ERROR<createWallet>: Invalid result format, expected array but got \(String(describing: result))")
        }
        
        guard let walletDict = resultArray[0] as? [String: Any] else {
            throw ParaError.bridgeError("METHOD_ERROR<createWallet>: Invalid wallet data in result array")
        }
        
        let newWallet = Wallet(result: walletDict)
        let recoverySecret = resultArray.count > 1 ? resultArray[1] as? String : nil
        
        // Update session state, but don't fetch wallets here as the new wallet is returned.
        // The caller can decide whether to fetch or just update the local list.
        self.sessionState = .activeLoggedIn
        
        // Update the local wallets list immediately
        self.wallets.append(newWallet)

        return (newWallet, recoverySecret)
    }
    
    /// Fetches all wallets associated with the current user.
    ///
    /// - Returns: Array of wallet objects.
    public func fetchWallets() async throws -> [Wallet] {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "fetchWallets", payload: EmptyPayload())
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }
    
    /// Distributes a new wallet share to another user.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to share.
    ///   - userShare: The user share.
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "distributeNewWalletShare", payload: DistributeNewWalletShareArgs(walletId: walletId, userShare: userShare))
    }
    
    /// Gets the current user's email address.
    ///
    /// - Returns: Email address as a string.
    public func getEmail() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "getEmail", payload: EmptyPayload())
        return try decodeResult(result, expectedType: String.self, method: "getEmail")
    }
}

// MARK: - Signing Operations

@available(iOS 16.4,*)
extension ParaManager {
    /// Signs a message with a wallet.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - message: The message to sign.
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation.
    /// - Returns: The signature as a string.
    public func signMessage(walletId: String, message: String, timeoutMs: Int? = nil) async throws -> String {
        try await ensureWebViewReady()
        
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
        
        let result = try await postMessage(method: "signMessage", payload: params)
        return try decodeDictionaryResult(
            result,
            expectedType: String.self,
            method: "signMessage",
            key: "signature"
        )
    }
    
    /// Signs a transaction with a wallet.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - rlpEncodedTx: The RLP-encoded transaction.
    ///   - chainId: The chain ID.
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation.
    /// - Returns: The signature as a string.
    public func signTransaction(
        walletId: String,
        rlpEncodedTx: String,
        chainId: String,
        timeoutMs: Int? = nil
    ) async throws -> String {
        try await ensureWebViewReady()
        
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
        
        let result = try await postMessage(method: "signTransaction", payload: params)
        return try decodeDictionaryResult(
            result,
            expectedType: String.self,
            method: "signTransaction",
            key: "signature"
        )
    }
}

// MARK: - Utility Methods

@available(iOS 16.4,*)
extension ParaManager {
    /// Formats a phone number into the international format required by Para.
    ///
    /// - Parameters:
    ///   - phoneNumber: The national phone number (without country code).
    ///   - countryCode: The country code (without the plus sign).
    /// - Returns: Formatted phone number in international format (+${countryCode}${phoneNumber}).
    ///
    /// - Note: This method is provided as a convenience for formatting phone numbers correctly.
    ///         All Para authentication methods expect phone numbers in international format.
    ///         Example: formatPhoneNumber(phoneNumber: "5551234", countryCode: "1") returns "+15551234".
    public func formatPhoneNumber(phoneNumber: String, countryCode: String) -> String {
        return "+\(countryCode)\(phoneNumber)"
    }
}

// MARK: - High-Level Authentication Flows

@available(iOS 16.4,*)
extension ParaManager {
    /// Handles the complete email authentication flow.
    ///
    /// This method manages the entire email authentication process, including signup/login decision
    /// and verification if needed.
    ///
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    /// - Returns: A tuple containing the authentication status, next required action, and any error message.
    public func handleEmailAuth(
        email: String,
        verificationCode: String? = nil,
        authorizationController: AuthorizationController
    ) async -> (status: EmailAuthStatus, errorMessage: String?) {
        do {
            if let code = verificationCode {
                return try await handleEmailVerification(
                    code: code,
                    email: email,
                    authorizationController: authorizationController
                )
            }
            
            // Use EmailIdentity instead of .email case directly
            let emailIdentity = EmailIdentity(email: email)
            let authState = try await signUpOrLogIn(auth: .identity(emailIdentity))
            
            switch authState.stage {
            case .verify:
                return (.needsVerification, nil)
                
            case .login:
                if authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil {
                    try await loginWithPasskey(
                        authorizationController: authorizationController,
                        authInfo: EmailAuthInfo(email: email)
                    )
                    return (.success, nil)
                } else {
                    return (.error, "Unable to get passkey authentication URL")
                }
                
            case .signup:
                return (.error, "Unexpected authentication state")
            }
        } catch {
            return (.error, String(describing: error))
        }
    }
    
    /// Handles email verification for a new account.
    ///
    /// - Parameters:
    ///   - code: The verification code.
    ///   - email: The user's email address.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    /// - Returns: A tuple containing the authentication status and any error message.
    private func handleEmailVerification(
        code: String,
        email: String,
        authorizationController: AuthorizationController
    ) async throws -> (status: EmailAuthStatus, errorMessage: String?) {
        let authState = try await verifyNewAccount(verificationCode: code)
        
        guard authState.stage == .signup else {
            return (.error, "Unexpected auth stage: \(authState.stage)")
        }
        
        // Get the identifier from auth identity or fall back to email parameter
        let identifier: String
        if let emailIdentity = authState.authIdentity as? EmailIdentity {
            identifier = emailIdentity.email
        } else {
            identifier = email
        }
        
        if let passkeyId = authState.passkeyId {
            try await generatePasskey(
                identifier: identifier,
                biometricsId: passkeyId,
                authorizationController: authorizationController
            )
            
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else if let wallet = authState.externalWalletInfo {
            // For external wallet signup, use the wallet info directly
            try await loginExternalWallet(wallet: wallet)
            return (.success, nil)
        } else if authState.passwordUrl != nil {
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else {
            return (.error, "No authentication method available")
        }
    }
    
    /// Status of the email authentication process.
    public enum EmailAuthStatus {
        /// Authentication successful.
        case success
        /// User needs to verify their email.
        case needsVerification
        /// Error occurred during authentication.
        case error
    }
    
    /// Handles the complete phone authentication flow.
    ///
    /// This method manages the entire phone authentication process, including signup/login decision
    /// and verification if needed.
    ///
    /// - Parameters:
    ///   - phoneNumber: The user's phone number (without country code).
    ///   - countryCode: The country code (without the + prefix).
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    /// - Returns: A tuple containing the authentication status, next required action, and any error message.
    public func handlePhoneAuth(
        phoneNumber: String,
        countryCode: String,
        verificationCode: String? = nil,
        authorizationController: AuthorizationController
    ) async -> (status: PhoneAuthStatus, errorMessage: String?) {
        do {
            if let code = verificationCode {
                return try await handlePhoneVerification(
                    code: code,
                    phoneNumber: phoneNumber,
                    countryCode: countryCode,
                    authorizationController: authorizationController
                )
            }
            
            // Use PhoneIdentity instead of .phone case directly
            let phoneIdentity = PhoneIdentity(phone: phoneNumber, countryCode: countryCode)
            let authState = try await signUpOrLogIn(auth: .identity(phoneIdentity))
            
            switch authState.stage {
            case .verify:
                return (.needsVerification, nil)
                
            case .login:
                if authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil {
                    try await loginWithPasskey(
                        authorizationController: authorizationController,
                        authInfo: PhoneAuthInfo(phone: phoneNumber, countryCode: countryCode)
                    )
                    return (.success, nil)
                } else {
                    return (.error, "Unable to get passkey authentication URL")
                }
                
            case .signup:
                return (.error, "Unexpected authentication state")
            }
        } catch {
            return (.error, String(describing: error))
        }
    }
    
    /// Handles phone verification for a new account.
    ///
    /// - Parameters:
    ///   - code: The verification code.
    ///   - phoneNumber: The user's phone number.
    ///   - countryCode: The country code.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    /// - Returns: A tuple containing the authentication status and any error message.
    private func handlePhoneVerification(
        code: String,
        phoneNumber: String,
        countryCode: String,
        authorizationController: AuthorizationController
    ) async throws -> (status: PhoneAuthStatus, errorMessage: String?) {
        let authState = try await verifyNewAccount(verificationCode: code)
        
        guard authState.stage == .signup else {
            return (.error, "Unexpected auth stage: \(authState.stage)")
        }
        
        // Get the identifier from auth identity or format the phone number
        let identifier: String
        if let phoneIdentity = authState.authIdentity as? PhoneIdentity {
            identifier = formatPhoneNumber(phoneNumber: phoneIdentity.phone, countryCode: phoneIdentity.countryCode)
        } else {
            identifier = formatPhoneNumber(phoneNumber: phoneNumber, countryCode: countryCode)
        }
        
        if let passkeyId = authState.passkeyId {
            try await generatePasskey(
                identifier: identifier,
                biometricsId: passkeyId,
                authorizationController: authorizationController
            )
            
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else if let wallet = authState.externalWalletInfo {
            // For external wallet signup, use the wallet info directly
            try await loginExternalWallet(wallet: wallet)
            return (.success, nil)
        } else if authState.passwordUrl != nil {
            try await createWallet(type: .evm, skipDistributable: false)
            return (.success, nil)
        } else {
            return (.error, "No authentication method available")
        }
    }
    
    /// Status of the phone authentication process.
    public enum PhoneAuthStatus {
        /// Authentication successful.
        case success
        /// User needs to verify their phone number.
        case needsVerification
        /// Error occurred during authentication.
        case error
    }
}

// MARK: - Error Handling

/// Errors that can occur during Para operations.
public enum ParaError: Error, CustomStringConvertible {
    /// An error occurred while executing JavaScript bridge code.
    case bridgeError(String)
    /// The JavaScript bridge did not respond in time.
    case bridgeTimeoutError
    /// A general error occurred.
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

/// Response type for 2FA setup operation
public enum TwoFactorSetupResponse {
    /// 2FA is already set up
    case alreadySetup
    /// 2FA needs to be set up, contains the URI for configuration
    case needsSetup(uri: String)
}
#endif
