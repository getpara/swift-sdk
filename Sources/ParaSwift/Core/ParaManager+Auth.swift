import SwiftUI
import AuthenticationServices
import WebKit
import os

// MARK: - Internal Authentication Helpers and Types
extension ParaManager {

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
            return SignUpOrLogInPayload(auth: PhoneIdentity(phone: phoneNumber))
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
            } else if let phone = auth["phone"] as? String {
                authIdentity = PhoneIdentity(phone: phone)
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

    /// Extracts authentication information and gets a web challenge.
    ///
    /// - Parameter authInfo: Optional authentication information (email or phone).
    /// - Returns: The web challenge result.
    private func authInfoHelper(authInfo: AuthInfo?) async throws -> Any? {
        let emailArg: String?
        let phoneArg: String?

        if let emailInfo = authInfo as? EmailAuthInfo {
            emailArg = emailInfo.email
            phoneArg = nil
        } else if let phoneInfo = authInfo as? PhoneAuthInfo {
            emailArg = nil
            phoneArg = phoneInfo.phone
            
            logger.debug("Phone login with phone: \(phoneArg ?? "nil")")
        } else {
            emailArg = nil
            phoneArg = nil
        }

        let payload = GetWebChallengeArgs(email: emailArg, phone: phoneArg)
        return try await postMessage(method: "getWebChallenge", payload: payload)
    }
}

// MARK: - Authentication Types and Methods
extension ParaManager {
    /// Enum defining the possible methods for login when the stage is .login
    public enum LoginMethod: String, CustomStringConvertible {
        case passkey
        case password
        case passkeyKnownDevice // If applicable in future
        
        public var description: String {
            return self.rawValue
        }
    }

    /// Enum defining the possible methods for signup when the stage is .signup
    public enum SignupMethod: String, CustomStringConvertible {
        case passkey
        case password
        
        public var description: String {
            return self.rawValue
        }
    }
    
    /// Signs up a new user or logs in an existing user
    /// - Parameter auth: Authentication information (email or phone)
    /// - Returns: AuthState object containing information about the next steps
    internal func signUpOrLogIn(auth: Auth) async throws -> AuthState {
        try await ensureWebViewReady()

        let payload = createSignUpOrLogInPayload(from: auth)

        let result = try await postMessage(method: "signUpOrLogIn", payload: payload)
        let authState = try parseAuthStateFromResult(result)

        if authState.stage == .verify || authState.stage == .login {
            self.sessionState = .active
        }

        return authState
    }
    
    /// Initiates the email/phone authentication flow (signup or login).
    /// Determines if the user exists and returns the appropriate next state.
    /// - Parameter auth: The authentication identifier (Email, Phone, ExternalWallet, or Identity).
    /// - Returns: The `AuthState` indicating the next step (.verify for new users, .login for existing users).
    @MainActor
    public func initiateAuthFlow(auth: Auth) async throws -> AuthState {
        logger.debug("Initiating auth flow with: \(auth.debugDescription)")
        let authState = try await signUpOrLogIn(auth: auth)
        logger.debug("Auth flow initiated. Resulting stage: \(authState.stage.rawValue)")
        return authState
    }
    
    /// Check if a specific login method is available for the given authentication state.
    /// - Parameters:
    ///   - method: The login method to check availability for.
    ///   - authState: The current authentication state.
    /// - Returns: Boolean indicating if the method is available.
    public func isLoginMethodAvailable(method: LoginMethod, authState: AuthState) -> Bool {
        guard authState.stage == .login else {
            return false
        }
        
        switch method {
        case .passkey:
            return authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil
        case .password:
            return authState.passwordUrl != nil
        case .passkeyKnownDevice:
            return authState.passkeyKnownDeviceUrl != nil
        }
    }
    
