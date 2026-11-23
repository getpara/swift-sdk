import Foundation

// MARK: - Decoding Helpers

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return String(intValue)
        }
        let doubleValue = try decode(Double.self, forKey: key)
        return String(doubleValue)
    }
}

// MARK: - Enums

/// On-ramp and off-ramp liquidity providers supported by the Para bridge.
public enum ParaOnRampProvider: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case stripe
    case moonpay
    case ramp
    case coinbase
    case cdp
    case transak
    case banxa
    case brale
    case mercuryo
    case unknown(String)

    public static var allCases: [ParaOnRampProvider] {
        [.stripe, .moonpay, .ramp, .coinbase, .cdp, .transak, .banxa, .brale, .mercuryo]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "STRIPE": self = .stripe
        case "MOONPAY": self = .moonpay
        case "RAMP": self = .ramp
        case "COINBASE": self = .coinbase
        case "CDP": self = .cdp
        case "TRANSAK": self = .transak
        case "BANXA": self = .banxa
        case "BRALE": self = .brale
        case "MERCURYO": self = .mercuryo
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .stripe: "STRIPE"
        case .moonpay: "MOONPAY"
        case .ramp: "RAMP"
        case .coinbase: "COINBASE"
        case .cdp: "CDP"
        case .transak: "TRANSAK"
        case .banxa: "BANXA"
        case .brale: "BRALE"
        case .mercuryo: "MERCURYO"
        case let .unknown(value): value
        }
    }
}

/// Payment methods offered by an on-ramp provider.
public enum ParaOnRampPaymentMethod: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case widget
    case applePay
    case card
    case bank
    case unknown(String)

    public static var allCases: [ParaOnRampPaymentMethod] {
        [.widget, .applePay, .card, .bank]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "WIDGET": self = .widget
        case "APPLE_PAY": self = .applePay
        case "CARD": self = .card
        case "BANK": self = .bank
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .widget: "WIDGET"
        case .applePay: "APPLE_PAY"
        case .card: "CARD"
        case .bank: "BANK"
        case let .unknown(value): value
        }
    }
}

/// Direction of a ramp order.
public enum ParaOnRampPurchaseType: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case buy
    case sell
    case unknown(String)

    public static var allCases: [ParaOnRampPurchaseType] {
        [.buy, .sell]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "BUY": self = .buy
        case "SELL": self = .sell
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .buy: "BUY"
        case .sell: "SELL"
        case let .unknown(value): value
        }
    }
}

/// Lifecycle status of a ramp purchase.
public enum ParaOnRampPurchaseStatus: RawRepresentable, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case initiated
    case finished
    case cancelled
    case failed
    case unknown(String)

    public static var allCases: [ParaOnRampPurchaseStatus] {
        [.initiated, .finished, .cancelled, .failed]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "INITIATED": self = .initiated
        case "FINISHED": self = .finished
        case "CANCELLED": self = .cancelled
        case "FAILED": self = .failed
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .initiated: "INITIATED"
        case .finished: "FINISHED"
        case .cancelled: "CANCELLED"
        case .failed: "FAILED"
        case let .unknown(value): value
        }
    }
}

// MARK: - Config & Catalog

/// Currency-denominated default amount returned by `getOnRampConfig`.
public struct ParaOnRampAmountValue: Codable, Sendable, Equatable {
    public let value: Double
    public let currency: String

    public init(value: Double, currency: String) {
        self.value = value
        self.currency = currency
    }
}

/// Provider availability and limits for a catalog asset implementation.
public struct ParaOnRampProviderSupport: Codable, Sendable, Equatable {
    public let provider: ParaOnRampProvider
    public let isBuy: Bool
    public let isSell: Bool
    public let paymentMethods: [ParaOnRampPaymentMethod]
    public let minAmount: Double?
    public let maxAmount: Double?

    public init(
        provider: ParaOnRampProvider,
        isBuy: Bool,
        isSell: Bool,
        paymentMethods: [ParaOnRampPaymentMethod],
        minAmount: Double? = nil,
        maxAmount: Double? = nil
    ) {
        self.provider = provider
        self.isBuy = isBuy
        self.isSell = isSell
        self.paymentMethods = paymentMethods
        self.minAmount = minAmount
        self.maxAmount = maxAmount
    }
}

/// Partner-configured catalog asset implementation entry.
public struct ParaOnRampCatalogItem: Codable, Sendable, Equatable {
    public let assetImplementationId: String
    public let assetId: String
    public let symbol: String
    public let name: String
    public let logoUrl: String?
    public let marketCapRank: Int
    public let networkId: String
    public let chainId: String?
    public let networkName: String
    public let networkLogoUrl: String?
    public let walletType: String
    public let isTestnet: Bool
    public let contractAddress: String?
    public let decimals: Int?
    public let providers: [ParaOnRampProviderSupport]

