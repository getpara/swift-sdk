import Foundation

/// Protocol defining authentication information that can be encoded
public protocol AuthInfo: Codable {}

/// Authentication identity for email-based authentication
public struct EmailIdentity: Codable {
    /// The user's email address
    public let email: String
    
    /// Creates a new EmailIdentity instance
    /// - Parameter email: The user's email address
    public init(email: String) {
        self.email = email
    }
    
    private enum CodingKeys: String, CodingKey {
        case email
    }
}

/// Authentication identity for phone-based authentication
public struct PhoneIdentity: Codable {
    /// The user's phone number (with country code, e.g. "+19205551111")
    public let phone: String
    
    /// Creates a new PhoneIdentity instance
    /// - Parameter phone: The full phone number with country code (e.g. "+19205551111")
    public init(phone: String) {
        self.phone = phone
    }
    
    private enum CodingKeys: String, CodingKey {
        case phone
    }
}

/// Wallet type for external wallet authentication
public enum ExternalWalletType: String, Codable {
    /// Ethereum Virtual Machine wallet
    case evm = "EVM"
    /// Solana wallet
    case solana = "SOLANA"
    /// Cosmos wallet
    case cosmos = "COSMOS"
}

/// Information about an external wallet
public struct ExternalWalletInfo: Codable {
    /// The wallet address
    public let address: String
    /// The wallet type
    public let type: ExternalWalletType
    /// The wallet provider (e.g. "metamask")
    public let provider: String?
    
    /// Creates a new ExternalWalletInfo instance
    /// - Parameters:
    ///   - address: The wallet address
    ///   - type: The wallet type
    ///   - provider: Optional wallet provider
    public init(address: String, type: ExternalWalletType, provider: String? = nil) {
        self.address = address
        self.type = type
        self.provider = provider
    }
}

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
    /// The user's full phone number with country code (e.g., "+19205551111")
    let phone: String
    
    /// Creates a new PhoneAuthInfo instance
    /// - Parameter phone: The user's full phone number with country code
    public init(phone: String) {
        self.phone = phone
    }
}

/// Authentication type for signUpOrLogIn method
public enum Auth: Encodable {
    /// Email-based authentication
    case email(String)
    /// Phone-based authentication with full phone number including country code
    case phone(String)
    
    /// String representation for debugging
    public var debugDescription: String {
        switch self {
        case .email(let value):
            return "Email(\(value))"
        case .phone(let phoneNumber):
            return "Phone(\(phoneNumber))"
        }
    }
    
    /// Encodes the authentication type
    /// - Parameter encoder: The encoder to use
    /// - Throws: An error if encoding fails
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .email(let value):
            try container.encode(value, forKey: .email)
        case .phone(let phoneNumber):
            try container.encode(phoneNumber, forKey: .phone)
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
    /// Email identity information if using email auth
    public let emailIdentity: EmailIdentity?
    /// Phone identity information if using phone auth
    public let phoneIdentity: PhoneIdentity?
    /// Display name for the authenticating user
    public let displayName: String?
    /// Profile picture URL for the authenticating user
    public let pfpUrl: String?
    /// Username for the authenticating user
    public let username: String?
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
    
    /// Creates a new AuthState instance
    /// - Parameters:
    ///   - stage: The authentication stage
    ///   - userId: The Para userId
    ///   - emailIdentity: Optional email identity
    ///   - phoneIdentity: Optional phone identity
    ///   - displayName: Optional display name
    ///   - pfpUrl: Optional profile picture URL
    ///   - username: Optional username
    ///   - passkeyUrl: Optional passkey URL
    ///   - passkeyId: Optional passkey ID
    ///   - passkeyKnownDeviceUrl: Optional passkey known device URL
    ///   - passwordUrl: Optional password URL
    ///   - biometricHints: Optional biometric hints
    public init(
        stage: AuthStage,
        userId: String,
        emailIdentity: EmailIdentity? = nil,
        phoneIdentity: PhoneIdentity? = nil,
        displayName: String? = nil,
        pfpUrl: String? = nil,
        username: String? = nil,
        passkeyUrl: String? = nil,
        passkeyId: String? = nil,
        passkeyKnownDeviceUrl: String? = nil,
        passwordUrl: String? = nil,
        biometricHints: [BiometricHint]? = nil
    ) {
        self.stage = stage
        self.userId = userId
        self.emailIdentity = emailIdentity
        self.phoneIdentity = phoneIdentity
        self.displayName = displayName
        self.pfpUrl = pfpUrl
        self.username = username
        self.passkeyUrl = passkeyUrl
        self.passkeyId = passkeyId
        self.passkeyKnownDeviceUrl = passkeyKnownDeviceUrl
        self.passwordUrl = passwordUrl
        self.biometricHints = biometricHints
    }
    
    /// For backward compatibility with code expecting email field
    public var email: String? {
        return emailIdentity?.email
    }
    
    // MARK: - Codable implementation
    
    /// Coding keys for encoding/decoding
    private enum CodingKeys: String, CodingKey {
        case stage, userId, displayName, pfpUrl, username
        case emailIdentity, phoneIdentity
        case passkeyUrl, passkeyId, passkeyKnownDeviceUrl, passwordUrl, biometricHints
    }
    
    /// Initialize from decoder
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        stage = try container.decode(AuthStage.self, forKey: .stage)
        userId = try container.decode(String.self, forKey: .userId)
        
        // Decode optional fields
        emailIdentity = try container.decodeIfPresent(EmailIdentity.self, forKey: .emailIdentity)
        phoneIdentity = try container.decodeIfPresent(PhoneIdentity.self, forKey: .phoneIdentity)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        pfpUrl = try container.decodeIfPresent(String.self, forKey: .pfpUrl)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        passkeyUrl = try container.decodeIfPresent(String.self, forKey: .passkeyUrl)
        passkeyId = try container.decodeIfPresent(String.self, forKey: .passkeyId)
        passkeyKnownDeviceUrl = try container.decodeIfPresent(String.self, forKey: .passkeyKnownDeviceUrl)
        passwordUrl = try container.decodeIfPresent(String.self, forKey: .passwordUrl)
        biometricHints = try container.decodeIfPresent([BiometricHint].self, forKey: .biometricHints)
    }
}
