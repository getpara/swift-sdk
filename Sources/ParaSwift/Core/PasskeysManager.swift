/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
AccountStore manages account sign in and out.
*/

#if os(iOS)

import AuthenticationServices
import SwiftUI
import Combine
import os



@available(iOS 16.4,*)
public enum AuthorizationHandlingError: Error {
    case unknownAuthorizationResult(ASAuthorizationResult)
    case otherError
}

@available(iOS 16.4,*)
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

@available(iOS 16.4,*)
final class PasskeysManager: NSObject, ASAuthorizationControllerDelegate {
    
    public var relyingPartyIdentifier: String
    
    public weak var presentationContextProvider: ASAuthorizationControllerPresentationContextProviding?
    
    public init(relyingPartyIdentifier: String) {
        self.relyingPartyIdentifier = relyingPartyIdentifier
    }
    
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
    
    private func passkeyChallenge() async -> Data {
        Data("passkey challenge".utf8)
    }

    private func passkeyAssertionRequest(challenge: String, allowedPublicKeys: [String]) async -> ASAuthorizationRequest {
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
            .createCredentialAssertionRequest(challenge: Data(base64URLEncoded: challenge)!)
        
        for allowedPublicKey in allowedPublicKeys {
            let apkData = Data(base64URLEncoded: allowedPublicKey)!
            request.allowedCredentials.append(ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: apkData))
        }
        
        return request
    }

    private func passkeyRegistrationRequest(username: String, userHandle: Data) async -> ASAuthorizationRequest {
        await ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
           .createCredentialRegistrationRequest(challenge: passkeyChallenge(), name: username, userID: userHandle)
    }

    private func signInRequests(challenge: String, allowedPublicKeys: [String]) async -> [ASAuthorizationRequest] {
        await [passkeyAssertionRequest(challenge: challenge, allowedPublicKeys: allowedPublicKeys), ASAuthorizationPasswordProvider().createRequest()]
    }
    
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

#endif // os(iOS) || os(macOS)
