import Foundation

// MARK: - Headless On-Ramp Enums

/// Supported payment methods for routed headless on-ramp checkouts.
public enum ParaHeadlessOnRampPaymentMethod: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case card
    case applePay
    case googlePay
    case unknown(String)

    public static var allCases: [ParaHeadlessOnRampPaymentMethod] {
        [.card, .applePay, .googlePay]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "CARD": self = .card
        case "APPLE_PAY": self = .applePay
        case "GOOGLE_PAY": self = .googlePay
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .card: "CARD"
        case .applePay: "APPLE_PAY"
        case .googlePay: "GOOGLE_PAY"
        case let .unknown(value): value
        }
    }
}

/// Prerequisite steps returned by `getHeadlessOnRampRequirements` before placing an order.
public enum ParaHeadlessOnRampMissingStep: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case verification
    case share
    case contact
    case agreement
    case unknown(String)

    public static var allCases: [ParaHeadlessOnRampMissingStep] {
        [.verification, .share, .contact, .agreement]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "VERIFICATION": self = .verification
        case "SHARE": self = .share
        case "CONTACT": self = .contact
        case "AGREEMENT": self = .agreement
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .verification: "VERIFICATION"
        case .share: "SHARE"
        case .contact: "CONTACT"
        case .agreement: "AGREEMENT"
        case let .unknown(value): value
        }
    }
}

// MARK: - Headless On-Ramp Quote, Requirements & Order Models

/// Request parameters for `getHeadlessOnRampQuote`.
public struct ParaHeadlessOnRampQuoteParams: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let paymentMethod: ParaHeadlessOnRampPaymentMethod
    public let assetImplementationId: String
    public let fiatAmount: String
    public let fiat: String

    public init(
        provider: ParaOnRampProvider,
        paymentMethod: ParaHeadlessOnRampPaymentMethod,
        assetImplementationId: String,
        fiatAmount: String,
        fiat: String = "USD"
    ) {
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.assetImplementationId = assetImplementationId
        self.fiatAmount = fiatAmount
        self.fiat = fiat
    }
}

/// Fee breakdown for a headless on-ramp quote.
public struct ParaHeadlessOnRampQuoteFees: Codable, Sendable, Equatable {
    public let network: Double
    public let transaction: Double
    public let partner: Double
    public let total: Double

    public init(
        network: Double,
        transaction: Double,
        partner: Double,
        total: Double
    ) {
        self.network = network
        self.transaction = transaction
        self.partner = partner
        self.total = total
    }
}

/// Provider quote details returned by `getHeadlessOnRampQuote`.
public struct ParaHeadlessOnRampQuote: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let paymentMethod: ParaHeadlessOnRampPaymentMethod
    public let sourceAmount: Double
    public let sourceCurrency: String
    public let destinationAmount: Double
    public let exchangeRate: Double
    public let fees: ParaHeadlessOnRampQuoteFees

    public init(
        provider: ParaOnRampProvider,
        paymentMethod: ParaHeadlessOnRampPaymentMethod,
        sourceAmount: Double,
        sourceCurrency: String,
        destinationAmount: Double,
        exchangeRate: Double,
        fees: ParaHeadlessOnRampQuoteFees
    ) {
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.sourceAmount = sourceAmount
        self.sourceCurrency = sourceCurrency
        self.destinationAmount = destinationAmount
        self.exchangeRate = exchangeRate
        self.fees = fees
    }
}

/// Response wrapper returned by `getHeadlessOnRampQuote`.
public struct ParaHeadlessOnRampQuoteResult: Codable, Sendable, Equatable {
    public let quote: ParaHeadlessOnRampQuote

    public init(quote: ParaHeadlessOnRampQuote) {
        self.quote = quote
    }
}

/// Request parameters for `getHeadlessOnRampRequirements`.
public struct ParaHeadlessOnRampRequirementsParams: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let paymentMethod: ParaHeadlessOnRampPaymentMethod
    public let assetImplementationId: String
    public let fiatAmount: String
    public let fiat: String
    public let walletId: String?

    public init(
        provider: ParaOnRampProvider,
        paymentMethod: ParaHeadlessOnRampPaymentMethod,
        assetImplementationId: String,
        fiatAmount: String,
        fiat: String = "USD",
        walletId: String? = nil
    ) {
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.assetImplementationId = assetImplementationId
        self.fiatAmount = fiatAmount
        self.fiat = fiat
        self.walletId = walletId
    }
}