    public init(
        assetImplementationId: String,
        assetId: String,
        symbol: String,
        name: String,
        logoUrl: String? = nil,
        marketCapRank: Int,
        networkId: String,
        chainId: String? = nil,
        networkName: String,
        networkLogoUrl: String? = nil,
        walletType: String,
        isTestnet: Bool,
        contractAddress: String? = nil,
        decimals: Int? = nil,
        providers: [ParaOnRampProviderSupport]
    ) {
        self.assetImplementationId = assetImplementationId
        self.assetId = assetId
        self.symbol = symbol
        self.name = name
        self.logoUrl = logoUrl
        self.marketCapRank = marketCapRank
        self.networkId = networkId
        self.chainId = chainId
        self.networkName = networkName
        self.networkLogoUrl = networkLogoUrl
        self.walletType = walletType
        self.isTestnet = isTestnet
        self.contractAddress = contractAddress
        self.decimals = decimals
        self.providers = providers
    }
}

/// Paginated response returned by `getOnRampCatalog`.
public struct ParaOnRampCatalogResponse: Codable, Sendable, Equatable {
    public let items: [ParaOnRampCatalogItem]
    public let total: Int
    public let limit: Int
    public let offset: Int

    public init(items: [ParaOnRampCatalogItem], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

/// Asset selector used when creating an order without an explicit `assetImplementationId`.
public struct ParaOnRampAssetSelector: Codable, Sendable, Equatable {
    public let chainId: String?
    public let contractAddress: String?
    public let symbol: String?

    public init(chainId: String? = nil, contractAddress: String? = nil, symbol: String? = nil) {
        self.chainId = chainId
        self.contractAddress = contractAddress
        self.symbol = symbol
    }
}

/// Partner-level on-ramp configuration returned by `getOnRampConfig`.
public struct ParaOnRampConfig: Codable, Sendable, Equatable {
    public let isBuyEnabled: Bool
    public let isReceiveEnabled: Bool
    public let isWithdrawEnabled: Bool
    public let isSendEnabled: Bool
    public let onRampSelectionMode: String
    public let defaultOnRampAssetImplementation: ParaOnRampCatalogItem?
    public let defaultBuyAmount: ParaOnRampAmountValue?
    public let rampApiKey: String?
    public let inlineApplePayProviders: [ParaOnRampProvider]?
    public let reusableKycEnabled: Bool?

    public init(
        isBuyEnabled: Bool,
        isReceiveEnabled: Bool,
        isWithdrawEnabled: Bool,
        isSendEnabled: Bool,
        onRampSelectionMode: String,
        defaultOnRampAssetImplementation: ParaOnRampCatalogItem? = nil,
        defaultBuyAmount: ParaOnRampAmountValue? = nil,
        rampApiKey: String? = nil,
        inlineApplePayProviders: [ParaOnRampProvider]? = nil,
        reusableKycEnabled: Bool? = nil
    ) {
        self.isBuyEnabled = isBuyEnabled
        self.isReceiveEnabled = isReceiveEnabled
        self.isWithdrawEnabled = isWithdrawEnabled
        self.isSendEnabled = isSendEnabled
        self.onRampSelectionMode = onRampSelectionMode
        self.defaultOnRampAssetImplementation = defaultOnRampAssetImplementation
        self.defaultBuyAmount = defaultBuyAmount
        self.rampApiKey = rampApiKey
        self.inlineApplePayProviders = inlineApplePayProviders
        self.reusableKycEnabled = reusableKycEnabled
    }
}

// MARK: - Purchases, Orders & Off-Ramp Deposits

/// Canonical on-ramp or off-ramp purchase record.
public struct ParaOnRampPurchase: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String?
    public let type: ParaOnRampPurchaseType?
    public let walletId: String?
    public let walletType: String?
    public let externalWalletAddress: String?
    public let address: String?
    public let status: ParaOnRampPurchaseStatus?
    public let provider: ParaOnRampProvider?
    public let providerKey: String?
    public let fiat: String?
    public let fiatCurrency: String?
    public let fiatQuantity: String?
    public let asset: String?
    public let assetQuantity: String?
    public let network: String?
    public let providerAssetCode: String?
    public let assetImplementationId: String?
    public let paymentMethod: ParaOnRampPaymentMethod?
    public let transactionHash: String?
    public let launchToken: String?
    public let testMode: Bool?

    public init(
        id: String,
        userId: String? = nil,
        type: ParaOnRampPurchaseType? = nil,
        walletId: String? = nil,
        walletType: String? = nil,
        externalWalletAddress: String? = nil,
        address: String? = nil,
        status: ParaOnRampPurchaseStatus? = nil,
        provider: ParaOnRampProvider? = nil,
        providerKey: String? = nil,
        fiat: String? = nil,
        fiatCurrency: String? = nil,
        fiatQuantity: String? = nil,
        asset: String? = nil,
        assetQuantity: String? = nil,
        network: String? = nil,
        providerAssetCode: String? = nil,
        assetImplementationId: String? = nil,
        paymentMethod: ParaOnRampPaymentMethod? = nil,
        transactionHash: String? = nil,
        launchToken: String? = nil,
        testMode: Bool? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.walletId = walletId
        self.walletType = walletType
        self.externalWalletAddress = externalWalletAddress
        self.address = address
        self.status = status
        self.provider = provider
        self.providerKey = providerKey
        self.fiat = fiat
        self.fiatCurrency = fiatCurrency
        self.fiatQuantity = fiatQuantity
        self.asset = asset
        self.assetQuantity = assetQuantity
        self.network = network
        self.providerAssetCode = providerAssetCode
        self.assetImplementationId = assetImplementationId
        self.paymentMethod = paymentMethod
        self.transactionHash = transactionHash
        self.launchToken = launchToken
        self.testMode = testMode
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case type
        case walletId
        case walletType
        case externalWalletAddress
        case address
        case status
        case provider
        case providerKey
        case fiat
        case fiatCurrency
        case fiatQuantity
        case asset
        case assetQuantity
        case network
        case providerAssetCode
        case assetImplementationId
        case paymentMethod
        case transactionHash
        case launchToken
        case testMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        type = try container.decodeIfPresent(ParaOnRampPurchaseType.self, forKey: .type)
        walletId = try container.decodeIfPresent(String.self, forKey: .walletId)
        walletType = try container.decodeIfPresent(String.self, forKey: .walletType)
        externalWalletAddress = try container.decodeIfPresent(String.self, forKey: .externalWalletAddress)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        status = try container.decodeIfPresent(ParaOnRampPurchaseStatus.self, forKey: .status)
        provider = try container.decodeIfPresent(ParaOnRampProvider.self, forKey: .provider)
        providerKey = try container.decodeIfPresent(String.self, forKey: .providerKey)
        fiat = try container.decodeIfPresent(String.self, forKey: .fiat)
        fiatCurrency = try container.decodeIfPresent(String.self, forKey: .fiatCurrency)
        fiatQuantity = try container.decodeFlexibleStringIfPresent(forKey: .fiatQuantity)
        asset = try container.decodeIfPresent(String.self, forKey: .asset)
        assetQuantity = try container.decodeFlexibleStringIfPresent(forKey: .assetQuantity)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        providerAssetCode = try container.decodeIfPresent(String.self, forKey: .providerAssetCode)
        assetImplementationId = try container.decodeIfPresent(String.self, forKey: .assetImplementationId)
        paymentMethod = try container.decodeIfPresent(ParaOnRampPaymentMethod.self, forKey: .paymentMethod)
        transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
        launchToken = try container.decodeIfPresent(String.self, forKey: .launchToken)
        testMode = try container.decodeIfPresent(Bool.self, forKey: .testMode)
    }
}

/// Pending seller deposit instructions stored on an open off-ramp purchase.
public struct ParaPendingOffRampDeposit: Codable, Sendable, Equatable {
    public let destinationAddress: String
    public let assetQuantity: String
    public let asset: String?
    public let network: String?
    public let updatedAt: String?

