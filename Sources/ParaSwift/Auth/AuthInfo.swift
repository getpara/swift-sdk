import Foundation

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
    /// Email address if using email auth
    public let email: String?
    /// Phone number if using phone auth
    public let phone: String?
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
    ///   - email: Optional email address
    ///   - phone: Optional phone number
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
        email: String? = nil,
        phone: String? = nil,
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
        self.email = email
        self.phone = phone
        self.displayName = displayName
        self.pfpUrl = pfpUrl
        self.username = username
        self.passkeyUrl = passkeyUrl
        self.passkeyId = passkeyId
        self.passkeyKnownDeviceUrl = passkeyKnownDeviceUrl
        self.passwordUrl = passwordUrl
        self.biometricHints = biometricHints
    }
    
    // MARK: - Codable implementation
    
    /// Coding keys for encoding/decoding
    private enum CodingKeys: String, CodingKey {
        case stage, userId, displayName, pfpUrl, username
        case email, phone
        case passkeyUrl, passkeyId, passkeyKnownDeviceUrl, passwordUrl, biometricHints
    }
    
    /// Initialize from decoder
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        stage = try container.decode(AuthStage.self, forKey: .stage)
        userId = try container.decode(String.self, forKey: .userId)
        
        // Decode optional fields
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
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