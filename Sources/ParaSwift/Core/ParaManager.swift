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
    /// Current package version.
    public static let packageVersion = "1.2.1"
    /// Available Para wallets connected to this instance.
    @Published public var wallets: [Wallet] = []
    /// Current state of the Para Manager session.
    @Published public var sessionState: ParaSessionState = .unknown
    /// API key for Para services.
    public var apiKey: String
    /// Para environment configuration.
    public var environment: ParaEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    /// Indicates if the ParaManager is ready to receive requests.
    public var isReady: Bool {
        return paraWebView.isReady
    }
    // MARK: - Internal Properties
    /// Logger for internal diagnostics.
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
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
    
    // MARK: - Internal Utilities & Bridge Communication
    
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
        var payloadString: String = "<encoding error>"
        if let data: Data = try? JSONEncoder().encode(AnyEncodable(payload)),
           let jsonString: String = String(data: data, encoding: .utf8) {
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
        // Normalize the phone number input by removing whitespace
        let normalizedPhoneNumber = phoneNumber.filter { !$0.isWhitespace }
        return "+\(countryCode)\(normalizedPhoneNumber)"
    }
    
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

// MARK: - Core Authentication Methods

@available(iOS 16.4,*)
extension ParaManager {
    
    /// Extracts authentication information and gets a web challenge.
    ///
    /// - Parameter authInfo: Optional authentication information (email or phone).
    /// - Returns: The web challenge result.
    private func authInfoHelper(authInfo: AuthInfo?) async throws -> Any? {
        let emailArg: String?
        let phoneArg: String?
        let countryCodeArg: String?
        
        if let emailInfo = authInfo as? EmailAuthInfo {
            emailArg = emailInfo.email
            phoneArg = nil
            countryCodeArg = nil
        } else if let phoneInfo = authInfo as? PhoneAuthInfo {
            emailArg = nil
            phoneArg = phoneInfo.phone
            countryCodeArg = phoneInfo.countryCode
        } else {
            emailArg = nil
            phoneArg = nil
            countryCodeArg = nil
        }
        
        let payload = GetWebChallengeArgs(email: emailArg, phone: phoneArg, countryCode: countryCodeArg)
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
    public func verifyNewAccount(verificationCode: String) async throws -> AuthState {
        try await ensureWebViewReady()
        
        let result = try await postMessage(method: "verifyNewAccount", payload: VerifyNewAccountArgs(verificationCode: verificationCode))
        // Log the raw result from the bridge before parsing
        let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager.Verify")
        logger.debug("Raw result from verifyNewAccount bridge call: \(String(describing: result))")
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
}

// MARK: - Wallet Management

@available(iOS 16.4,*)
extension ParaManager {
    /// Creates a new wallet of the specified type, refreshes the wallet list, and returns any recovery secret.
    ///
    /// Note: This function initiates wallet creation and immediately fetches the updated wallet list.
    /// The UI should observe the `wallets` property for updates.
    ///
    /// - Parameters:
    ///   - type: The type of wallet to create.
    ///   - skipDistributable: Whether to skip distributable shares.
    @MainActor
    public func createWallet(type: WalletType, skipDistributable: Bool) async throws {
        try await ensureWebViewReady()
        // Call createWallet but ignore the result as we fetch wallets separately
        _ = try await postMessage(method: "createWallet", payload: CreateWalletArgs(type: type.rawValue, skipDistributable: skipDistributable))

        logger.debug("Wallet creation initiated for type \(type.rawValue). Refreshing wallet list...")

        // Fetch the complete list of wallets to update the list immediately
        let allWallets = try await fetchWallets()

        // Update the local wallets list with the complete fetched data
        self.wallets = allWallets
        self.sessionState = .activeLoggedIn // Update state as wallet creation implies login

        logger.debug("Wallet list refreshed after creation. Found \(allWallets.count) wallets.")

        // No return value
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
    
    /// Helper method to refresh wallets with retry logic
    private func refreshWalletsWithRetry(maxAttempts: Int = 5, isSignup: Bool = false) async {
        let logger: Logger = Logger(subsystem: "com.paraSwift", category: "WalletRefresh")
        
        // For signup, wallets can take longer to be available
        let delayBetweenAttempts: UInt64 = isSignup ? 3_000_000_000 : 1_500_000_000 // 3 seconds for signup, 1.5 for login
        
        for attempt in 1...maxAttempts {
            do {
                logger.debug("Attempting to fetch wallets (attempt \(attempt)/\(maxAttempts))...")
                let newWallets: [Wallet] = try await fetchWallets()
                
                if !newWallets.isEmpty {
                    logger.debug("Successfully fetched \(newWallets.count) wallets")
                    self.wallets = newWallets
                    
                    // Ensure session state is updated
                    self.sessionState = .activeLoggedIn
                    return
                } else {
                    logger.debug("Fetched empty wallet list, retrying in \(delayBetweenAttempts/1_000_000_000) seconds...")
                    
                    // Check if we're logged in even though wallets aren't available yet
                    if let isLoggedIn: Bool = try? await isFullyLoggedIn(), isLoggedIn {
                        logger.debug("User is fully logged in despite no wallets yet - continuing to wait")
                    }
                    
                    try await Task.sleep(nanoseconds: delayBetweenAttempts)
                }
            } catch {
                logger.error("Error fetching wallets: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: delayBetweenAttempts)
            }
        }
        
        logger.warning("Failed to fetch wallets after \(maxAttempts) attempts")
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

// MARK: - High-Level Authentication Flows

@available(iOS 16.4,*)
extension ParaManager {
    
    // Internal enum for unified auth flow status
    private enum AuthFlowStatus {
        case success
        case needsVerification
        case error(String?)
    }

    /// Orchestrates the main authentication flow (signup/login/verify).
    private func _handleAuthFlow(
        authIdentity: AuthIdentity,
        authInfoForPasskeyLogin: AuthInfo?, // Optional because verification doesn't need it
        identifierForPasskeySignup: String,
        verificationCode: String? = nil,
        authMethod: AuthMethod,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession? = nil
    ) async -> AuthFlowStatus {
        do {
            if let code = verificationCode {
                // --- Verification Flow ---
                let authState: AuthState = try await verifyNewAccount(verificationCode: code)
                guard authState.stage == .signup else {
                    return .error("Unexpected auth stage after verification: \(authState.stage)")
                }
                
                let signupSuccess: Bool = await _completeSignup(
                    authState: authState,
                    identifier: identifierForPasskeySignup,
                    authMethod: authMethod,
                    authorizationController: authorizationController,
                    webAuthenticationSession: webAuthenticationSession
                )
                return signupSuccess ? .success : .error("Signup completion failed after verification.")

            } else {
                // --- Initial Signup/Login Flow ---
                let authState: AuthState = try await signUpOrLogIn(auth: .identity(authIdentity))

                switch authState.stage {
                case .verify:
                    return .needsVerification

                case .login:
                    guard let authInfo = authInfoForPasskeyLogin else {
                         return .error("Internal error: AuthInfo missing for login stage.")
                    }
                    let loginSuccess: Bool = await _completeLogin(
                        authState: authState,
                        authInfo: authInfo,
                        authMethod: authMethod,
                        authorizationController: authorizationController,
                        webAuthenticationSession: webAuthenticationSession
                    )
                    return loginSuccess ? .success : .error("Login completion failed.")

                case .signup:
                    // This case might happen if verification was skipped server-side (e.g., trusted device)
                    // Treat it like the verification flow's signup completion path.
                    logger.debug("Received signup stage directly from signUpOrLogIn - attempting signup completion.")
                    let signupSuccess: Bool = await _completeSignup(
                        authState: authState,
                        identifier: identifierForPasskeySignup,
                        authMethod: authMethod,
                        authorizationController: authorizationController,
                        webAuthenticationSession: webAuthenticationSession
                    )
                    // If signup completion fails here, it's an error.
                    return signupSuccess ? .success : .error("Direct signup completion failed.")
                }
            }
        } catch let error as ParaError {
             logger.error("ParaError during auth flow: \(error.description)")
             return .error(error.description)
        } catch {
            let errorMsg: String = "Unexpected error during auth flow: \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            return .error(errorMsg)
        }
    }

    /// Handles the completion of the signup process (post-verification or direct signup).
    private func _completeSignup(
        authState: AuthState,
        identifier: String,
        authMethod: AuthMethod,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession?
    ) async -> Bool {
        do {
            switch authMethod {
            case .password:
                guard let passwordUrl: String = authState.passwordUrl else {
                    logger.error("Password auth requested for signup, but no passwordUrl available.")
                    return false
                }
                guard let webAuthSession: WebAuthenticationSession = webAuthenticationSession else {
                    logger.error("WebAuthenticationSession required for password signup.")
                    return false
                }
                // presentPasswordUrl handles wallet creation internally for signup=true
                if let _: URL = try await presentPasswordUrl(passwordUrl, webAuthenticationSession: webAuthSession, isSignup: true) {
                    return true
                } else {
                    logger.error("Password signup failed or timed out.")
                    return false
                }
                
            case .passkey:
                // Check for passkey first
                if let passkeyId: String = authState.passkeyId {
                    try await generatePasskey(
                        identifier: identifier,
                        biometricsId: passkeyId,
                        authorizationController: authorizationController
                    )
                    // Explicitly create wallet after generating passkey
                    logger.debug("Explicitly calling createWallet after passkey generation (signup flow).")
                    try await createWallet(type: .evm, skipDistributable: false)
                    self.sessionState = .activeLoggedIn // Assume success if createWallet doesn't throw
                    return true
                }
                
                // If no passkeyId, check for external wallet signup
                if let wallet: ExternalWalletInfo = authState.externalWalletInfo {
                    logger.debug("Completing signup via external wallet login.")
                    try await loginExternalWallet(wallet: wallet) // loginExternalWallet sets state
                    return true
                }
                
                // If neither passkey nor external wallet, it's an error for the .passkey case
                logger.error("Passkey auth requested for signup, but no passkeyId or externalWalletInfo available.")
                return false
            }
        } catch {
            let errorMsg: String = "Error during signup completion (method: \(authMethod)): \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            // Ensure state reflects potential failure if createWallet/loginExternalWallet failed
             if self.sessionState == .activeLoggedIn { // Check if state was optimistically set
                 // Attempt to check actual logged-in status, default to inactive on error
                 self.sessionState = (try? await isFullyLoggedIn()) == true ? .activeLoggedIn : .inactive
             }
            return false
        }
    }

    /// Handles the completion of the login process.
    private func _completeLogin(
        authState: AuthState,
        authInfo: AuthInfo,
        authMethod: AuthMethod,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession?
    ) async -> Bool {
        do {
            switch authMethod {
            case .password:
                guard let passwordUrl: String = authState.passwordUrl else {
                    logger.error("Password auth requested for login, but no passwordUrl available.")
                    return false
                }
                guard let webAuthSession: WebAuthenticationSession = webAuthenticationSession else {
                    logger.error("WebAuthenticationSession required for password login.")
                    return false
                }
                if let _: URL = try await presentPasswordUrl(passwordUrl, webAuthenticationSession: webAuthSession, isSignup: false) {
                    return true // presentPasswordUrl handles state update on success
                } else {
                     logger.error("Password login failed.")
                     return false
                }
                
            case .passkey:
                guard authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil else {
                    logger.error("Passkey auth requested for login, but no passkey URLs available.")
                    return false
                }
                // Use the provided authInfo (EmailAuthInfo or PhoneAuthInfo)
                 try await loginWithPasskey(
                    authorizationController: authorizationController,
                    authInfo: authInfo
                 )
                 return true // loginWithPasskey handles state update
            }
        } catch {
            let errorMsg: String = "Error during login completion (method: \(authMethod)): \(error.localizedDescription)"
            logger.error("\(errorMsg)")
            // Reset state on login error
            self.sessionState = .inactive
            return false
        }
    }

    /// Handles the complete email authentication flow.
    ///
    /// This method manages the entire email authentication process, including signup/login decision
    /// and verification if needed. It supports both passkey and password authentication.
    ///
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage.
    ///   - authMethod: The intended authentication method.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    ///   - webAuthenticationSession: Required when using password authentication to present the password URL.
    /// - Returns: A tuple containing the authentication status and any error message.
    public func handleEmailAuth(
        email: String,
        verificationCode: String? = nil,
        authMethod: AuthMethod, // UPDATED
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession? = nil
    ) async -> (status: EmailAuthStatus, errorMessage: String?) {

        let emailIdentity = EmailIdentity(email: email)
        let emailAuthInfo = EmailAuthInfo(email: email) // Needed for loginWithPasskey

        let flowStatus = await _handleAuthFlow(
            authIdentity: emailIdentity,
            authInfoForPasskeyLogin: emailAuthInfo,
            identifierForPasskeySignup: email, // Use raw email for passkey generation identifier
            verificationCode: verificationCode,
            authMethod: authMethod, // UPDATED
            authorizationController: authorizationController,
            webAuthenticationSession: webAuthenticationSession
        )

        switch flowStatus {
        case .success:
            return (.success, nil)
        case .needsVerification:
            return (.needsVerification, nil)
        case .error(let message):
            return (.error, message)
        }
    }

    /// Handles the complete phone authentication flow.
    ///
    /// This method manages the entire phone authentication process, including signup/login decision
    /// and verification if needed. It supports both passkey and password authentication.
    ///
    /// - Parameters:
    ///   - phoneNumber: The user's phone number (without country code).
    ///   - countryCode: The country code (without the + prefix).
    ///   - verificationCode: Optional verification code, to be provided if the first call results in a verify stage.
    ///   - authMethod: The intended authentication method.
    ///   - authorizationController: The AuthorizationController to use for passkey operations.
    ///   - webAuthenticationSession: Required when using password authentication to present the password URL.
    /// - Returns: A tuple containing the authentication status, next required action, and any error message.
    public func handlePhoneAuth(
        phoneNumber: String,
        countryCode: String,
        verificationCode: String? = nil,
        authMethod: AuthMethod, // UPDATED
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession? = nil
    ) async -> (status: PhoneAuthStatus, errorMessage: String?) {

        // Normalize phone number: remove spaces and potentially other common formatting characters
        let normalizedPhoneNumber = phoneNumber.filter { !$0.isWhitespace } 

        let phoneIdentity = PhoneIdentity(phone: normalizedPhoneNumber, countryCode: countryCode)
        let phoneAuthInfo = PhoneAuthInfo(phone: normalizedPhoneNumber, countryCode: countryCode) // Needed for loginWithPasskey
        let formattedPhoneNumber = formatPhoneNumber(phoneNumber: normalizedPhoneNumber, countryCode: countryCode) // Needed for passkey generation

        let flowStatus = await _handleAuthFlow(
            authIdentity: phoneIdentity,
            authInfoForPasskeyLogin: phoneAuthInfo,
            identifierForPasskeySignup: formattedPhoneNumber,
            verificationCode: verificationCode,
            authMethod: authMethod, // UPDATED
            authorizationController: authorizationController,
            webAuthenticationSession: webAuthenticationSession
        )

        switch flowStatus {
        case .success:
            return (.success, nil)
        case .needsVerification:
            return (.needsVerification, nil)
        case .error(let message):
            return (.error, message)
        }
    }

    /// Presents a password URL using a web authentication session and verifies authentication completion.
    /// This implementation mimics the web-sdk waitForWalletCreation and waitForSignup methods.
    /// 
    /// - Parameters:
    ///   - url: The password authentication URL to present
    ///   - webAuthenticationSession: The session to use for presenting the URL
    ///   - isSignup: Whether this is a new account signup (true) or login (false)
    /// - Returns: The callback URL if authentication was successful, nil otherwise
    public func presentPasswordUrl(_ url: String, webAuthenticationSession: WebAuthenticationSession, isSignup: Bool = false) async throws -> URL? {
        let logger = Logger(subsystem: "com.paraSwift", category: "PasswordAuth")
        guard let originalPasswordUrl = URL(string: url) else {
            throw ParaError.error("Invalid password authentication URL")
        }
        
        // Add nativeCallbackUrl query parameter for ASWebAuthenticationSession
        var components = URLComponents(url: originalPasswordUrl, resolvingAgainstBaseURL: false)
        let callbackQueryItem = URLQueryItem(name: "nativeCallbackUrl", value: deepLink + "://")
        // Resolve overlapping access warning by modifying a local variable
        var currentQueryItems = components?.queryItems ?? []
        currentQueryItems.append(callbackQueryItem)
        components?.queryItems = currentQueryItems

        guard let finalPasswordUrl = components?.url else {
            throw ParaError.error("Failed to construct final password URL with callback parameter")
        }
        
        logger.debug("Presenting password authentication URL (\(isSignup ? "signup" : "login")) with native callback: \(finalPasswordUrl.absoluteString)")
        
        // When the web portal calls window.close() after password creation/login,
        // ASWebAuthenticationSession throws a canceledLogin error, which we need to handle as success
        do {
            // Attempt to authenticate with the web session using the modified URL
            let callbackURL = try await webAuthenticationSession.authenticate(using: finalPasswordUrl, callbackURLScheme: deepLink)
            // Normal callback URL completion (rare for password auth)
            logger.debug("Received callback URL: \(callbackURL.absoluteString)")
            
            // For standard callback completion, update state immediately
            self.sessionState = try await isFullyLoggedIn() ? .activeLoggedIn : .active
            try await fetchWallets()
            
            return callbackURL
        } catch {
            // This is expected for password auth - handle as intentional window close
            logger.debug("WebAuthenticationSession ended, likely due to window.close(): \(error.localizedDescription)")

            // Removed polling. Assume success based on window close and proceed.

            if isSignup {
                // --- Signup Flow ---
                logger.debug("Attempting explicit wallet creation (signup flow)...")
                do {
                    _ = try await createWallet(type: .evm, skipDistributable: false)
                    logger.debug("Successfully called createWallet (signup flow)")
                    self.sessionState = .activeLoggedIn
                    // Attempt to fetch wallets once immediately after creation
                    await refreshWalletsWithRetry(maxAttempts: 1, isSignup: true)
                    logger.debug("Signup flow completed.")
                    return URL(string: "success://password.signup.completed")
                } catch {
                    logger.error("Error explicitly calling createWallet during signup: \(error.localizedDescription)")
                    self.sessionState = .inactive // Revert state if wallet creation failed
                    return nil // Indicate failure
                }
            } else {
                // --- Login Flow ---
                logger.debug("Assuming login success (login flow). Setting state and fetching wallets...")
                self.sessionState = .activeLoggedIn
                // Attempt to fetch wallets once immediately after login assumption
                await refreshWalletsWithRetry(maxAttempts: 1, isSignup: false)
                 logger.debug("Login flow completed.")
                return URL(string: "success://password.login.completed")
            }
        }
    }
}

// MARK: - Supporting Types & Enums

@available(iOS 16.4,*)
extension ParaManager {
    
    /// Specifies the intended authentication method.
    public enum AuthMethod {
        case passkey
        case password
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