    public init(
        destinationAddress: String,
        assetQuantity: String,
        asset: String? = nil,
        network: String? = nil,
        updatedAt: String? = nil
    ) {
        self.destinationAddress = destinationAddress
        self.assetQuantity = assetQuantity
        self.asset = asset
        self.network = network
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case destinationAddress
        case assetQuantity
        case asset
        case network
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        destinationAddress = try container.decode(String.self, forKey: .destinationAddress)
        guard let quantity = try container.decodeFlexibleStringIfPresent(forKey: .assetQuantity) else {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: container.codingPath + [CodingKeys.assetQuantity], debugDescription: "Missing assetQuantity")
            )
        }
        assetQuantity = quantity
        asset = try container.decodeIfPresent(String.self, forKey: .asset)
        network = try container.decodeIfPresent(String.self, forKey: .network)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// Parameters passed to `createOnRampOrder`.
public struct ParaCreateOnRampOrderParams: Codable, Sendable, Equatable {
    public let walletId: String?
    public let externalWalletAddress: String?
    public let walletType: String?
    public let address: String?
    public let provider: ParaOnRampProvider
    public let type: ParaOnRampPurchaseType
    public let assetImplementationId: String?
    public let assetSelector: ParaOnRampAssetSelector?
    public let asset: String?
    public let network: String?
    public let fiat: String?
    public let fiatQuantity: String?
    public let assetQuantity: String?
    public let paymentMethod: ParaOnRampPaymentMethod?
    public let returnUrl: String?
    public let nativeCallbackUrl: String?
    public let purchaseId: String?
    public let testMode: Bool?

