import Foundation

/// Chain used to interpret and sign a bridge payload.
public enum BridgeChainType: String, Codable {
    case evm = "EVM"
    case solana = "SOLANA"
    case cosmos = "COSMOS"
    case stellar = "STELLAR"
    case sui = "SUI"
}

/// A JSON value used by EIP-712 domains and messages.
public enum BridgeJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case decimal(Double)
    case boolean(Bool)
    case null
    case array([BridgeJSONValue])
    case object([String: BridgeJSONValue])

    public subscript(key: String) -> BridgeJSONValue? {
        guard case let .object(dict) = self else { return nil }
        return dict[key]
    }

    init?(any value: Any) {
        if value is NSNull {
            self = .null
        } else if let bool = value as? Bool {
            self = .boolean(bool)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .boolean(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .decimal(number.doubleValue)
            } else {
                self = .integer(number.intValue)
            }
        } else if let string = value as? String {
            self = .string(string)
        } else if let array = value as? [Any] {
            self = .array(array.compactMap(BridgeJSONValue.init(any:)))
        } else if let dict = value as? [String: Any] {
            var converted: [String: BridgeJSONValue] = [:]
            for (key, item) in dict {
                if let jsonValue = BridgeJSONValue(any: item) {
                    converted[key] = jsonValue
                }
            }
            self = .object(converted)
        } else {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .decimal(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BridgeJSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: BridgeJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value):
            guard abs(Double(value)) <= 9_007_199_254_740_991 else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "EIP-712 integers must be within JavaScript safe integer range; use .string for large integer values",
                    ),
                )
            }
            try container.encode(value)
        case let .decimal(value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "EIP-712 numbers must be finite",
                    ),
                )
            }
            guard abs(value) <= 9_007_199_254_740_991 else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "EIP-712 numbers must be within JavaScript safe integer range; use .string for large integer values",
                    ),
                )
            }
            try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// Encodes arbitrary JSON payloads without EIP-712 safe-integer validation.
    func encodeUnvalidated(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .decimal(value):
            if value.isFinite {
                try container.encode(value)
            } else {
                try container.encode(String(describing: value))
            }
        case let .boolean(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case let .array(value):
            try container.encode(value.map(UnvalidatedBridgeJSONValue.init))
        case let .object(value):
            try container.encode(value.mapValues(UnvalidatedBridgeJSONValue.init))
        }
    }
}

struct UnvalidatedBridgeJSONValue: Encodable {
    let value: BridgeJSONValue

    func encode(to encoder: Encoder) throws {
        try value.encodeUnvalidated(to: encoder)
    }
}

/// A structured message accepted by the Para bridge.
public protocol BridgeMessagePayload: Encodable {
    var chainType: BridgeChainType { get }
}

/// Base64-encoded bytes for Solana or Stellar message signing.
public struct RawBridgeMessage: BridgeMessagePayload {
    public let chainType: BridgeChainType
    public let type = "raw"
    public let data: String
    public let encoding = "base64"

    private init(chainType: BridgeChainType, data: String) {
        self.chainType = chainType
        self.data = data
    }

    public static func solana(_ data: String) -> RawBridgeMessage {
        RawBridgeMessage(chainType: .solana, data: data)
    }

    public static func stellar(_ data: String) -> RawBridgeMessage {
        RawBridgeMessage(chainType: .stellar, data: data)
    }

    private enum CodingKeys: String, CodingKey {
        case type, data, encoding
    }
}

/// One field in an EIP-712 type definition.
public struct EVMTypedDataField: Codable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

/// An EIP-712 typed-data message.
public struct EVMTypedDataMessage: BridgeMessagePayload {
    public var chainType: BridgeChainType {
        .evm
    }

    public let type = "typedData"
    public let data: Data

    public struct Data: Codable {
        public let domain: [String: BridgeJSONValue]
        public let types: [String: [EVMTypedDataField]]
        public let primaryType: String
        public let message: [String: BridgeJSONValue]

        public init(
            domain: [String: BridgeJSONValue],
            types: [String: [EVMTypedDataField]],
            primaryType: String,
            message: [String: BridgeJSONValue],
        ) {
            self.domain = domain
            self.types = types
            self.primaryType = primaryType
            self.message = message
        }
    }

