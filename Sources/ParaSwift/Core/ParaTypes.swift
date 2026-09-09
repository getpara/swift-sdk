import Foundation

/// Current package version.
public enum ParaPackage {
    /// Package version of the Swift SDK
    public static let version = "2.0.0"
}

/// Specifies the intended authentication method.
public enum AuthMethod {
    case passkey
    case password
}

/// Errors that can occur during Para operations.
public enum ParaError: Error, CustomStringConvertible, LocalizedError {
    /// An error occurred while executing JavaScript bridge code.
    case bridgeError(String)
    /// The JavaScript bridge did not respond in time.
    case bridgeTimeoutError
    /// A general error occurred.
    case error(String)
    /// Feature not implemented yet.
    case notImplemented(String)
    /// A signing operation was denied by a permissions policy and requires user approval.
    case transactionDenied(pendingTransactionId: String, transactionReviewUrl: String?)
    /// A native passkey login was refused because the passkey is the account's login SECOND factor (its key
    /// share moved to the Para enclave). Sign the user in with email, phone or a social login; the portal then
    /// asks for this passkey as the second step.
    case passkeyIsSecondFactor

    public var description: String {
        switch self {
        case let .bridgeError(info):
            "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            "The javascript bridge did not respond in time and the continuation has been cancelled."
        case let .error(info):
            "An error occurred: \(info)"
        case let .notImplemented(feature):
            "Feature not implemented: \(feature)"
        case let .transactionDenied(id, _):
            "Transaction requires approval (pending: \(id))"
        case .passkeyIsSecondFactor:
            "This passkey is the account's second factor and cannot sign in on its own. Sign in with email, phone or a social login first."
        }
    }

    // Provide concise strings for SwiftUI alerts and NSError bridging
    public var errorDescription: String? {
        switch self {
        case let .bridgeError(info):
            return info
        case .bridgeTimeoutError:
            return "Request timed out. Please try again."
        case let .error(info):
            return info
        case let .notImplemented(feature):
            return "Feature not implemented: \(feature)"
        case let .transactionDenied(id, _):
            return "Transaction requires approval (pending: \(id))"
        case .passkeyIsSecondFactor:
            return "Sign in with your email, phone or social account first, then verify with this passkey."
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
