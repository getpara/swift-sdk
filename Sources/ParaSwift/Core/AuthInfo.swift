//
//  AuthInfo.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/11/25.
//

public protocol AuthInfo: Codable {}

public struct EmailAuthInfo: AuthInfo {
    let email: String
    
    public init(email: String) {
        self.email = email
    }
}

public struct PhoneAuthInfo: AuthInfo {
    let phone: String
    let countryCode: String
    
    public init(phone: String, countryCode: String) {
        self.phone = phone
        self.countryCode = countryCode
    }
}

/// New authentication type for signUpOrLogIn method
public enum Auth: Encodable {
    case email(String)
    case phone(String)
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .email(let value):
            try container.encode(value, forKey: .email)
        case .phone(let value):
            try container.encode(value, forKey: .phone)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case email, phone
    }
}

/// Authentication state representing different stages of the auth flow
public enum AuthStage: String, Codable {
    case verify
    case signup
    case login
}

/// Authentication state returned by signUpOrLogIn
public struct AuthState: Codable {
    /// The stage of authentication
    public let stage: AuthStage
    /// The Para userId for the currently authenticating user
    public let userId: String
    /// URL for passkey authentication
    public let passkeyUrl: String?
    /// ID for the passkey
    public let passkeyId: String?
    /// URL for password authentication
    public let passwordUrl: String?
    /// Biometric hints for the user's devices
    public let biometricHints: [BiometricHint]?
    
    public struct BiometricHint: Codable {
        public let aaguid: String
        public let userAgent: String
    }
}
