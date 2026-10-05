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
        }
    }

    /// Provide concise strings for SwiftUI alerts and NSError bridging
    public var errorDescription: String? {
        switch self {
        case let .bridgeError(info):
            info
        case .bridgeTimeoutError:
            "Request timed out. Please try again."
        case let .error(info):
            info
        case let .notImplemented(feature):
            "Feature not implemented: \(feature)"
        case let .transactionDenied(id, _):
            "Transaction requires approval (pending: \(id))"
        }
    }
}

/// Response type for 2FA setup operation
/// Thrown by the stage-based sign-in methods (`initiateAuthFlow`, `handleVerificationCode`, `handleOAuth`,
/// `loginExternalWallet`) when the account must complete login two-factor authentication, which those flows can't host.
/// The SDK cancels the pending sign-in before throwing. Use `authenticateWithEmailOrPhone` or `authenticateWithOAuth`,
/// which complete the second factor on a Para-hosted page once Para's updated authentication flow is enabled for your
/// app. A separate type rather than a `ParaError` case, so existing exhaustive `switch`es over `ParaError` still compile.
public struct ParaTwoFactorRequiredError: Error, LocalizedError {
    public init() {}

    public var errorDescription: String? {
        "This account requires two-factor authentication to sign in, which this sign-in flow can't complete."
    }
}

public enum TwoFactorSetupResponse {
    /// 2FA is already set up
    case alreadySetup
    /// 2FA needs to be set up, contains the URI for configuration
    case needsSetup(uri: String)
}
