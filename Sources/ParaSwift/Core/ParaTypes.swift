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
public enum ParaError: Error, CustomStringConvertible {
    /// An error occurred while executing JavaScript bridge code.
    case bridgeError(String)
    /// The JavaScript bridge did not respond in time.
    case bridgeTimeoutError
    /// A general error occurred.
    case error(String)
    /// Feature not implemented yet.
    case notImplemented(String)

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
