//
//  CosmosTransaction.swift
//  ParaSwift
//
//  Created by Para AI on 1/30/25.
//

import Foundation

/// Errors specific to CosmosTransaction
public enum CosmosTransactionError: Error, LocalizedError {
    case invalidAddress(String)
    case invalidAmount(String)
    case invalidDenom(String)
    case invalidPrefix(String)
    case encodingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let message):
            return message
        case .invalidAmount(let message):
            return message
        case .invalidDenom(let message):
            return message
        case .invalidPrefix(let message):
            return message
        case .encodingFailed(let message):
            return message
        }
    }
}

/// Represents a coin amount in Cosmos
public struct CosmosCoin: Codable {
    public let denom: String
    public let amount: String
    
    public init(denom: String, amount: String) throws {
        guard !denom.isEmpty else {
            throw CosmosTransactionError.invalidDenom("Denom cannot be empty")
        }
        guard !amount.isEmpty, UInt64(amount) != nil else {
            throw CosmosTransactionError.invalidAmount("Amount must be a valid positive number")
        }
        
        self.denom = denom
        self.amount = amount
    }
    
    /// Convenience initializer for creating a coin with numeric amount
    public init(denom: String, amount: UInt64) throws {
        try self.init(denom: denom, amount: String(amount))
    }
}

/// Represents transaction fees in Cosmos
public struct CosmosFee: Codable {
    public let amount: [CosmosCoin]
    public let gas: String
    
    public init(amount: [CosmosCoin], gas: String) throws {
        guard !gas.isEmpty, UInt64(gas) != nil else {
            throw CosmosTransactionError.invalidAmount("Gas must be a valid positive number")
        }
        
        self.amount = amount
        self.gas = gas
    }
    
    /// Convenience initializer for simple fee
    public init(denom: String, amount: String, gas: String) throws {
        let coin = try CosmosCoin(denom: denom, amount: amount)
        try self.init(amount: [coin], gas: gas)
    }
}

/// Represents a Cosmos message
public struct CosmosMessage {
    public let typeUrl: String
    public let value: [String: Any]
    
    public init(typeUrl: String, value: [String: Any]) {
        self.typeUrl = typeUrl
        self.value = value
    }
}

extension CosmosMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case typeUrl
        case value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        typeUrl = try container.decode(String.self, forKey: .typeUrl)
        
        // Decode value as JSON data and convert to [String: Any]
        let valueData = try container.decode(Data.self, forKey: .value)
        value = try JSONSerialization.jsonObject(with: valueData, options: []) as? [String: Any] ?? [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeUrl, forKey: .typeUrl)
        
        // Convert [String: Any] to JSON data for encoding
        let valueData = try JSONSerialization.data(withJSONObject: value, options: [])
        try container.encode(valueData, forKey: .value)
    }
}

extension CosmosMessage {
    /// Create a MsgSend message
    public static func send(
        fromAddress: String,
        toAddress: String,
        amount: [CosmosCoin]
    ) throws -> CosmosMessage {
        // Basic validation
        guard CosmosTransaction.isValidBech32Address(fromAddress) else {
            throw CosmosTransactionError.invalidAddress("Invalid from address: \(fromAddress)")
        }
        guard CosmosTransaction.isValidBech32Address(toAddress) else {
            throw CosmosTransactionError.invalidAddress("Invalid to address: \(toAddress)")
        }
        
        let value: [String: Any] = [
            "from_address": fromAddress,
            "to_address": toAddress,
            "amount": amount.map { ["denom": $0.denom, "amount": $0.amount] }
        ]
        
        return CosmosMessage(typeUrl: "/cosmos.bank.v1beta1.MsgSend", value: value)
    }
}


/// Signing method for Cosmos transactions
public enum CosmosSigningMethod: String, Codable {
    case amino = "amino"    // Standard signing method (default)
    case proto = "proto"    // Modern Proto/Direct signing (for future use)
}

