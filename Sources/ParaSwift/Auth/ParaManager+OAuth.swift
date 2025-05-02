//
//  ParaManager+OAuth.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

import SwiftUI
import AuthenticationServices
import os

// MARK: - OAuth Provider Types

/// Supported OAuth provider types for authentication
public enum OAuthProvider: String {
    /// Google authentication provider
    case google = "GOOGLE"
    /// Discord authentication provider
    case discord = "DISCORD"
    /// Apple authentication provider
    case apple = "APPLE"
}

// MARK: - Private OAuth Parameter Structures

/// Struct for OAuth URL parameters that conforms to Encodable
private struct OAuthUrlParams: Encodable {
    /// The OAuth method/provider name
    let method: String
    /// The deeplink URL for redirecting back to the app
    let deeplinkUrl: String
}

/// Struct for verifyOAuth parameters that conforms to Encodable
private struct VerifyOAuthParams: Encodable {
    /// The OAuth method/provider name
    let method: String
    /// The deeplink URL with verification data
    let deeplinkUrl: String
}

// MARK: - OAuth Authentication Methods

extension ParaManager {
    /// Verifies an OAuth authentication and returns an AuthState object according to the V2 authentication flow
    /// - Parameters:
    ///   - provider: The OAuth provider to verify
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    /// - Returns: An AuthState object containing information about the next steps in the authentication flow
    internal func verifyOAuth(provider: OAuthProvider, webAuthenticationSession: WebAuthenticationSession) async throws -> AuthState {
        let logger = Logger(subsystem: "com.paraSwift", category: "OAuth")
        try await ensureWebViewReady()
        
        // Step 1: Prepare and get the OAuth URL
        logger.debug("Getting OAuth URL for provider: \(provider.rawValue)")
        let oAuthParams = OAuthUrlParams(method: provider.rawValue, deeplinkUrl: deepLink)
        
        let oAuthUrlResult = try await paraWebView.postMessage(method: "getOAuthUrl", payload: oAuthParams)
        guard let oAuthURL = oAuthUrlResult as? String, let url = URL(string: oAuthURL) else {
            throw ParaError.error("Invalid OAuth URL")
        }
        logger.debug("Received OAuth URL: \(oAuthURL)")
        
        // Step 2: Extract session information if available
        _ = extractSessionLookupId(from: oAuthURL, logger: logger)
        
        // Step 3: Perform the authentication flow
        let callbackURL = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: deepLink)
        let callbackUrlString = callbackURL.absoluteString
        logger.debug("Received callback URL: \(callbackUrlString)")
        
        // Step 4: Verify the OAuth response
        let verifyParams = VerifyOAuthParams(
            method: provider.rawValue,
            deeplinkUrl: callbackUrlString
        )
        
        logger.debug("Calling verifyOAuth with provider: \(provider.rawValue)")
        let result = try await paraWebView.postMessage(method: "verifyOAuth", payload: verifyParams)
        
        // Step 5: Process the verification result
        let authState = try processOAuthResult(result, logger: logger)
        logger.debug("OAuth verification completed with stage: \(authState.stage.rawValue)")
        