    public init(
        domain: [String: BridgeJSONValue],
        types: [String: [EVMTypedDataField]],
        primaryType: String,
        message: [String: BridgeJSONValue],
    ) {
        data = Data(domain: domain, types: types, primaryType: primaryType, message: message)
    }
}

/// An unsigned EIP-7702 authorization.
public struct EVMAuthorizationMessage: Encodable {
    public var chainType: BridgeChainType {
        .evm
    }

    public let type = "authorization"
    public let data: Data

    public struct Data: Codable {
        public let address: String
        public let chainId: Int
        public let nonce: Int

        public init(address: String, chainId: Int, nonce: Int) {
            self.address = address
            self.chainId = chainId
            self.nonce = nonce
        }
    }

    public init(address: String, chainId: Int, nonce: Int) {
        data = Data(address: address, chainId: chainId, nonce: nonce)
    }
}

/// A signed EIP-7702 authorization returned for provider-managed account flows.
public struct EVMSignedAuthorization: Codable {
    public let address: String
    public let chainId: Int
    public let nonce: Int
    public let yParity: Int
    public let r: String
    public let s: String

    public init(address: String, chainId: Int, nonce: Int, yParity: Int, r: String, s: String) {
        self.address = address
        self.chainId = chainId
        self.nonce = nonce
        self.yParity = yParity
        self.r = r
        self.s = s
    }
}

/// A base64-encoded Soroban authorization-entry preimage.
public struct StellarAuthEntryMessage: BridgeMessagePayload {
    public var chainType: BridgeChainType {
        .stellar
    }

    public let type = "authEntry"
    public let data: String

    public init(data: String) {
        self.data = data
    }
}

/// Base64-encoded bytes signed with Sui's personal-message intent.
public struct SuiPersonalMessage: BridgeMessagePayload {
    public var chainType: BridgeChainType {
        .sui
    }

    public let type = "suiPersonalMessage"
    public let data: String

    public init(data: String) {
        self.data = data
    }
}

/// A transaction payload with an explicit bridge chain interpretation.
public protocol BridgeTransactionPayload: Encodable {
    var chainType: BridgeChainType { get }
}

extension EVMTransaction: BridgeTransactionPayload {
    public var chainType: BridgeChainType {
        .evm
    }
}

extension SolanaTransaction: BridgeTransactionPayload {
    public var chainType: BridgeChainType {
        .solana
    }
}

extension CosmosTransaction: BridgeTransactionPayload {
    public var chainType: BridgeChainType {
        .cosmos
    }
}

extension StellarTransaction: BridgeTransactionPayload {
    public var chainType: BridgeChainType {
        .stellar
    }
}

/// Cosmos signing modes supported by the bridge.
public enum CosmosSignMode: String, Codable {
    case direct = "proto"
    case amino
}

/// A transaction already serialized by the chain's canonical SDK.
public struct SerializedTransaction: BridgeTransactionPayload {
    public let type = "serialized"
    public let chainType: BridgeChainType
    public let data: String
    public let format: CosmosSignMode?
    public let networkPassphrase: String?

    private init(
        chainType: BridgeChainType,
        data: String,
        format: CosmosSignMode? = nil,
        networkPassphrase: String? = nil,
    ) {
        self.chainType = chainType
        self.data = data
        self.format = format
        self.networkPassphrase = networkPassphrase
    }

    public static func solana(_ data: String) -> SerializedTransaction {
        SerializedTransaction(chainType: .solana, data: data)
    }

    public static func cosmos(_ data: String, signMode: CosmosSignMode) -> SerializedTransaction {
        SerializedTransaction(chainType: .cosmos, data: data, format: signMode)
    }

    public static func stellar(_ xdr: String, networkPassphrase: String? = nil)
        -> SerializedTransaction
    {
        SerializedTransaction(chainType: .stellar, data: xdr, networkPassphrase: networkPassphrase)
    }

    public static func sui(_ data: String) -> SerializedTransaction {
        SerializedTransaction(chainType: .sui, data: data)
    }
}

/// One address and its storage keys in an EIP-2930 access list.
public struct EVMAccessListEntry: Codable {
    public let address: String
    public let storageKeys: [String]

    public init(address: String, storageKeys: [String]) {
        self.address = address
        self.storageKeys = storageKeys
    }
}
