import Foundation

public enum StellarNetwork {
    public static let publicPassphrase = "Public Global Stellar Network ; September 2015"
    public static let testnetPassphrase = "Test SDF Network ; September 2015"
}

public struct StellarAsset: Encodable {
    public let code: String
    public let issuer: String

    public init(code: String, issuer: String) {
        self.code = code
        self.issuer = issuer
    }
}

public struct StellarMemo: Encodable {
    public let type: String
    public let value: String

    public static func text(_ value: String) -> StellarMemo {
        StellarMemo(type: "text", value: value)
    }

    public static func id(_ value: String) -> StellarMemo {
        StellarMemo(type: "id", value: value)
    }

    public static func hash(_ value: String) -> StellarMemo {
        StellarMemo(type: "hash", value: value)
    }

    public static func returnHash(_ value: String) -> StellarMemo {
        StellarMemo(type: "return", value: value)
    }
}

public struct StellarTransaction: Encodable {
    public let to: String?
    public let amount: String?
    public let asset: StellarAsset?
    public let memo: StellarMemo?
    public let networkPassphrase: String?
    public let fee: String?
    public let timeout: Int?
    public let sequenceNumber: String?
    public let serializedXDR: String?

    public init(
        to: String,
        amount: String,
        asset: StellarAsset? = nil,
        memo: StellarMemo? = nil,
        networkPassphrase: String? = nil,
        fee: String? = nil,
        timeout: Int? = nil,
        sequenceNumber: String? = nil
    ) {
        self.to = to
        self.amount = amount
        self.asset = asset
        self.memo = memo
        self.networkPassphrase = networkPassphrase
        self.fee = fee
        self.timeout = timeout
        self.sequenceNumber = sequenceNumber
        serializedXDR = nil
    }

    public init(serializedXDR: String, networkPassphrase: String? = nil) {
        to = nil
        amount = nil
        asset = nil
        memo = nil
        self.networkPassphrase = networkPassphrase
        fee = nil
        timeout = nil
        sequenceNumber = nil
        self.serializedXDR = serializedXDR
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("STELLAR", forKey: .chainType)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(asset, forKey: .asset)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encodeIfPresent(networkPassphrase, forKey: .networkPassphrase)
        try container.encodeIfPresent(fee, forKey: .fee)
        try container.encodeIfPresent(timeout, forKey: .timeout)
        try container.encodeIfPresent(sequenceNumber, forKey: .sequenceNumber)

        if let serializedXDR {
            try container.encode("serialized", forKey: .type)
            try container.encode(serializedXDR, forKey: .data)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case chainType, to, amount, asset, memo, networkPassphrase, fee, timeout, sequenceNumber, type, data
    }
}