    /// Determines which login method to use when a user has previously registered.
    /// This prioritizes passkeys for security when available.
    /// 
    /// - Parameter authState: The current authentication state
    /// - Returns: The recommended login method to use
    private func determinePreferredLoginMethod(authState: AuthState) -> LoginMethod? {
        guard authState.stage == .login else {
            logger.error("determinePreferredLoginMethod called with invalid stage: \(authState.stage.rawValue)")
            return nil
        }
        
        // Check if we have both password and passkey options available
        let hasPasswordOption = authState.passwordUrl != nil
        let hasPasskeyOption = authState.passkeyUrl != nil || authState.passkeyKnownDeviceUrl != nil
        
        // Prioritize passkeys when available as they are more secure
        if hasPasskeyOption {
            return .passkey
        }
        
        // Fall back to password if passkey is not available
        if hasPasswordOption {
            return .password
        }
        
        return nil
    }
}

// MARK: - Verification Methods
extension ParaManager {
    /// Verifies a new account with the provided verification code
    /// - Parameter verificationCode: The verification code sent to the user
    /// - Returns: AuthState object containing information about the next steps
    public func verifyNewAccount(verificationCode: String) async throws -> AuthState {
        try await ensureWebViewReady()

        let result = try await postMessage(method: "verifyNewAccount", payload: VerifyNewAccountArgs(verificationCode: verificationCode))
        // Log the raw result from the bridge before parsing
        let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager.Verify")
        logger.debug("Raw result from verifyNewAccount bridge call received")
        let authState = try parseAuthStateFromResult(result)

        if authState.stage == .signup {
            self.sessionState = .active
        }

        return authState
    }
    
    /// Handles the verification step for a new user.
    /// Assumes the initial `authState.stage` was `.verify`.
    /// - Parameter verificationCode: The code entered by the user.
    /// - Returns: The `AuthState` indicating the next step (expected to be `.signup`).
    @MainActor
    public func handleVerificationCode(verificationCode: String) async throws -> AuthState {
        logger.debug("Handling verification code...")
        let newState = try await verifyNewAccount(verificationCode: verificationCode)
        logger.debug("Verification code handled. Resulting stage: \(newState.stage.rawValue)")
        
        guard newState.stage == .signup else {
            logger.error("Verification completed but resulted in unexpected stage: \(newState.stage.rawValue)")
            throw ParaError.bridgeError("Verification resulted in unexpected state.")
        }
        return newState
    }
    
    /// Resend verification code for account verification
    public func resendVerificationCode() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "resendVerificationCode", payload: EmptyPayload())
    }
}

// MARK: - Passkey Authentication
extension ParaManager {
    /// Logs in with passkey authentication.
    ///
    /// - Parameters:
    ///   - authorizationController: The controller to handle authorization UI.
    ///   - authInfo: Optional authentication information (email or phone).
    @MainActor
    public func loginWithPasskey(authorizationController: AuthorizationController, authInfo: AuthInfo?) async throws {
        let getWebChallengeResult = try await authInfoHelper(authInfo: authInfo)
        let challenge = try decodeDictionaryResult(
            getWebChallengeResult,
            expectedType: String.self,
            method: "getWebChallenge",
            key: "challenge"
        )
        
        // Get allowedPublicKeys from the bridge response
        let allowedPublicKeys = try decodeDictionaryResult(
            getWebChallengeResult,
            expectedType: [String]?.self,
            method: "getWebChallenge",
            key: "allowedPublicKeys"
        ) ?? []
        
        // Log the number of keys we received
        if allowedPublicKeys.isEmpty {
            logger.debug("No specific public keys provided for this account. Will show all available passkeys.")
        } else {
            logger.debug("Received \(allowedPublicKeys.count) specific public keys for this account.")
        }

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
        
        let verifyWebChallengeResult = try await postMessage(
            method: "verifyWebChallenge",
            payload: verifyArgs
        )
        
        let userId = try decodeResult(verifyWebChallengeResult, expectedType: String.self, method: "verifyWebChallenge")

        let loginArgs = LoginWithPasskeyArgs(
            userId: userId,
            credentialsId: id,
            userHandle: signIntoPasskeyAccountResult.userID.base64URLEncodedString()
        )
        
        let loginResult = try await postMessage(
            method: "loginWithPasskey",
            payload: loginArgs
        )
        if let _ = loginResult as? [String: Any] {
            logger.debug("loginWithPasskey bridge call returned wallet data")
        }

        self.wallets = try await fetchWallets()
        sessionState = .activeLoggedIn
    }