/// Legal agreement required before creating a headless on-ramp order.
public struct ParaHeadlessOnRampAgreement: Codable, Sendable, Equatable {
    public let code: String
    public let type: String
    public let url: String
    public let issuer: String?

    public init(
        code: String,
        type: String,
        url: String,
        issuer: String? = nil
    ) {
        self.code = code
        self.type = type
        self.url = url
        self.issuer = issuer
    }
}

/// Eligibility and required agreements returned by `getHeadlessOnRampRequirements`.
public struct ParaHeadlessOnRampRequirementsResult: Codable, Sendable, Equatable {
    public let eligible: Bool
    public let missingSteps: [ParaHeadlessOnRampMissingStep]
    public let agreements: [ParaHeadlessOnRampAgreement]

    public init(
        eligible: Bool,
        missingSteps: [ParaHeadlessOnRampMissingStep],
        agreements: [ParaHeadlessOnRampAgreement]
    ) {
        self.eligible = eligible
        self.missingSteps = missingSteps
        self.agreements = agreements
    }
}

/// Request parameters for `acceptHeadlessOnRampAgreements`.
public struct ParaHeadlessOnRampAgreementsParams: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let paymentMethod: ParaHeadlessOnRampPaymentMethod
    public let codes: [String]

    public init(
        provider: ParaOnRampProvider,
        paymentMethod: ParaHeadlessOnRampPaymentMethod,
        codes: [String]
    ) {
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.codes = codes
    }
}

/// Response returned by `acceptHeadlessOnRampAgreements`.
public struct ParaHeadlessOnRampAgreementsResult: Codable, Sendable, Equatable {
    public let acceptedCodes: [String]

    public init(acceptedCodes: [String]) {
        self.acceptedCodes = acceptedCodes
    }
}

/// Request parameters for `createHeadlessOnRampOrder`.
public struct ParaHeadlessOnRampOrderParams: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let paymentMethod: ParaHeadlessOnRampPaymentMethod
    public let assetImplementationId: String
    public let fiatAmount: String
    public let fiat: String
    public let walletId: String
    public let idempotencyKey: String

    public init(
        provider: ParaOnRampProvider,
        paymentMethod: ParaHeadlessOnRampPaymentMethod,
        assetImplementationId: String,
        fiatAmount: String,
        fiat: String = "USD",
        walletId: String,
        idempotencyKey: String
    ) {
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.assetImplementationId = assetImplementationId
        self.fiatAmount = fiatAmount
        self.fiat = fiat
        self.walletId = walletId
        self.idempotencyKey = idempotencyKey
    }
}

/// Response returned by `createHeadlessOnRampOrder`.
public struct ParaHeadlessOnRampOrderResult: Codable, Sendable, Equatable {
    public let purchaseId: String
    public let order: [String: BridgeJSONValue]

    public init(
        purchaseId: String,
        order: [String: BridgeJSONValue]
    ) {
        self.purchaseId = purchaseId
        self.order = order
    }

    public var orderId: String? {
        order["id"]?.stringValue
    }

    public var paymentMethodType: String? {
        order["paymentMethodType"]?.stringValue
    }

    public var providerSessionToken: String? {
        order["paymentMethodResponseDetails"]?.objectValue?["sessionToken"]?.stringValue
    }

    /// Serializes `order` into raw JSON bytes for native provider SDKs such as `MeldOrder.from(jsonData:)`.
    public func encodedOrderData() throws -> Data {
        try JSONEncoder().encode(order.mapValues(UnvalidatedBridgeJSONValue.init))
    }