        return authState
    }
    
    /// Handles the complete OAuth authentication flow, including processing the authentication state
    /// and performing the appropriate login or signup actions based on the result.
    /// - Parameters:
    ///   - provider: The OAuth provider to authenticate with
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    ///   - authorizationController: The AuthorizationController to use for passkey operations
    /// - Returns: A tuple containing the result status and any error message
    public func handleOAuth(
        provider: OAuthProvider,
        webAuthenticationSession: WebAuthenticationSession,
        authorizationController: AuthorizationController
    ) async -> (success: Bool, errorMessage: String?) {
        let logger = Logger(subsystem: "com.paraSwift", category: "OAuth")
        
        do {
            // Step 1: Get OAuth verification
            logger.debug("Starting OAuth flow for provider: \(provider.rawValue)")
            let authState = try await verifyOAuth(provider: provider, webAuthenticationSession: webAuthenticationSession)
            
            // Step 2: Process the authentication state based on its stage
            return try await processOAuthAuthState(
                authState,
                authorizationController: authorizationController,
                logger: logger
            )
        } catch {
            logger.error("OAuth error: \(error.localizedDescription)")
            return (success: false, errorMessage: String(describing: error))
        }
    }
    
    // MARK: - Private OAuth Helper Methods
    
    /// Extracts the session lookup ID from an OAuth URL if present
    /// - Parameters:
    ///   - url: The OAuth URL to extract from
    ///   - logger: Logger for debug messages
    /// - Returns: The session lookup ID, if found
    private func extractSessionLookupId(from url: String, logger: Logger) -> String? {
        if let urlComponents = URLComponents(string: url),
           let queryItems = urlComponents.queryItems {
            let sessionLookupId = queryItems.first(where: { $0.name == "sessionLookupId" })?.value
            logger.debug("Extracted sessionLookupId: \(sessionLookupId ?? "nil")")
            return sessionLookupId
        }
        return nil
    }
    
    // Note: The sessionLookupId is currently not used in the OAuth flow, 
    // but may be needed for future OAuth implementations
    
    /// Processes the result from verifyOAuth and creates an AuthState object
    /// - Parameters:
    ///   - result: The result from the verifyOAuth call
    ///   - logger: Logger for debug messages
    /// - Returns: The parsed AuthState object
    private func processOAuthResult(_ result: Any?, logger: Logger) throws -> AuthState {
        guard let resultDict = result as? [String: Any] else {
            throw ParaError.bridgeError("Invalid result format from verifyOAuth: \(String(describing: result))")
        }
        
        // Extract required fields from the response
        guard let stageString = resultDict["stage"] as? String,
              let stage = AuthStage(rawValue: stageString),
              let userId = resultDict["userId"] as? String else {
            throw ParaError.bridgeError("Missing required fields in verifyOAuth response: \(resultDict)")
        }
        
        // Extract optional fields
        let passkeyUrl = resultDict["passkeyUrl"] as? String
        let passkeyId = resultDict["passkeyId"] as? String
        let passwordUrl = resultDict["passwordUrl"] as? String
        let passkeyKnownDeviceUrl = resultDict["passkeyKnownDeviceUrl"] as? String
        let displayName = resultDict["displayName"] as? String
        let pfpUrl = resultDict["pfpUrl"] as? String
        let username = resultDict["username"] as? String
        let signatureVerificationMessage = resultDict["signatureVerificationMessage"] as? String
        
        // Extract auth identity and external wallet if available
        var authIdentity: AuthIdentity? = nil
        var externalWalletInfo: ExternalWalletInfo? = nil
        
        if let auth = resultDict["auth"] as? [String: Any] {
            // Determine the type of auth identity
            if let email = auth["email"] as? String {
                authIdentity = EmailIdentity(email: email)
            } else if let phone = auth["phone"] as? String {
                authIdentity = PhoneIdentity(phone: phone)
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
        
        // Extract biometric hints if available
        let biometricHints = extractBiometricHints(from: resultDict)
        
        // Create AuthState object with the extracted fields
        let authState = AuthState(
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
        
        // Update session state based on authentication stage
        switch stage {
        case .login, .signup, .verify:
            // For all OAuth stages, we set the state to active
            self.sessionState = .active
        }
        
        return authState
    }
    
    /// Extracts biometric hints from a result dictionary
    /// - Parameter resultDict: The result dictionary
    /// - Returns: An array of BiometricHint objects, if available
    private func extractBiometricHints(from resultDict: [String: Any]) -> [AuthState.BiometricHint]? {
        if let hintsArray = resultDict["biometricHints"] as? [[String: Any]] {
            return hintsArray.compactMap { hint in
                // Check for both camelCase and lowercase versions of the field
                let aaguid = hint["aaguid"] as? String
                let userAgent = hint["userAgent"] as? String ?? hint["useragent"] as? String
                
                guard aaguid != nil || userAgent != nil else {
                    return nil
                }
                
                return AuthState.BiometricHint(aaguid: aaguid, userAgent: userAgent)
            }
        }
        return nil
    }
    
    /// Processes an OAuth AuthState and performs the appropriate login or signup actions
    /// - Parameters:
    ///   - authState: The auth state to process
    ///   - authorizationController: The controller for passkey operations
    ///   - logger: Logger for debug messages
    /// - Returns: A tuple with the success status and any error message
    private func processOAuthAuthState(
        _ authState: AuthState,
        authorizationController: AuthorizationController,
        logger: Logger
    ) async throws -> (success: Bool, errorMessage: String?) {
        switch authState.stage {
        case .login:
            logger.debug("Processing login stage for user ID: \(authState.userId)")
            
            // Log auth identity details
            if let emailIdentity = authState.authIdentity as? EmailIdentity {
                logger.debug("User email from OAuth: \(emailIdentity.email)")
            } else if let phoneIdentity = authState.authIdentity as? PhoneIdentity {
                logger.debug("User phone from OAuth: \(phoneIdentity.phone)")
            } else if authState.authIdentity != nil {
                logger.debug("User identity type from OAuth: \(authState.authIdentity!.type)")
            }
            
            // Use the appropriate auth info for passkey login
            var authInfo: AuthInfo? = nil
            if let emailIdentity = authState.authIdentity as? EmailIdentity {
                authInfo = EmailAuthInfo(email: emailIdentity.email)
            } else if let phoneIdentity = authState.authIdentity as? PhoneIdentity {
                authInfo = PhoneAuthInfo(phone: phoneIdentity.phone)
            } else if let walletIdentity = authState.authIdentity as? ExternalWalletIdentity {
                // For wallet-based login, we don't need passkeys
                let wallet = walletIdentity.wallet
                try await loginExternalWallet(wallet: wallet)
                return (success: true, errorMessage: nil)
            } else if let wallet = authState.externalWalletInfo {
                // Alternative way to get wallet info directly from authState
                try await loginExternalWallet(wallet: wallet)
                return (success: true, errorMessage: nil)
            }
            
            try await loginWithPasskey(authorizationController: authorizationController, authInfo: authInfo)
            logger.debug("Login successful")
            return (success: true, errorMessage: nil)
            
        case .signup:
            logger.debug("Processing signup stage for user ID: \(authState.userId)")
            
            // Handle signup with passkey if available
            if let passkeyId = authState.passkeyId {
                logger.debug("Generating passkey with ID: \(passkeyId)")
                // Use the appropriate identifier based on auth identity
                let identifier: String
                if let emailIdentity = authState.authIdentity as? EmailIdentity {
                    identifier = emailIdentity.email
                } else if let phoneIdentity = authState.authIdentity as? PhoneIdentity {
                    identifier = phoneIdentity.phone
                } else {
                    identifier = authState.userId
                }
                
                try await generatePasskey(
                    identifier: identifier,
                    biometricsId: passkeyId,
                    authorizationController: authorizationController
                )
                
                logger.debug("Creating wallet")
                try await createWallet(type: .evm, skipDistributable: false)
                return (success: true, errorMessage: nil)
            } else if let wallet = authState.externalWalletInfo {
                // For external wallet signup, use the wallet info directly
                try await loginExternalWallet(wallet: wallet)
                return (success: true, errorMessage: nil)
            } else {
                logger.error("No passkey ID or external wallet available for signup")
                return (success: false, errorMessage: "No authentication method available")
            }
            
        case .verify:
            // This shouldn't happen with OAuth
            logger.error("Unexpected verify stage in OAuth flow")
            return (success: false, errorMessage: "Unexpected authentication stage")
        }
    }
}