    public init(
        walletId: String? = nil,
        externalWalletAddress: String? = nil,
        walletType: String? = nil,
        address: String? = nil,
        provider: ParaOnRampProvider,
        type: ParaOnRampPurchaseType = .buy,
        assetImplementationId: String? = nil,
        assetSelector: ParaOnRampAssetSelector? = nil,
        asset: String? = nil,
        network: String? = nil,
        fiat: String? = nil,
        fiatQuantity: String? = nil,
        assetQuantity: String? = nil,
        paymentMethod: ParaOnRampPaymentMethod? = nil,
        returnUrl: String? = nil,
        nativeCallbackUrl: String? = nil,
        purchaseId: String? = nil,
        testMode: Bool? = nil
    ) {
        self.walletId = walletId
        self.externalWalletAddress = externalWalletAddress
        self.walletType = walletType
        self.address = address
        self.provider = provider
        self.type = type
        self.assetImplementationId = assetImplementationId
        self.assetSelector = assetSelector
        self.asset = asset
        self.network = network
        self.fiat = fiat
        self.fiatQuantity = fiatQuantity
        self.assetQuantity = assetQuantity
        self.paymentMethod = paymentMethod
        self.returnUrl = returnUrl
        self.nativeCallbackUrl = nativeCallbackUrl
        self.purchaseId = purchaseId
        self.testMode = testMode
    }
}

/// Result returned by `createOnRampOrder`.
public struct ParaCreateOnRampOrderResult: Codable, Sendable, Equatable {
    public let onRampPurchase: ParaOnRampPurchase
    public let portalUrl: String

    public init(onRampPurchase: ParaOnRampPurchase, portalUrl: String) {
        self.onRampPurchase = onRampPurchase
        self.portalUrl = portalUrl
    }
}

/// Result returned by `getOnRampOrder`.
public struct ParaGetOnRampOrderResult: Codable, Sendable, Equatable {
    public let onRampPurchase: ParaOnRampPurchase
    public let eventData: ParaOnRampEventPayload?
    public let pendingDeposit: ParaPendingOffRampDeposit?

    public init(
        onRampPurchase: ParaOnRampPurchase,
        eventData: ParaOnRampEventPayload? = nil,
        pendingDeposit: ParaPendingOffRampDeposit? = nil
    ) {
        self.onRampPurchase = onRampPurchase
        self.eventData = eventData
        self.pendingDeposit = pendingDeposit
    }
}

/// Parameters passed to `sendOffRampDeposit`.
public struct ParaSendOffRampDepositParams: Codable, Sendable, Equatable {
    public let purchaseId: String
    public let walletId: String?
    public let externalWalletAddress: String?
    public let walletType: String?
    public let provider: ParaOnRampProvider?
    public let address: String?
    public let destinationAddress: String
    public let assetQuantity: String
    public let chainId: String?
    public let contractAddress: String?
    public let asset: String?
    public let network: String?
    public let fiat: String?
    public let fiatQuantity: String?
    public let providerOrderId: String?
    public let testMode: Bool?

    public init(
        purchaseId: String,
        walletId: String? = nil,
        externalWalletAddress: String? = nil,
        walletType: String? = nil,
        provider: ParaOnRampProvider? = nil,
        address: String? = nil,
        destinationAddress: String,
        assetQuantity: String,
        chainId: String? = nil,
        contractAddress: String? = nil,
        asset: String? = nil,
        network: String? = nil,
        fiat: String? = nil,
        fiatQuantity: String? = nil,
        providerOrderId: String? = nil,
        testMode: Bool? = nil
    ) {
        self.purchaseId = purchaseId
        self.walletId = walletId
        self.externalWalletAddress = externalWalletAddress
        self.walletType = walletType
        self.provider = provider
        self.address = address
        self.destinationAddress = destinationAddress
        self.assetQuantity = assetQuantity
        self.chainId = chainId
        self.contractAddress = contractAddress
        self.asset = asset
        self.network = network
        self.fiat = fiat
        self.fiatQuantity = fiatQuantity
        self.providerOrderId = providerOrderId
        self.testMode = testMode
    }
}

/// Result returned by `sendOffRampDeposit`.
public struct ParaSendOffRampDepositResult: Codable, Sendable, Equatable {
    public let txHash: String
    public let onRampPurchase: ParaOnRampPurchase?

    public init(txHash: String, onRampPurchase: ParaOnRampPurchase? = nil) {
        self.txHash = txHash
        self.onRampPurchase = onRampPurchase
    }