/// A struct representing a Cosmos transaction
/// 
/// This abstraction provides a clean interface for creating Cosmos transactions
/// without requiring direct CosmJS knowledge in application code.
/// The ParaCosmosSigner converts this to proper CosmJS format internally.
/// 
/// **Current Support:**
/// - Token transfers (MsgSend) with proper validation
/// - Fee specification
/// - Memo support
/// - Both Proto and Amino signing methods
/// 
/// **Limitations:**
/// - Currently supports basic transfers and common operations
/// - For complex operations, extend this struct or use CosmJS directly in the bridge
public struct CosmosTransaction: Codable {
    /// The transaction messages
    public let messages: [CosmosMessage]
    /// Transaction fee
    public let fee: CosmosFee
    /// Optional memo
    public let memo: String?
    /// Preferred signing method (defaults to amino)
    public let signingMethod: CosmosSigningMethod
    
    /// Creates a new Cosmos transaction
    /// - Parameters:
    ///   - messages: Array of transaction messages
    ///   - fee: Transaction fee
    ///   - memo: Optional memo text
    ///   - signingMethod: Signing method (defaults to amino)
    public init(
        messages: [CosmosMessage],
        fee: CosmosFee,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) throws {
        guard !messages.isEmpty else {
            throw CosmosTransactionError.invalidAmount("Transaction must have at least one message")
        }
        
        self.messages = messages
        self.fee = fee
        self.memo = memo
        self.signingMethod = signingMethod
    }
    
    /// Convenience initializer for token transfer
    /// - Parameters:
    ///   - fromAddress: Sender address
    ///   - toAddress: Recipient address
    ///   - amount: Amount to send
    ///   - denom: Token denomination (e.g., "uatom")
    ///   - feeDenom: Fee denomination (defaults to same as amount denom)
    ///   - feeAmount: Fee amount (default: "5000")
    ///   - gas: Gas limit (default: "200000")
    ///   - memo: Optional memo
    ///   - signingMethod: Signing method (defaults to amino)
    public static func transfer(
        fromAddress: String,
        toAddress: String,
        amount: String,
        denom: String,
        feeDenom: String? = nil,
        feeAmount: String = "5000",
        gas: String = "200000",
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) throws -> CosmosTransaction {
        let coin = try CosmosCoin(denom: denom, amount: amount)
        let message = try CosmosMessage.send(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: [coin]
        )
        
        let fee = try CosmosFee(
            denom: feeDenom ?? denom,
            amount: feeAmount,
            gas: gas
        )
        
        return try CosmosTransaction(
            messages: [message],
            fee: fee,
            memo: memo,
            signingMethod: signingMethod
        )
    }
    
    /// Basic Bech32 address validation
    /// Validates format: hrp + separator + data (32-90 chars total)
    internal static func isValidBech32Address(_ address: String) -> Bool {
        let parts = address.components(separatedBy: "1")
        guard parts.count == 2 else { return false }
        
        let hrp = parts[0]
        let data = parts[1]
        
        // Basic validation: reasonable length and charset
        guard hrp.count >= 1 && hrp.count <= 10,
              data.count >= 6 && data.count <= 87,
              address.count >= 8 && address.count <= 90 else {
            return false
        }
        
        // Bech32 charset validation (simplified)
        let bech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        return data.lowercased().allSatisfy { bech32Charset.contains($0) }
    }
}

/// Response structure for Cosmos signing operations
public struct CosmosSignResponse {
    public let signature: CosmosSignature
    public let signedDoc: [String: Any]
    
    public init(signature: CosmosSignature, signedDoc: [String: Any]) {
        self.signature = signature
        self.signedDoc = signedDoc
    }
}

extension CosmosSignResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case signature
        case signedDoc
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signature = try container.decode(CosmosSignature.self, forKey: .signature)
        
        // Decode signedDoc as JSON data and convert to [String: Any]
        let signedDocData = try container.decode(Data.self, forKey: .signedDoc)
        signedDoc = try JSONSerialization.jsonObject(with: signedDocData, options: []) as? [String: Any] ?? [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signature, forKey: .signature)
        
        // Convert [String: Any] to JSON data for encoding
        let signedDocData = try JSONSerialization.data(withJSONObject: signedDoc, options: [])
        try container.encode(signedDocData, forKey: .signedDoc)
    }
}

/// Cosmos signature structure
public struct CosmosSignature: Codable {
    public let pubKey: CosmosPubKey?
    public let signature: String
    
    public init(pubKey: CosmosPubKey?, signature: String) {
        self.pubKey = pubKey
        self.signature = signature
    }
}

/// Cosmos public key structure
public struct CosmosPubKey: Codable {
    public let type: String
    public let value: String
    
    public init(type: String, value: String) {
        self.type = type
        self.value = value
    }
}