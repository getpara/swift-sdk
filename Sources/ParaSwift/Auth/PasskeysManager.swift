/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
PasskeysManager handles passkey-based authentication using Apple's AuthenticationServices framework.
*/

import AuthenticationServices
import SwiftUI
import Combine
import os

/// Errors that can occur during authorization handling
public enum AuthorizationHandlingError: Error {
    /// An unknown authorization result was received
    case unknownAuthorizationResult(ASAuthorizationResult)
    /// An unspecified error occurred
    case otherError
}

extension AuthorizationHandlingError: LocalizedError {
    public var errorDescription: String? {
            switch self {
            case .unknownAuthorizationResult:
                return NSLocalizedString("Received an unknown authorization result.",
                                         comment: "Human readable description of receiving an unknown authorization result.")
            case .otherError:
                return NSLocalizedString("Encountered an error handling the authorization result.",
                                         comment: "Human readable description of an unknown error while handling the authorization result.")
            }
        }
}

/// Manages passkey-based authentication using Apple's AuthenticationServices framework
final class PasskeysManager: NSObject, ASAuthorizationControllerDelegate {
    
    /// The relying party identifier for passkey authentication
    public var relyingPartyIdentifier: String
    
    /// The presentation context provider for authorization requests
    public weak var presentationContextProvider: ASAuthorizationControllerPresentationContextProviding?
    
    /// Creates a new PasskeysManager instance
    /// - Parameter relyingPartyIdentifier: The relying party identifier for passkey authentication
    public init(relyingPartyIdentifier: String) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
    }
    
    /// Signs into a passkey account
    /// - Parameters:
    ///   - authorizationController: The authorization controller to use
    ///   - challenge: The challenge string for authentication
    ///   - allowedPublicKeys: Array of allowed public keys
    ///   - options: Optional authorization request options
    /// - Returns: A passkey assertion for authentication
    public func signIntoPasskeyAccount(authorizationController: AuthorizationController,
                                       challenge: String,
                                       allowedPublicKeys: [String],
                                       options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let authorizationResult = try await authorizationController.performRequests(
            signInRequests(challenge: challenge, allowedPublicKeys: allowedPublicKeys),
                options: options
        )
        
        switch authorizationResult {
        case let .passkeyAssertion(passkeyAssertion):
            return passkeyAssertion
        default:
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    }
    
    /// Creates a new passkey account
    /// - Parameters:
    ///   - authorizationController: The authorization controller to use
    ///   - username: The username for the new account
    ///   - userHandle: The user handle data
    ///   - options: Optional authorization request options
    /// - Returns: A passkey registration for the new account
    public func createPasskeyAccount(authorizationController: AuthorizationController, username: String, userHandle: Data,
                                     options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let authorizationResult = try await authorizationController.performRequests(
                [passkeyRegistrationRequest(username: username, userHandle: userHandle)],
                options: options
        )
        
        switch authorizationResult {
        case let .passkeyRegistration(passkeyRegistration):
            return passkeyRegistration
        default:
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    }
    
    /// Generates a passkey challenge
    /// - Returns: The challenge data
    private func passkeyChallenge() async -> Data {
        Data("passkey challenge".utf8)
    }

    /// Creates a passkey assertion request
    /// - Parameters:
    ///   - challenge: The challenge string
    ///   - allowedPublicKeys: Array of allowed public keys
    /// - Returns: An authorization request for passkey assertion
    private func passkeyAssertionRequest(challenge: String, allowedPublicKeys: [String]) async -> ASAuthorizationRequest {
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
            .createCredentialAssertionRequest(challenge: Data(base64URLEncoded: challenge)!)
        
        for allowedPublicKey in allowedPublicKeys {
            let apkData = Data(base64URLEncoded: allowedPublicKey)!
            request.allowedCredentials.append(ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: apkData))
        }
        
        return request
    }

    /// Creates a passkey registration request
    /// - Parameters:
    ///   - username: The username for registration
    ///   - userHandle: The user handle data
    /// - Returns: An authorization request for passkey registration
    private func passkeyRegistrationRequest(username: String, userHandle: Data) async -> ASAuthorizationRequest {
        await ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
           .createCredentialRegistrationRequest(challenge: passkeyChallenge(), name: username, userID: userHandle)
    }

    /// Creates sign-in requests for passkey authentication
    /// - Parameters:
    ///   - challenge: The challenge string
    ///   - allowedPublicKeys: Array of allowed public keys
    /// - Returns: Array of authorization requests
    private func signInRequests(challenge: String, allowedPublicKeys: [String]) async -> [ASAuthorizationRequest] {
        await [passkeyAssertionRequest(challenge: challenge, allowedPublicKeys: allowedPublicKeys), ASAuthorizationPasswordProvider().createRequest()]
    }
    
    /// Handles the authorization result
    /// - Parameters:
    ///   - authorizationResult: The result of the authorization request
    ///   - username: Optional username for logging
    private func handleAuthorizationResult(_ authorizationResult: ASAuthorizationResult, username: String? = nil) async throws {
        switch authorizationResult {
        case let .passkeyAssertion(passkeyAssertion):
            // The login was successful.
            Logger.authorization.log("Passkey authorization succeeded: \(passkeyAssertion)")
            guard let _ = String(bytes: passkeyAssertion.userID, encoding: .utf8) else {
                fatalError("Invalid credential: \(passkeyAssertion)")
            }
        case let .passkeyRegistration(passkeyRegistration):
            // The registration was successful.
            Logger.authorization.log("Passkey registration succeeded: \(passkeyRegistration)")
        default:
            Logger.authorization.error("Received an unknown authorization result.")
            // Throw an error and return to the caller.
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    }
}
