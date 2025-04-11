//
//  AuthInfo.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

/// Protocol defining authentication information that can be encoded
public protocol AuthInfo: Codable {}

/// Authentication information for email-based authentication
public struct EmailAuthInfo: AuthInfo {
    /// The user's email address
    let email: String
    
    /// Creates a new EmailAuthInfo instance
    /// - Parameter email: The user's email address
    public init(email: String) {
        self.email = email
    }
}

/// Authentication information for phone-based authentication
public struct PhoneAuthInfo: AuthInfo {
    /// The user's phone number
    let phone: String
    /// The country code for the phone number
    let countryCode: String
    
    /// Creates a new PhoneAuthInfo instance
    /// - Parameters:
    ///   - phone: The user's phone number
    ///   - countryCode: The country code for the phone number
    public init(phone: String, countryCode: String) {
        self.phone = phone
        self.countryCode = countryCode
    }
}

/// Authentication type for signUpOrLogIn method
public enum Auth: Encodable {
    /// Email-based authentication
    case email(String)
    /// Phone-based authentication
    case phone(String)
    
    /// Encodes the authentication type
    /// - Parameter encoder: The encoder to use
    /// - Throws: An error if encoding fails
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .email(let value):
            try container.encode(value, forKey: .email)
        case .phone(let value):
            try container.encode(value, forKey: .phone)
        }
    }
    
    /// Coding keys for the Auth enum
    private enum CodingKeys: String, CodingKey {
        case email, phone
    }
}

/// Authentication state representing different stages of the auth flow
public enum AuthStage: String, Codable {
    /// Verification stage
    case verify
    /// Signup stage
    case signup
    /// Login stage
    case login
}

/// Authentication state returned by signUpOrLogIn
public struct AuthState: Codable {
    /// The stage of authentication
    public let stage: AuthStage
    /// The Para userId for the currently authenticating user
    public let userId: String
    /// The user's email, if available
    public let email: String?
    /// URL for passkey authentication
    public let passkeyUrl: String?
    /// ID for the passkey
    public let passkeyId: String?
    /// URL for passkey authentication on a known device
    public let passkeyKnownDeviceUrl: String?
    /// URL for password authentication
    public let passwordUrl: String?
    /// Biometric hints for the user's devices
    public let biometricHints: [BiometricHint]?
    
    /// Information about a biometric authentication device
    public struct BiometricHint: Codable {
        /// The AAGUID (Authenticator Attestation GUID) of the device
        public let aaguid: String?
        /// The user agent string of the device
        public let userAgent: String?
    }
}