    private enum CodingKeys: String, CodingKey {
        case txHash
        case onRampPurchase
        case updatedOnRampPurchase
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        txHash = try container.decode(String.self, forKey: .txHash)
        onRampPurchase = try container.decodeIfPresent(ParaOnRampPurchase.self, forKey: .onRampPurchase)
            ?? container.decodeIfPresent(ParaOnRampPurchase.self, forKey: .updatedOnRampPurchase)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(txHash, forKey: .txHash)
        try container.encodeIfPresent(onRampPurchase, forKey: .onRampPurchase)
    }
}

// MARK: - Brale ACH Models

/// Customer attributes used to prefill Brale's Plaid bank-link flow.
public struct ParaBraleAchCustomer: Codable, Sendable, Equatable {
    public let legalName: String?

    public init(legalName: String? = nil) {
        self.legalName = legalName
    }
}

/// Parameters passed to `createBraleAchCheckout`.
public struct ParaCreateBraleAchCheckoutParams: Codable, Sendable, Equatable {
    public let walletId: String
    public let assetImplementationId: String?
    public let amountUsd: String
    public let customer: ParaBraleAchCustomer?
    public let linkNewBank: Bool?
    public let testMode: Bool?
    public let platform: String?

    public init(
        walletId: String,
        assetImplementationId: String? = nil,
        amountUsd: String,
        customer: ParaBraleAchCustomer? = nil,
        linkNewBank: Bool? = nil,
        testMode: Bool? = nil,
        platform: String? = nil
    ) {
        self.walletId = walletId
        self.assetImplementationId = assetImplementationId
        self.amountUsd = amountUsd
        self.customer = customer
        self.linkNewBank = linkNewBank
        self.testMode = testMode
        self.platform = platform
    }

    func withPlatform(_ platform: String) -> ParaCreateBraleAchCheckoutParams {
        ParaCreateBraleAchCheckoutParams(
            walletId: walletId,
            assetImplementationId: assetImplementationId,
            amountUsd: amountUsd,
            customer: customer,
            linkNewBank: linkNewBank,
            testMode: testMode,
            platform: platform
        )
    }
}

/// Failure details returned on a Brale ACH checkout or transfer.
public struct ParaBraleAchFailure: Codable, Sendable, Equatable {
    public let returnCode: String?
    public let reason: String
    public let category: String?
    public let retriable: Bool?

    public init(returnCode: String? = nil, reason: String, category: String? = nil, retriable: Bool? = nil) {
        self.returnCode = returnCode
        self.reason = reason
        self.category = category
        self.retriable = retriable
    }
}

/// Saved bank account summary returned on a Brale ACH checkout.
public struct ParaBraleAchSavedBank: Codable, Sendable, Equatable {
    public let name: String
    public let accountType: String
    public let accountNumberMask: String
    public let needsUpdate: Bool

    public init(name: String, accountType: String, accountNumberMask: String, needsUpdate: Bool) {
        self.name = name
        self.accountType = accountType
        self.accountNumberMask = accountNumberMask
        self.needsUpdate = needsUpdate
    }
}

/// Brale ACH checkout state.
public struct ParaBraleAchCheckout: Codable, Sendable, Equatable {
    public let id: String
    public let walletId: String
    public let amountUsd: String
    public let stage: String
    public let nextAction: String
    public let linkTokenExpiresAt: String?
    public let plaidLinkToken: String?
    public let purchaseId: String?
    public let braleStatus: String?
    public let failure: ParaBraleAchFailure?
    public let savedBank: ParaBraleAchSavedBank?

    public init(
        id: String,
        walletId: String,
        amountUsd: String,
        stage: String,
        nextAction: String,
        linkTokenExpiresAt: String? = nil,
        plaidLinkToken: String? = nil,
        purchaseId: String? = nil,
        braleStatus: String? = nil,
        failure: ParaBraleAchFailure? = nil,
        savedBank: ParaBraleAchSavedBank? = nil
    ) {
        self.id = id
        self.walletId = walletId
        self.amountUsd = amountUsd
        self.stage = stage
        self.nextAction = nextAction
        self.linkTokenExpiresAt = linkTokenExpiresAt
        self.plaidLinkToken = plaidLinkToken
        self.purchaseId = purchaseId
        self.braleStatus = braleStatus
        self.failure = failure
        self.savedBank = savedBank
    }
}

/// Brale ACH authorization text and version returned by `getBraleAchAuthorization`.
public struct ParaBraleAchAuthorization: Codable, Sendable, Equatable {
    public let version: String
    public let text: String

    public init(version: String, text: String) {
        self.version = version
        self.text = text
    }
}

/// Submitted Brale ACH transfer summary returned by `listBraleAchTransfers`.
public struct ParaBraleTransferItem: Codable, Sendable, Equatable {
    public let checkoutId: String
    public let purchaseId: String
    public let assetImplementationId: String
    public let amountUsd: String
    public let asset: String
    public let network: String
    public let bankAccountMask: String?
    public let stage: String
    public let braleStatus: String?
    public let createdAt: String
    public let failedAt: String?
    public let failure: ParaBraleAchFailure?