    /// Generate a new passkey for authentication
    /// - Parameters:
    ///   - identifier: The user identifier
    ///   - biometricsId: The biometrics ID for the passkey
    ///   - authorizationController: The controller to handle authorization UI
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
        
        _ = try await postMessage(
            method: "generatePasskey",
            payload: generateArgs
        )
    }
}

// MARK: - Password Authentication
extension ParaManager {
    /// Presents a password URL using a web authentication session and verifies authentication completion.
    /// The caller is responsible for handling subsequent steps like wallet creation if needed.
    ///
    /// - Parameters:
    ///   - url: The password authentication URL to present
    ///   - webAuthenticationSession: The session to use for presenting the URL
    /// - Returns: The callback URL if authentication was successful via direct callback, or a success placeholder URL if the window was closed (interpreted as success). Returns nil on failure.
    public func presentPasswordUrl(_ url: String, webAuthenticationSession: WebAuthenticationSession) async throws -> URL? {
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

        logger.debug("Presenting password authentication URL with native callback \(finalPasswordUrl.absoluteString)")

        // When the web portal calls window.close() after password creation/login,
        // ASWebAuthenticationSession throws a canceledLogin error, which we need to handle as success
        do {
            // Attempt to authenticate with the web session using the modified URL
            let callbackURL = try await webAuthenticationSession.authenticate(using: finalPasswordUrl, callbackURLScheme: deepLink)
            // Normal callback URL completion (rare for password auth)
            logger.debug("Received callback URL from authentication session")
            
            self.wallets = try await self.fetchWallets()

            return callbackURL
        } catch {
            logger.error("WebAuthenticationSession failed with unexpected error: \(error.localizedDescription)")
            throw error // Rethrow the specific error
        }
    }
}

// MARK: - External Wallet Authentication
extension ParaManager {
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
            logger.debug("loginExternalWallet completed. Returned AuthState with userId: \(authState.userId)")
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

// MARK: - Two-Factor Authentication
extension ParaManager {
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
        struct Enable2faArgs: Encodable {
            let verificationCode: String
        }
        let payload = Enable2faArgs(verificationCode: verificationCode)
        _ = try await postMessage(method: "enable2fa", payload: payload)
    }
}

