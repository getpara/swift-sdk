//
//  ParaManager+OAuth.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

import AuthenticationServices
import os
import SwiftUI

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
    /// The app scheme for redirecting back to the app
    let appScheme: String
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
    /// Handles the complete OAuth authentication flow, including processing the authentication state
    /// and performing the appropriate login or signup actions based on the result.
    /// - Parameters:
    ///   - provider: The OAuth provider to authenticate with
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    ///   - authorizationController: The AuthorizationController to use for passkey operations
    /// - Throws: ParaError or other authentication-related errors
    public func handleOAuth(
        provider: OAuthProvider,
        webAuthenticationSession overrideSession: WebAuthenticationSession? = nil,
        authorizationController: AuthorizationController
    ) async throws {
        let logger = Logger(subsystem: "com.paraSwift", category: "OAuth")

        let session: WebAuthenticationSession
        if let overrideSession {
            session = overrideSession
        } else if let defaultSession = defaultWebAuthenticationSession {
            session = defaultSession
        } else {
            logger.error("No WebAuthenticationSession provided for OAuth flow.")
            throw ParaError.error("Missing WebAuthenticationSession. Call setDefaultWebAuthenticationSession(_:) or pass one in.")
        }

        // Step 1: Get OAuth verification
        logger.debug("Starting OAuth flow for provider: \(provider.rawValue)")
        let authState = try await verifyOAuth(provider: provider, webAuthenticationSession: session)

        // Step 2: Process the authentication state based on its stage
        try await processOAuthAuthState(
            authState,
            authorizationController: authorizationController,
            logger: logger,
        )
    }

    // MARK: - Private OAuth Helper Methods

    /// Verifies an OAuth authentication and returns an AuthState object according to the V2 authentication flow
    /// - Parameters:
    ///   - provider: The OAuth provider to verify
    ///   - webAuthenticationSession: The WebAuthenticationSession to use for the OAuth flow
    /// - Returns: An AuthState object containing information about the next steps in the authentication flow
    private func verifyOAuth(provider: OAuthProvider, webAuthenticationSession: WebAuthenticationSession) async throws -> AuthState {
        let logger = Logger(subsystem: "com.paraSwift", category: "OAuth")
        try await ensureWebViewReady()

        // Step 1: Prepare and get the OAuth URL
        logger.debug("Getting OAuth URL for provider: \(provider.rawValue) and appScheme: \(self.appScheme)")
        let oAuthParams = OAuthUrlParams(method: provider.rawValue, appScheme: appScheme)

        let oAuthUrlResult = try await paraWebView.postMessage(method: "getOAuthUrl", payload: oAuthParams)
        guard let oAuthURL = oAuthUrlResult as? String, let url = URL(string: oAuthURL) else {
            throw ParaError.error("Invalid OAuth URL")
        }
        logger.debug("Received OAuth URL: \(oAuthURL)")

        // Step 3: Perform the authentication flow
        let callbackURL = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: appScheme)
        let callbackUrlString = callbackURL.absoluteString
        logger.debug("Received callback URL: \(callbackUrlString)")

        // Step 4: Verify the OAuth response
        let verifyParams = VerifyOAuthParams(
            method: provider.rawValue,
            deeplinkUrl: callbackUrlString,
        )

        logger.debug("Calling verifyOAuth with provider: \(provider.rawValue)")
        let result = try await paraWebView.postMessage(method: "verifyOAuth", payload: verifyParams)

        // Step 5: Process the verification result
        let authState = try processOAuthResult(result, logger: logger)
        logger.debug("OAuth verification completed with stage: \(authState.stage.rawValue)")

        return authState
    }

    // Note: The sessionLookupId is currently not used in the OAuth flow,
    // but may be needed for future OAuth implementations

    /// Processes the result from verifyOAuth and creates an AuthState object
    /// - Parameters:
    ///   - result: The result from the verifyOAuth call
    ///   - logger: Logger for debug messages
    /// - Returns: The parsed AuthState object
    private func processOAuthResult(_ result: Any?, logger _: Logger) throws -> AuthState {
        guard let resultDict = result as? [String: Any] else {
            throw ParaError.bridgeError("Invalid result format from verifyOAuth: \(String(describing: result))")
        }

        // Extract required fields from the response
        guard let stageString = resultDict["stage"] as? String,
              let stage = AuthStage(rawValue: stageString),
              let userId = resultDict["userId"] as? String
        else {
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
        let loginUrl = resultDict["loginUrl"] as? String
        let nextStage = (resultDict["nextStage"] as? String).flatMap(AuthStage.init(rawValue:))
        let loginAuthMethods = resultDict["loginAuthMethods"] as? [String]
        let signupAuthMethods = resultDict["signupAuthMethods"] as? [String]

        // Extract email and phone directly from the response
        var email: String? = nil
        var phone: String? = nil

        if let auth = resultDict["auth"] as? [String: Any] {
            // Get email/phone directly
            email = auth["email"] as? String
            phone = auth["phone"] as? String
        }

        // Extract biometric hints if available
        let biometricHints = extractBiometricHints(from: resultDict)

        // Create AuthState object with the extracted fields
        let authState = AuthState(
            stage: stage,
            userId: userId,
            email: email,
            phone: phone,
            displayName: displayName,
            pfpUrl: pfpUrl,
            username: username,
            passkeyUrl: passkeyUrl,
            passkeyId: passkeyId,
            passkeyKnownDeviceUrl: passkeyKnownDeviceUrl,
            passwordUrl: passwordUrl,
            biometricHints: biometricHints,
            loginUrl: loginUrl,
            nextStage: nextStage,
            loginAuthMethods: loginAuthMethods,
            signupAuthMethods: signupAuthMethods
        )

        // Update session state based on authentication stage
        switch stage {
        case .login, .signup, .verify:
            // For all OAuth stages, we set the state to active
            sessionState = .active
        case .done:
            sessionState = .activeLoggedIn
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
    /// - Throws: ParaError or other authentication-related errors
    private func processOAuthAuthState(
        _ authState: AuthState,
        authorizationController: AuthorizationController,
        logger: Logger,
    ) async throws {
        switch authState.stage {
        case .login:
            logger.debug("Processing login stage for user ID: \(authState.userId)")

            // Log auth identity details
            if let email = authState.email {
                logger.debug("User email from OAuth: \(email)")
            } else if let phone = authState.phone {
                logger.debug("User phone from OAuth: \(phone)")
            }

            // Pass email and phone directly to loginWithPasskey
            try await loginWithPasskey(
                authorizationController: authorizationController,
                email: authState.email,
                phone: authState.phone,
            )

            logger.debug("Login successful")

        case .signup:
            logger.debug("Processing signup stage for user ID: \(authState.userId)")

            // Handle signup with passkey if available
            guard let passkeyId = authState.passkeyId else {
                logger.error("No passkey ID available for signup")
                throw ParaError.error("No authentication method available")
            }

            logger.debug("Generating passkey with ID: \(passkeyId)")
            // Use the appropriate identifier based on identity
            let identifier: String = if let email = authState.email {
                email
            } else if let phone = authState.phone {
                phone
            } else {
                authState.userId
            }

            try await generatePasskey(
                identifier: identifier,
                biometricsId: passkeyId,
                authorizationController: authorizationController,
            )

            logger.debug("Passkey generation completed successfully")

            // Update session state after successful signup
            wallets = try await fetchWallets()
            sessionState = .activeLoggedIn
            await persistCurrentSession(reason: "oauth-signup")

            // Synchronize required wallets for new OAuth users
            logger.info("Synchronizing required wallets for new OAuth user...")
            do {
                let newWallets = try await synchronizeRequiredWallets()
                if !newWallets.isEmpty {
                    logger.info("Created \(newWallets.count) required wallets for new OAuth user")
                }
            } catch {
                // Don't fail the signup if wallet creation fails
                logger.error("Failed to synchronize required wallets: \(error.localizedDescription)")
            }

        case .verify:
            logger.debug("OAuth verify stage received; waiting for completion via portal")

        case .done:
            logger.debug("OAuth flow completed with DONE stage for user ID: \(authState.userId)")
            sessionState = .activeLoggedIn
            await persistCurrentSession(reason: "oauth-done")
        }
    }
}
