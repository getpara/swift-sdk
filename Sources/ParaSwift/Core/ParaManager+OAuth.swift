//
//  ParaManager+OAuth.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

import SwiftUI
import AuthenticationServices
import os

public enum OAuthProvider: String {
    case google = "GOOGLE"
    case discord = "DISCORD"
    case apple = "APPLE"
}

/// Struct for OAuth URL parameters that conforms to Encodable
private struct OAuthUrlParams: Encodable {
    let method: String
    let deeplinkUrl: String
}

/// Struct for verifyOAuth parameters that conforms to Encodable
private struct VerifyOAuthParams: Encodable {
    let method: String
    let deeplinkUrl: String
}

@available(iOS 16.4,*)
extension ParaManager {
    /// Verifies an OAuth authentication and returns an AuthState object according to the V2 authentication flow
    /// - Parameters:
    ///   - provider: The OAuth provider to verify
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    /// - Returns: An AuthState object containing information about the next steps in the authentication flow
    public func verifyOAuth(provider: OAuthProvider, webAuthenticationSession: WebAuthenticationSession) async throws -> AuthState {
        let logger = Logger(subsystem: "com.paraSwift", category: "OAuth")
        try await ensureWebViewReady()
        
        // Step 1: Get the OAuth URL
        logger.debug("Getting OAuth URL for provider: \(provider.rawValue)")
        let oAuthParams = OAuthUrlParams(method: provider.rawValue, deeplinkUrl: deepLink)
        
        // Step 2: Call getOAuthUrl method
        let oAuthUrlResult = try await postMessage(method: "getOAuthUrl", arguments: [oAuthParams])
        guard let oAuthURL = oAuthUrlResult as? String, let url = URL(string: oAuthURL) else {
            throw ParaError.error("Invalid OAuth URL")
        }
        logger.debug("Received OAuth URL: \(oAuthURL)")
        
        // Extract sessionLookupId from the OAuth URL if present
        var sessionLookupId: String? = nil
        if let urlComponents = URLComponents(string: oAuthURL),
           let queryItems = urlComponents.queryItems {
            sessionLookupId = queryItems.first(where: { $0.name == "sessionLookupId" })?.value
            logger.debug("Extracted sessionLookupId: \(sessionLookupId ?? "nil")")
        }
        
        // Step 3: Open the OAuth URL in a WebAuthenticationSession and wait for the callback
        let callbackURL = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: deepLink)
        let callbackUrlString = callbackURL.absoluteString
        logger.debug("Received callback URL: \(callbackUrlString)")
        
        // Step 4: Create verifyOAuth parameters
        let verifyParams = VerifyOAuthParams(
            method: provider.rawValue,
            deeplinkUrl: callbackUrlString
        )
        
        // Step 5: Call verifyOAuth with the callback URL and session lookup ID
        logger.debug("Calling verifyOAuth with provider: \(provider.rawValue)")
        let result = try await postMessage(method: "verifyOAuth", arguments: [verifyParams])
        
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
        
        // Extract email if available
        var email: String? = nil
        if let auth = resultDict["auth"] as? [String: Any] {
            email = auth["email"] as? String
        }
        
        // Extract biometric hints if available
        var biometricHints: [AuthState.BiometricHint]?
        if let hintsArray = resultDict["biometricHints"] as? [[String: Any]] {
            biometricHints = hintsArray.compactMap { hint in
                // Check for both camelCase and lowercase versions of the field
                let aaguid = hint["aaguid"] as? String
                let userAgent = hint["userAgent"] as? String ?? hint["useragent"] as? String
                
                guard aaguid != nil || userAgent != nil else {
                    return nil
                }
                
                return AuthState.BiometricHint(aaguid: aaguid, userAgent: userAgent)
            }
        }
        
        // Create AuthState object with additional fields
        let authState = AuthState(
            stage: stage,
            userId: userId,
            email: email,
            passkeyUrl: passkeyUrl,
            passkeyId: passkeyId,
            passkeyKnownDeviceUrl: passkeyKnownDeviceUrl,
            passwordUrl: passwordUrl,
            biometricHints: biometricHints
        )
        
        // Update session state based on authentication stage
        switch stage {
        case .login, .signup:
            self.sessionState = .active
        case .verify:
            // This shouldn't happen for OAuth, but keeping it for completeness
            self.sessionState = .active
        }
        
        logger.debug("OAuth verification completed with stage: \(stage.rawValue)")
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
            
            // Step 2: Handle the auth state based on its stage
            switch authState.stage {
            case .login:
                logger.debug("Processing login stage for user ID: \(authState.userId)")
                if let email = authState.email {
                    logger.debug("User email from OAuth: \(email)")
                }
                
                // Use the email from OAuth response for authentication
                let emailAuthInfo = authState.email.map { EmailAuthInfo(email: $0) }
                try await login(authorizationController: authorizationController, authInfo: emailAuthInfo)
                logger.debug("Login successful")
                return (success: true, errorMessage: nil)
                
            case .signup:
                logger.debug("Processing signup stage for user ID: \(authState.userId)")
                
                // Handle signup with passkey if available
                if let passkeyId = authState.passkeyId {
                    logger.debug("Generating passkey with ID: \(passkeyId)")
                    try await generatePasskey(
                        identifier: authState.userId,
                        biometricsId: passkeyId,
                        authorizationController: authorizationController
                    )
                    
                    logger.debug("Creating wallet")
                    try await createWallet(type: .evm, skipDistributable: false)
                    return (success: true, errorMessage: nil)
                } else {
                    logger.error("No passkey ID available for signup")
                    return (success: false, errorMessage: "No passkey ID available")
                }
                
            case .verify:
                // This shouldn't happen with OAuth
                logger.error("Unexpected verify stage in OAuth flow")
                return (success: false, errorMessage: "Unexpected authentication stage")
            }
        } catch {
            logger.error("OAuth error: \(error.localizedDescription)")
            return (success: false, errorMessage: String(describing: error))
        }
    }
    
    /// Deprecated: Use verifyOAuth instead to align with V2 authentication flow
    /// Connects to an OAuth provider and returns the email associated with the account
    /// - Parameters:
    ///   - provider: The OAuth provider to connect to
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    /// - Returns: The email associated with the OAuth account
    @available(*, deprecated, message: "Use verifyOAuth instead to align with V2 authentication flow")
    public func oAuthConnect(provider: OAuthProvider, webAuthenticationSession: WebAuthenticationSession) async throws -> String {
        let oAuthParams = OAuthUrlParams(method: provider.rawValue, deeplinkUrl: deepLink)
        let result = try await postMessage(method: "getOAuthUrl", arguments: [oAuthParams])
        let oAuthURL = try decodeResult(result, expectedType: String.self, method: "getOAuthUrl")
        
        guard let url = URL(string: oAuthURL) else {
            throw ParaError.error("Invalid url")
        }
        
        let urlWithToken = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: deepLink)
        guard let email = urlWithToken.valueOf("email") else {
            throw ParaError.error("No email found in returned url")
        }
        
        return email
    }
}