    public init(
        checkoutId: String,
        purchaseId: String,
        assetImplementationId: String,
        amountUsd: String,
        asset: String,
        network: String,
        bankAccountMask: String? = nil,
        stage: String,
        braleStatus: String? = nil,
        createdAt: String,
        failedAt: String? = nil,
        failure: ParaBraleAchFailure? = nil
    ) {
        self.checkoutId = checkoutId
        self.purchaseId = purchaseId
        self.assetImplementationId = assetImplementationId
        self.amountUsd = amountUsd
        self.asset = asset
        self.network = network
        self.bankAccountMask = bankAccountMask
        self.stage = stage
        self.braleStatus = braleStatus
        self.createdAt = createdAt
        self.failedAt = failedAt
        self.failure = failure
    }
}

/// Response returned by `listBraleAchTransfers`.
public struct ParaBraleTransferListResponse: Codable, Sendable, Equatable {
    public let transfers: [ParaBraleTransferItem]

    public init(transfers: [ParaBraleTransferItem]) {
        self.transfers = transfers
    }
}

// MARK: - Coinbase Headless Models

/// Parameters passed to `createCoinbaseOnrampOrder`.
public struct ParaCoinbaseOrderParams: Codable, Sendable, Equatable {
    public let isQuote: Bool?
    public let paymentAmount: String?
    public let purchaseAmount: String?
    public let assetImplementationId: String?
    public let purchaseCurrency: String?
    public let walletId: String?
    public let destinationAddress: String?
    public let destinationNetwork: String?
    public let phoneNumber: String
    public let phoneNumberVerifiedAt: String?
    public let email: String?
    public let agreementAcceptedAt: String?
    public let domain: String?
    public let purchaseId: String?
    public let testMode: Bool?

    public init(
        isQuote: Bool? = nil,
        paymentAmount: String? = nil,
        purchaseAmount: String? = nil,
        assetImplementationId: String? = nil,
        purchaseCurrency: String? = nil,
        walletId: String? = nil,
        destinationAddress: String? = nil,
        destinationNetwork: String? = nil,
        phoneNumber: String,
        phoneNumberVerifiedAt: String? = nil,
        email: String? = nil,
        agreementAcceptedAt: String? = nil,
        domain: String? = nil,
        purchaseId: String? = nil,
        testMode: Bool? = nil
    ) {
        self.isQuote = isQuote
        self.paymentAmount = paymentAmount
        self.purchaseAmount = purchaseAmount
        self.assetImplementationId = assetImplementationId
        self.purchaseCurrency = purchaseCurrency
        self.walletId = walletId
        self.destinationAddress = destinationAddress
        self.destinationNetwork = destinationNetwork
        self.phoneNumber = phoneNumber
        self.phoneNumberVerifiedAt = phoneNumberVerifiedAt
        self.email = email
        self.agreementAcceptedAt = agreementAcceptedAt
        self.domain = domain
        self.purchaseId = purchaseId
        self.testMode = testMode
    }
}

/// Fee entry on a Coinbase headless order.
public struct ParaCoinbaseHeadlessFee: Codable, Sendable, Equatable {
    public let type: String?
    public let amount: String?
    public let currency: String?

    public init(type: String? = nil, amount: String? = nil, currency: String? = nil) {
        self.type = type
        self.amount = amount
        self.currency = currency
    }
}

/// Order details nested inside `ParaCoinbaseOrderResult`.
public struct ParaCoinbaseOrderDetails: Codable, Sendable, Equatable {
    public let orderId: String?
    public let paymentTotal: String?
    public let paymentSubtotal: String?
    public let paymentCurrency: String?
    public let purchaseAmount: String?
    public let purchaseCurrency: String?
    public let fees: [ParaCoinbaseHeadlessFee]?
    public let exchangeRate: String?
    public let destinationAddress: String?
    public let destinationNetwork: String?
    public let status: String?
    public let txHash: String?

    public init(
        orderId: String? = nil,
        paymentTotal: String? = nil,
        paymentSubtotal: String? = nil,
        paymentCurrency: String? = nil,
        purchaseAmount: String? = nil,
        purchaseCurrency: String? = nil,
        fees: [ParaCoinbaseHeadlessFee]? = nil,
        exchangeRate: String? = nil,
        destinationAddress: String? = nil,
        destinationNetwork: String? = nil,
        status: String? = nil,
        txHash: String? = nil
    ) {
        self.orderId = orderId
        self.paymentTotal = paymentTotal
        self.paymentSubtotal = paymentSubtotal
        self.paymentCurrency = paymentCurrency
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrency = purchaseCurrency
        self.fees = fees
        self.exchangeRate = exchangeRate
        self.destinationAddress = destinationAddress
        self.destinationNetwork = destinationNetwork
        self.status = status
        self.txHash = txHash
    }
}

/// Payment link returned for a Coinbase headless Apple Pay order.
public struct ParaCoinbasePaymentLink: Codable, Sendable, Equatable {
    public let url: String?
    public let paymentLinkType: String?