// MARK: - High-Level Auth Workflow Methods
extension ParaManager {
    /// Handles the login process for an existing user with the specified method.
    /// Assumes the `authState.stage` is `.login`.
    /// - Parameters:
    ///   - authState: The current `AuthState` (must be in `.login` stage).
    ///   - method: The user's chosen login method (`.passkey` or `.password`).
    ///   - authorizationController: Required for passkey operations.
    ///   - webAuthenticationSession: Required for password operations.
    /// - Throws: Error if login fails or the chosen method is unavailable.
    @MainActor
    public func handleLoginWithMethod(
        authState: AuthState,
        method: LoginMethod,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession
    ) async throws {
        guard authState.stage == .login else {
            logger.error("handleLoginWithMethod called with invalid stage: \(authState.stage.rawValue)")
            throw ParaError.error("Invalid application state: Expected login stage.")
        }

        logger.debug("Handling login with method: \(method.description) for userId: \(authState.userId)")

        switch method {
        case .passkey:
            guard let authIdentity = authState.authIdentity else {
                throw ParaError.error("Cannot perform passkey login without original auth identity.")
            }
            
            // loginWithPasskey needs AuthInfo derived from the identity
            let authInfo: AuthInfo?
            if let emailIdentity = authIdentity as? EmailIdentity {
                authInfo = EmailAuthInfo(email: emailIdentity.email)
            } else if let phoneIdentity = authIdentity as? PhoneIdentity {
                authInfo = PhoneAuthInfo(phone: phoneIdentity.phone)
            } else {
                // Should not happen if signUpOrLogIn returned .login for email/phone
                logger.warning("Passkey login attempted with unexpected identity type")
                authInfo = nil // Let loginWithPasskey handle nil if appropriate
            }

            logger.debug("Calling loginWithPasskey...")
            try await loginWithPasskey(
                authorizationController: authorizationController,
                authInfo: authInfo // Pass derived AuthInfo
            )
            logger.debug("loginWithPasskey successful.")
            // `loginWithPasskey` internally sets sessionState and fetches wallets.

        case .password:
            guard let passwordUrl = authState.passwordUrl else {
                logger.error("Password login selected but no passwordUrl found in AuthState.")
                throw ParaError.error("Password login option is unavailable.")
            }
            logger.debug("Calling presentPasswordUrl for login...")
            let resultUrl = try await presentPasswordUrl(
                passwordUrl,
                webAuthenticationSession: webAuthenticationSession
            )

            // Check if the result indicates success
            if resultUrl != nil {
                logger.debug("presentPasswordUrl successful for login.")
                // Password login success path requires explicit state update and wallet fetch
                self.wallets = try await self.fetchWallets()
                self.sessionState = .activeLoggedIn
            } else {
                // Should only happen if webAuthenticationSession throws internally and presentPasswordUrl catches/returns nil
                logger.warning("Password login flow seemed to fail (nil result from presentPasswordUrl).")
                throw ParaError.error("Password login failed or was cancelled.")
            }

        case .passkeyKnownDevice:
            logger.error("PasskeyKnownDevice login method not yet implemented.")
            throw ParaError.notImplemented("PasskeyKnownDevice login")
        }
        logger.info("Login successful via \(method.description). Session active.")
    }
    
    /// Handles the login process for an existing user by automatically determining 
    /// and using the preferred login method.
    /// Assumes the `authState.stage` is `.login`.
    /// - Parameters:
    ///   - authState: The current `AuthState` (must be in `.login` stage).
    ///   - authorizationController: Required for passkey operations.
    ///   - webAuthenticationSession: Required for password operations.
    /// - Throws: Error if login fails or no login methods are available.
    /// - Note: This is a convenience method that uses `handleLoginWithMethod` with the best available method.
    @MainActor
    public func handleLogin(
        authState: AuthState,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession
    ) async throws {
        guard authState.stage == .login else {
            logger.error("handleLogin called with invalid stage: \(authState.stage.rawValue)")
            throw ParaError.error("Invalid application state: Expected login stage.")
        }
        
        // Determine the preferred login method automatically
        guard let preferredMethod = determinePreferredLoginMethod(authState: authState) else {
            logger.error("No login methods available for userId: \(authState.userId)")
            throw ParaError.error("No login methods available for this account.")
        }
        
        logger.debug("Automatically selected login method: \(preferredMethod.description) for userId: \(authState.userId)")
        
        // Use the method-specific implementation
        try await handleLoginWithMethod(
            authState: authState,
            method: preferredMethod,
            authorizationController: authorizationController,
            webAuthenticationSession: webAuthenticationSession
        )
    }

    /// Determines which signup method to use when a user is creating an account.
    /// This prioritizes passkeys for security when available.
    /// 
    /// - Parameter authState: The current authentication state
    /// - Returns: The recommended signup method to use
    private func determinePreferredSignupMethod(authState: AuthState) -> SignupMethod? {
        guard authState.stage == .signup else {
            logger.error("determinePreferredSignupMethod called with invalid stage: \(authState.stage.rawValue)")
            return nil
        }
        
        // Check for available signup options
        let hasPasskeyOption = authState.passkeyId != nil
        let hasPasswordOption = authState.passwordUrl != nil
        
        // Prioritize passkeys when available as they are more secure
        if hasPasskeyOption {
            return .passkey
        }
        
        // Fall back to password if passkey is not available
        if hasPasswordOption {
            return .password
        }
        
        return nil
    }
    
