import Foundation

/// Protocol defining authentication information that can be encoded
public protocol AuthInfo: Codable {}

/// Protocol for authentication identity information
public protocol AuthIdentity: Codable {
    /// The identity type name
    /// Used for both encoding the type field and verifying during decoding
    static var identityType: String { get }
    
    /// The identifier for the identity
    var identifier: String { get }
}

/// Default implementation for AuthIdentity
extension AuthIdentity {
    /// Get the identity type name (instance accessor for the static property)
    public var type: String { return Self.identityType }
}

/// Authentication identity for email-based authentication
public struct EmailIdentity: AuthIdentity {
    /// The user's email address
    public let email: String
    
    /// The identity type name
    public static var identityType: String { return "email" }
    
    /// The identifier for the identity (email address)
    public var identifier: String { return email }
    
    /// Creates a new EmailIdentity instance
    /// - Parameter email: The user's email address
    public init(email: String) {
        self.email = email
    }
    
    /// Encodes the identity to a container
    /// - Parameter encoder: The encoder to use
    /// - Throws: An error if encoding fails
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(email, forKey: .email)
        try container.encode(type, forKey: .type)
    }
    
    /// Initializes from a decoder
    /// - Parameter decoder: The decoder
    /// - Throws: An error if decoding fails
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
        guard decodedType == nil || decodedType == Self.identityType else {
            throw DecodingError.dataCorruptedError(forKey: .type, 
                                                   in: container, 
                                                   debugDescription: "Type mismatch: expected \(Self.identityType), got \(decodedType ?? "nil")")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case email, type
    }
}

/// Authentication identity for phone-based authentication
public struct PhoneIdentity: AuthIdentity {
    /// The user's phone number (with country code, e.g. "+19205551111")
    public let phone: String
    
    /// The identity type name
    public static var identityType: String { return "phone" }
    
    /// The identifier for the identity (the full phone number)
    public var identifier: String {
        return phone
    }
    
    /// Creates a new PhoneIdentity instance
    /// - Parameter phone: The full phone number with country code (e.g. "+19205551111")
    public init(phone: String) {
        self.phone = phone
    }
    