    public init(url: String? = nil, paymentLinkType: String? = nil) {
        self.url = url
        self.paymentLinkType = paymentLinkType
    }
}

/// Result returned by `createCoinbaseOnrampOrder`.
public struct ParaCoinbaseOrderResult: Codable, Sendable, Equatable {
    public let purchaseId: String?
    public let order: ParaCoinbaseOrderDetails?
    public let paymentLink: ParaCoinbasePaymentLink?
    public let assetImplementation: ParaOnRampCatalogItem?

    public init(
        purchaseId: String? = nil,
        order: ParaCoinbaseOrderDetails? = nil,
        paymentLink: ParaCoinbasePaymentLink? = nil,
        assetImplementation: ParaOnRampCatalogItem? = nil
    ) {
        self.purchaseId = purchaseId
        self.order = order
        self.paymentLink = paymentLink
        self.assetImplementation = assetImplementation
    }
}

/// Parameters passed to `checkCoinbaseOnrampLimits`.
public struct ParaCoinbaseLimitsParams: Codable, Sendable, Equatable {
    public let testMode: Bool?
    public let phoneNumber: String?

    public init(testMode: Bool? = nil, phoneNumber: String? = nil) {
        self.testMode = testMode
        self.phoneNumber = phoneNumber
    }
}

/// Individual Coinbase guest-checkout limit entry.
public struct ParaCoinbaseLimit: Codable, Sendable, Equatable {
    public let limitType: String?
    public let limit: String?
    public let remaining: String?
    public let currency: String?

    public init(limitType: String? = nil, limit: String? = nil, remaining: String? = nil, currency: String? = nil) {
        self.limitType = limitType
        self.limit = limit
        self.remaining = remaining
        self.currency = currency
    }
}

/// Result returned by `checkCoinbaseOnrampLimits`.
public struct ParaCoinbaseLimitsResult: Codable, Sendable, Equatable {
    public let limits: [ParaCoinbaseLimit]?
    public let status: String?
    public let upgradeable: Bool?

    public init(limits: [ParaCoinbaseLimit]? = nil, status: String? = nil, upgradeable: Bool? = nil) {
        self.limits = limits
        self.status = status
        self.upgradeable = upgradeable
    }
}

/// Parameters passed to `createCoinbaseOnrampLimitUpgrade`.
public struct ParaCoinbaseLimitUpgradeParams: Codable, Sendable, Equatable {
    public let testMode: Bool?
    public let phoneNumber: String?

    public init(testMode: Bool? = nil, phoneNumber: String? = nil) {
        self.testMode = testMode
        self.phoneNumber = phoneNumber
    }
}

/// Result returned by `createCoinbaseOnrampLimitUpgrade`.
public struct ParaCoinbaseLimitUpgradeResult: Codable, Sendable, Equatable {
    public let upgradeUrl: String?
    public let expiresAt: String?

    public init(upgradeUrl: String? = nil, expiresAt: String? = nil) {
        self.upgradeUrl = upgradeUrl
        self.expiresAt = expiresAt
    }
}

// MARK: - On-Ramp Events & Portal Callback

/// Asset details emitted in an on-ramp bridge event.
public struct ParaOnRampEventAsset: Codable, Sendable, Equatable {
    public let symbol: String?
    public let name: String?
    public let contractAddress: String?
    public let type: String?
    public let chainId: String?
    public let networkName: String?
    public let decimals: Int?

    public init(
        symbol: String? = nil,
        name: String? = nil,
        contractAddress: String? = nil,
        type: String? = nil,
        chainId: String? = nil,
        networkName: String? = nil,
        decimals: Int? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.contractAddress = contractAddress
        self.type = type
        self.chainId = chainId
        self.networkName = networkName
        self.decimals = decimals
    }
}

/// Curated on-ramp event payload matching the canonical `onramp.completed` / `Para#event` schema.
public struct ParaOnRampEventPayload: Codable, Sendable, Equatable {
    public let userId: String?
    public let purchaseId: String
    public let provider: ParaOnRampProvider?
    public let direction: ParaOnRampPurchaseType?
    public let paymentMethod: ParaOnRampPaymentMethod?
    public let transactionHash: String?
    public let asset: ParaOnRampEventAsset?
    public let assetQuantity: String?
    public let fiatAmount: String?
    public let fiatCurrency: String?
    public let walletId: String?
    public let destinationAddress: String?
    public let providerOrderId: String?
    public let providerTransactionId: String?
    public let testMode: Bool?
    public let completedAt: String?