    /// Check if a specific signup method is available for the given authentication state.
    /// - Parameters:
    ///   - method: The signup method to check availability for.
    ///   - authState: The current authentication state.
    /// - Returns: Boolean indicating if the method is available.
    public func isSignupMethodAvailable(method: SignupMethod, authState: AuthState) -> Bool {
        guard authState.stage == .signup else {
            return false
        }
        
        switch method {
        case .passkey:
            return authState.passkeyId != nil
        case .password:
            return authState.passwordUrl != nil
        }
    }
    
    /// Handles the signup process for a new user with the specified method.
    /// Assumes the `authState.stage` is `.signup`.
    /// - Parameters:
    ///   - authState: The current `AuthState` (must be in `.signup` stage).
    ///   - method: The user's chosen signup method (`.passkey` or `.password`).
    ///   - authorizationController: Required for passkey operations.
    ///   - webAuthenticationSession: Required for password operations.
    /// - Throws: Error if signup fails or the chosen method is unavailable.
    @MainActor
    public func handleSignup(
        authState: AuthState,
        method: SignupMethod,
        authorizationController: AuthorizationController,
        webAuthenticationSession: WebAuthenticationSession
    ) async throws {
        guard authState.stage == .signup else {
            logger.error("handleSignup called with invalid stage: \(authState.stage.rawValue)")
            throw ParaError.error("Invalid application state: Expected signup stage.")
        }
        
        guard let identifier = authState.authIdentity?.identifier else {
            logger.error("Cannot perform signup without user identifier in AuthState.")
            throw ParaError.error("Missing user identifier for signup.")
        }
        
        logger.debug("Handling signup with method: \(method.description) for userId: \(authState.userId)")
        
        // Execute the signup workflow based on the specified method
        switch method {
        case .passkey:
            guard let passkeyId = authState.passkeyId else {
                logger.error("Passkey signup selected but no passkeyId found in AuthState.")
                throw ParaError.error("Passkey signup option is unavailable.")
            }
            logger.debug("Generating passkey with id: \(passkeyId)")
            try await generatePasskey(
                identifier: identifier, // Use identifier from authState
                biometricsId: passkeyId,
                authorizationController: authorizationController
            )
            logger.debug("Passkey generated. Creating wallet...")
            _ = try await createWallet(type: .evm, skipDistributable: false) // Assuming default EVM
            logger.debug("Wallet created after passkey signup.")

        case .password:
            guard let passwordUrl = authState.passwordUrl else {
                logger.error("Password signup selected but no passwordUrl found in AuthState.")
                throw ParaError.error("Password signup option is unavailable.")
            }
            logger.debug("Calling presentPasswordUrl for signup...")
            let resultUrl = try await presentPasswordUrl(
                passwordUrl,
                webAuthenticationSession: webAuthenticationSession
            )

            // Check if the result indicates success
            if resultUrl != nil {
                logger.debug("presentPasswordUrl successful for signup.")
                logger.debug("Creating wallet after password signup...")
                _ = try await createWallet(type: .evm, skipDistributable: false) // Assuming default EVM
                logger.debug("Wallet created after password signup.")
            } else {
                logger.warning("Password signup flow seemed to fail (nil result from presentPasswordUrl).")
                throw ParaError.error("Password setup failed or was cancelled.")
            }
        }

        // Common success path for both methods: Update state and fetch wallets
        self.wallets = try await fetchWallets()
        self.sessionState = .activeLoggedIn
        logger.info("Signup successful via \(method.description). Session active.")
    }
}
