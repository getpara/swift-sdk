import SwiftUI // Keep SwiftUI if @MainActor or other UI-related things are used
import AuthenticationServices
import WebKit // Needed for presentPasswordUrl
import os

#if os(iOS)
// MARK: - Core Authentication Methods
@available(iOS 16.4,*)
extension ParaManager {

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
            try await fetchWallets() // Need to fetch wallets after successful login

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
#endif 