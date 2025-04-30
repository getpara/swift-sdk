import Foundation // Use Foundation instead of SwiftUI if UI elements aren't needed

/// Specifies the intended authentication method.
public enum AuthMethod {
    case passkey
    case password
}

/// Status of the email authentication process.
public enum EmailAuthStatus {
    /// Authentication successful.
    case success
    /// User needs to verify their email.
    case needsVerification
    /// Error occurred during authentication.
    case error
}

/// Status of the phone authentication process.
public enum PhoneAuthStatus {
    /// Authentication successful.
    case success
    /// User needs to verify their phone number.
    case needsVerification
    /// Error occurred during authentication.
    case error
}

/// Errors that can occur during Para operations.
public enum ParaError: Error, CustomStringConvertible {
    /// An error occurred while executing JavaScript bridge code.
    case bridgeError(String)
    /// The JavaScript bridge did not respond in time.
    case bridgeTimeoutError
    /// A general error occurred.
    case error(String)

    public var description: String {
        switch self {
        case .bridgeError(let info):
            return "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            return "The javascript bridge did not respond in time and the continuation has been cancelled."
        case .error(let info):
            return "An error occurred: \(info)"
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