    public init(
        userId: String? = nil,
        purchaseId: String,
        provider: ParaOnRampProvider? = nil,
        direction: ParaOnRampPurchaseType? = nil,
        paymentMethod: ParaOnRampPaymentMethod? = nil,
        transactionHash: String? = nil,
        asset: ParaOnRampEventAsset? = nil,
        assetQuantity: String? = nil,
        fiatAmount: String? = nil,
        fiatCurrency: String? = nil,
        walletId: String? = nil,
        destinationAddress: String? = nil,
        providerOrderId: String? = nil,
        providerTransactionId: String? = nil,
        testMode: Bool? = nil,
        completedAt: String? = nil
    ) {
        self.userId = userId
        self.purchaseId = purchaseId
        self.provider = provider
        self.direction = direction
        self.paymentMethod = paymentMethod
        self.transactionHash = transactionHash
        self.asset = asset
        self.assetQuantity = assetQuantity
        self.fiatAmount = fiatAmount
        self.fiatCurrency = fiatCurrency
        self.walletId = walletId
        self.destinationAddress = destinationAddress
        self.providerOrderId = providerOrderId
        self.providerTransactionId = providerTransactionId
        self.testMode = testMode
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case userId
        case purchaseId
        case id
        case provider
        case direction
        case paymentMethod
        case transactionHash
        case asset
        case assetQuantity
        case fiatAmount
        case fiatCurrency
        case walletId
        case destinationAddress
        case providerOrderId
        case providerTransactionId
        case testMode
        case completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        if let decodedPurchaseId = try container.decodeIfPresent(String.self, forKey: .purchaseId) {
            purchaseId = decodedPurchaseId
        } else {
            purchaseId = try container.decode(String.self, forKey: .id)
        }
        provider = try container.decodeIfPresent(ParaOnRampProvider.self, forKey: .provider)
        direction = try container.decodeIfPresent(ParaOnRampPurchaseType.self, forKey: .direction)
        paymentMethod = try container.decodeIfPresent(ParaOnRampPaymentMethod.self, forKey: .paymentMethod)
        transactionHash = try container.decodeIfPresent(String.self, forKey: .transactionHash)
        asset = try container.decodeIfPresent(ParaOnRampEventAsset.self, forKey: .asset)
        assetQuantity = try container.decodeFlexibleStringIfPresent(forKey: .assetQuantity)
        fiatAmount = try container.decodeFlexibleStringIfPresent(forKey: .fiatAmount)
        fiatCurrency = try container.decodeIfPresent(String.self, forKey: .fiatCurrency)
        walletId = try container.decodeIfPresent(String.self, forKey: .walletId)
        destinationAddress = try container.decodeIfPresent(String.self, forKey: .destinationAddress)
        providerOrderId = try container.decodeIfPresent(String.self, forKey: .providerOrderId)
        providerTransactionId = try container.decodeIfPresent(String.self, forKey: .providerTransactionId)
        testMode = try container.decodeIfPresent(Bool.self, forKey: .testMode)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(purchaseId, forKey: .purchaseId)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
        try container.encodeIfPresent(transactionHash, forKey: .transactionHash)
        try container.encodeIfPresent(asset, forKey: .asset)
        try container.encodeIfPresent(assetQuantity, forKey: .assetQuantity)
        try container.encodeIfPresent(fiatAmount, forKey: .fiatAmount)
        try container.encodeIfPresent(fiatCurrency, forKey: .fiatCurrency)
        try container.encodeIfPresent(walletId, forKey: .walletId)
        try container.encodeIfPresent(destinationAddress, forKey: .destinationAddress)
        try container.encodeIfPresent(providerOrderId, forKey: .providerOrderId)
        try container.encodeIfPresent(providerTransactionId, forKey: .providerTransactionId)
        try container.encodeIfPresent(testMode, forKey: .testMode)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

/// Unsolicited on-ramp lifecycle event emitted by the Para JS bridge.
public enum ParaOnRampEvent: Sendable, Equatable {
    case launched(ParaOnRampEventPayload)
    case completed(ParaOnRampEventPayload)
}

/// Parsed query fields from an on-ramp portal return deep link.
public struct ParaOnRampPortalCallback: Sendable, Equatable {
    public let status: ParaOnRampPurchaseStatus?
    public let rawStatus: String?
    public let purchaseId: String?
    public let error: String?

    public init(
        status: ParaOnRampPurchaseStatus? = nil,
        rawStatus: String? = nil,
        purchaseId: String? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.rawStatus = rawStatus
        self.purchaseId = purchaseId
        self.error = error
    }
}