    private enum CodingKeys: String, CodingKey {
        case purchaseId
        case order
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        purchaseId = try container.decode(String.self, forKey: .purchaseId)
        order = try container.decode([String: BridgeJSONValue].self, forKey: .order)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purchaseId, forKey: .purchaseId)
        try container.encode(order.mapValues(UnvalidatedBridgeJSONValue.init), forKey: .order)
    }
}

// MARK: - Reusable KYC Models

/// Verification lifecycle state returned by `getKycStatus`.
public enum ParaKycStatus: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case notStarted
    case inProgress
    case onHold
    case approved
    case rejected
    case unknown(String)

    public static var allCases: [ParaKycStatus] {
        [.notStarted, .inProgress, .onHold, .approved, .rejected]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "not_started": self = .notStarted
        case "in_progress": self = .inProgress
        case "on_hold": self = .onHold
        case "approved": self = .approved
        case "rejected": self = .rejected
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .notStarted: "not_started"
        case .inProgress: "in_progress"
        case .onHold: "on_hold"
        case .approved: "approved"
        case .rejected: "rejected"
        case let .unknown(value): value
        }
    }
}

/// Reusable KYC verification widget provider returned by `createKycSession`.
public enum ParaKycProvider: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case sumsub
    case unknown(String)

    public static var allCases: [ParaKycProvider] {
        [.sumsub]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "SUMSUB": self = .sumsub
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .sumsub: "SUMSUB"
        case let .unknown(value): value
        }
    }
}

/// Ramp provider that accepts shared reusable KYC credentials via `shareKyc`.
public enum ParaKycShareProvider: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case banxa
    case transak
    case moonpay
    case unknown(String)

    public static var allCases: [ParaKycShareProvider] {
        [.banxa, .transak, .moonpay]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "BANXA": self = .banxa
        case "TRANSAK": self = .transak
        case "MOONPAY": self = .moonpay
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .banxa: "BANXA"
        case .transak: "TRANSAK"
        case .moonpay: "MOONPAY"
        case let .unknown(value): value
        }
    }
}

/// Result status returned by `shareKyc`.
public enum ParaKycShareStatus: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case shared
    case failed
    case unknown(String)

    public static var allCases: [ParaKycShareStatus] {
        [.shared, .failed]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "shared": self = .shared
        case "failed": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .shared: "shared"
        case .failed: "failed"
        case let .unknown(value): value
        }
    }
}

/// Response returned by `getKycStatus`.
public struct ParaKycStatusResult: Codable, Sendable, Equatable {
    public let status: ParaKycStatus
    public let canRetry: Bool
    public let levelName: String?
    public let reviewedAt: String?
    public let sharedProviders: [ParaKycShareProvider]?

    public init(
        status: ParaKycStatus,
        canRetry: Bool,
        levelName: String? = nil,
        reviewedAt: String? = nil,
        sharedProviders: [ParaKycShareProvider]? = nil
    ) {
        self.status = status
        self.canRetry = canRetry
        self.levelName = levelName
        self.reviewedAt = reviewedAt
        self.sharedProviders = sharedProviders
    }
}

/// Response returned by `createKycSession`.
public struct ParaKycSessionResult: Codable, Sendable, Equatable {
    public let provider: ParaKycProvider
    public let accessToken: String

    public init(
        provider: ParaKycProvider,
        accessToken: String
    ) {
        self.provider = provider
        self.accessToken = accessToken
    }
}

/// Request parameters for `shareKyc`.
public struct ParaShareKycParams: Codable, Sendable, Equatable {
    public let provider: ParaKycShareProvider

    public init(provider: ParaKycShareProvider) {
        self.provider = provider
    }
}

/// Response returned by `shareKyc`.
public struct ParaShareKycResult: Codable, Sendable, Equatable {
    public let provider: ParaKycShareProvider
    public let status: ParaKycShareStatus

    public init(
        provider: ParaKycShareProvider,
        status: ParaKycShareStatus
    ) {
        self.provider = provider
        self.status = status
    }
}

// MARK: - Internal BridgeJSONValue Accessors

extension BridgeJSONValue {
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case let .decimal(value): value
        case let .integer(value): Double(value)
        default: nil
        }
    }

    var objectValue: [String: BridgeJSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [BridgeJSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }
}