    /// Encodes the identity to a container
    /// - Parameter encoder: The encoder to use
    /// - Throws: An error if encoding fails
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phone, forKey: .phone)
        try container.encode(type, forKey: .type)
    }
    
    /// Initializes from a decoder
    /// - Parameter decoder: The decoder
    /// - Throws: An error if decoding fails
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phone = try container.decode(String.self, forKey: .phone)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
        guard decodedType == nil || decodedType == Self.identityType else {
            throw DecodingError.dataCorruptedError(forKey: .type, 
                                                   in: container, 
                                                   debugDescription: "Type mismatch: expected \(Self.identityType), got \(decodedType ?? "nil")")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case phone, type
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

/// Authentication identity for external wallet-based authentication
public struct ExternalWalletIdentity: AuthIdentity {
    /// Information about the external wallet
    public let wallet: ExternalWalletInfo
    
    /// The identity type name
    public static var identityType: String { return "externalWallet" }
    
    /// The identifier for the identity (wallet address)
    public var identifier: String { return wallet.address }
    
    /// Creates a new ExternalWalletIdentity instance
    /// - Parameter wallet: Information about the external wallet
    public init(wallet: ExternalWalletInfo) {
        self.wallet = wallet
    }
    
    /// Encodes the identity to a container
    /// - Parameter encoder: The encoder to use
    /// - Throws: An error if encoding fails
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wallet, forKey: .wallet)
        try container.encode(type, forKey: .type)
    }
    
    /// Initializes from a decoder
    /// - Parameter decoder: The decoder
    /// - Throws: An error if decoding fails
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wallet = try container.decode(ExternalWalletInfo.self, forKey: .wallet)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
        guard decodedType == nil || decodedType == Self.identityType else {
            throw DecodingError.dataCorruptedError(forKey: .type, 
                                                   in: container, 
                                                   debugDescription: "Type mismatch: expected \(Self.identityType), got \(decodedType ?? "nil")")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case wallet, type
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
    /// External wallet-based authentication
    case externalWallet(ExternalWalletInfo)
    /// Identity-based authentication
    case identity(AuthIdentity)
    
    /// String representation for debugging
    public var debugDescription: String {
        switch self {
        case .email(let value):
            return "Email(\(value))"
        case .phone(let phoneNumber):
            return "Phone(\(phoneNumber))"
        case .externalWallet(let wallet):
            return "ExternalWallet(\(wallet.address), \(wallet.type.rawValue))"
        case .identity(let identity):
            return "Identity(\(identity.type), \(identity.identifier))"
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
        case .externalWallet(let wallet):
            try container.encode(wallet, forKey: .externalWallet)
        case .identity(let identity):
            try identity.encode(to: encoder)
        }
    }
    
    /// Coding keys for the Auth enum
    private enum CodingKeys: String, CodingKey {
        case email, phone, externalWallet
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
    /// The authentication identity information
    public let authIdentity: AuthIdentity?
    /// Display name for the authenticating user
    public let displayName: String?
    /// Profile picture URL for the authenticating user
    public let pfpUrl: String?
    /// Username for the authenticating user
    public let username: String?
    /// External wallet information
    public let externalWalletInfo: ExternalWalletInfo?
    /// Signature verification message for external wallet auth
    public let signatureVerificationMessage: String?
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
    ///   - authIdentity: Optional authentication identity
    ///   - displayName: Optional display name
    ///   - pfpUrl: Optional profile picture URL
    ///   - username: Optional username
    ///   - externalWalletInfo: Optional external wallet information
    ///   - signatureVerificationMessage: Optional signature verification message
    ///   - passkeyUrl: Optional passkey URL
    ///   - passkeyId: Optional passkey ID
    ///   - passkeyKnownDeviceUrl: Optional passkey known device URL
    ///   - passwordUrl: Optional password URL
    ///   - biometricHints: Optional biometric hints
    public init(
        stage: AuthStage,
        userId: String,
        authIdentity: AuthIdentity? = nil,
        displayName: String? = nil,
        pfpUrl: String? = nil,
        username: String? = nil,
        externalWalletInfo: ExternalWalletInfo? = nil,
        signatureVerificationMessage: String? = nil,
        passkeyUrl: String? = nil,
        passkeyId: String? = nil,
        passkeyKnownDeviceUrl: String? = nil,
        passwordUrl: String? = nil,
        biometricHints: [BiometricHint]? = nil
    ) {
        self.stage = stage
        self.userId = userId
        self.authIdentity = authIdentity
        self.displayName = displayName
        self.pfpUrl = pfpUrl
        self.username = username
        self.externalWalletInfo = externalWalletInfo
        self.signatureVerificationMessage = signatureVerificationMessage
        self.passkeyUrl = passkeyUrl
        self.passkeyId = passkeyId
        self.passkeyKnownDeviceUrl = passkeyKnownDeviceUrl
        self.passwordUrl = passwordUrl
        self.biometricHints = biometricHints
    }
    
    /// For backward compatibility with code expecting email field
    public var email: String? {
        if let emailIdentity = authIdentity as? EmailIdentity {
            return emailIdentity.email
        }
        return nil
    }
    
    // MARK: - Codable implementation
    
    /// Coding keys for encoding/decoding
    private enum CodingKeys: String, CodingKey {
        case stage, userId, displayName, pfpUrl, username
        case externalWalletInfo, signatureVerificationMessage
        case passkeyUrl, passkeyId, passkeyKnownDeviceUrl, passwordUrl, biometricHints
        case auth, type
    }
    
    /// Encode the auth state
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage, forKey: .stage)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(pfpUrl, forKey: .pfpUrl)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(externalWalletInfo, forKey: .externalWalletInfo)
        try container.encodeIfPresent(signatureVerificationMessage, forKey: .signatureVerificationMessage)
        try container.encodeIfPresent(passkeyUrl, forKey: .passkeyUrl)
        try container.encodeIfPresent(passkeyId, forKey: .passkeyId)
        try container.encodeIfPresent(passkeyKnownDeviceUrl, forKey: .passkeyKnownDeviceUrl)
        try container.encodeIfPresent(passwordUrl, forKey: .passwordUrl)
        try container.encodeIfPresent(biometricHints, forKey: .biometricHints)
        
        // Encode auth identity if present
        if let identity = authIdentity {
            try identity.encode(to: encoder)
        }
    }
    
    /// Initialize from decoder
    public init(from decoder: Decoder) throws {
        // We won't use our custom container-based decoding for now
        // Instead, we'll rely on manual approach for creating this object
        
        // Extract the container
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        stage = try container.decode(AuthStage.self, forKey: .stage)
        userId = try container.decode(String.self, forKey: .userId)
        
        // Decode optional fields
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        pfpUrl = try container.decodeIfPresent(String.self, forKey: .pfpUrl)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        externalWalletInfo = try container.decodeIfPresent(ExternalWalletInfo.self, forKey: .externalWalletInfo)
        signatureVerificationMessage = try container.decodeIfPresent(String.self, forKey: .signatureVerificationMessage)
        passkeyUrl = try container.decodeIfPresent(String.self, forKey: .passkeyUrl)
        passkeyId = try container.decodeIfPresent(String.self, forKey: .passkeyId)
        passkeyKnownDeviceUrl = try container.decodeIfPresent(String.self, forKey: .passkeyKnownDeviceUrl)
        passwordUrl = try container.decodeIfPresent(String.self, forKey: .passwordUrl)
        biometricHints = try container.decodeIfPresent([BiometricHint].self, forKey: .biometricHints)
        
        // For now, we won't try to decode the authIdentity directly
        // since this is causing compile errors. We'll rely on the auth info
        // being passed through the constructor after parsing the JSON
        // in the ParaManager methods
        authIdentity = nil
    }
}
