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

/// Thrown when the account must complete login two-factor authentication before the sign-in can finish.
///
/// Thrown by `initiateAuthFlow`, `handleVerificationCode`, `handleOAuth`, `loginExternalWallet`,
/// `authenticateWithEmailOrPhone`, `authenticateWithOAuth`, and `authenticateWithExternalWallet`. On Para's updated
/// sign-in flow the second factor is completed on Para's hosted page, so this is only thrown when the sign-in runs
/// the earlier flow, which can't host it. Updating to the latest Para SDK lets these accounts sign in. The SDK cancels
/// the pending sign-in before throwing.
///
/// A separate type rather than a `ParaError` case, so existing exhaustive `switch`es over `ParaError` still compile.
public struct ParaTwoFactorRequiredError: Error, CustomStringConvertible, LocalizedError {
    /// Whether the account needs to verify an enrolled second factor or set one up first.
    public enum Mode: String {
        /// The account has a second factor enrolled and must verify it.
        case verify
        /// The account must set up a second factor before it can sign in.
        case enroll
    }

    /// What the account needs to do, or nil when Para didn't say.
    public let mode: Mode?
    /// The second-factor methods Para offered for this sign-in (for example `"totp"`). Empty when none were reported.
    public let methods: [String]

    public init(mode: Mode? = nil, methods: [String] = []) {
        self.mode = mode
        self.methods = methods
    }

    /// Reads the `mfa` details of a sign-in parked on two-factor, tolerating missing or unrecognized values.
    init(mfa: Any?) {
        let details = mfa as? [String: Any]
        self.init(
            mode: (details?["mode"] as? String).flatMap(Mode.init(rawValue:)),
            methods: (details?["methods"] as? [Any])?.compactMap { $0 as? String } ?? []
        )
    }

    public var description: String {
        errorDescription ?? ""
    }

    public var errorDescription: String? {
        switch mode {
        case .enroll:
            "This account needs two-factor authentication set up to sign in, which this sign-in flow can't complete."
        case .verify, nil:
            "This account requires two-factor authentication to sign in, which this sign-in flow can't complete."
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
