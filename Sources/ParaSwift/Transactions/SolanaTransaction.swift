//
//  SolanaTransaction.swift
//  ParaSwift
//
//  Created by Para AI on 1/27/25.
//

import Foundation

/// Errors specific to SolanaTransaction
public enum SolanaTransactionError: Error, LocalizedError {
    case invalidAddress(String)
    case invalidAmount(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidAddress(message):
            message
        case let .invalidAmount(message):
            message
        }
    }
}

/// A struct representing a Solana transaction
///
/// This abstraction provides a clean interface for creating Solana transactions
/// without requiring direct SolanaSwift knowledge in application code.
/// The bridge handles the conversion to proper Solana transaction format internally.
///
/// **Current Support:**
/// - SOL transfers with proper validation
/// - Fee payer specification
/// - Recent blockhash handling
/// - Compute unit configuration
///
/// **Limitations:**
/// - Currently only supports simple SOL transfers
/// - For complex instructions/programs, extend this struct or use SolanaSwift directly in the SDK
public struct SolanaTransaction: Codable {
    /// The recipient address
    public let to: String
    /// The amount in lamports
    public let lamports: UInt64
    /// The fee payer address (optional, defaults to sender)
    public let feePayer: String?
    /// Recent blockhash (optional, will be fetched if not provided)
    public let recentBlockhash: String?
    /// Compute unit limit (optional)
    public let computeUnitLimit: UInt32?
    /// Compute unit price in micro-lamports (optional)
    public let computeUnitPrice: UInt64?
    /// Optional memo instruction
    public let memo: String?
    /// Transaction type - currently only supports "transfer"
    public let type: String

    /// Creates a new Solana transfer transaction
    /// - Parameters:
    ///   - to: Recipient address
    ///   - lamports: Amount in lamports (1 SOL = 1,000,000,000 lamports)
    ///   - feePayer: Fee payer address (optional)
    ///   - recentBlockhash: Recent blockhash (optional)
    ///   - computeUnitLimit: Compute unit limit (optional)
    ///   - computeUnitPrice: Compute unit price in micro-lamports (optional)
    public init(
        to: String,
        lamports: UInt64,
        feePayer: String? = nil,
        recentBlockhash: String? = nil,
        computeUnitLimit: UInt32? = nil,
        computeUnitPrice: UInt64? = nil,
        memo: String? = nil
    ) throws {
        // Basic Solana address validation
        guard SolanaTransaction.isValidAddress(to) else {
            throw SolanaTransactionError.invalidAddress("Invalid recipient address: \(to)")
        }

        if let feePayer {
            guard SolanaTransaction.isValidAddress(feePayer) else {
                throw SolanaTransactionError.invalidAddress("Invalid fee payer address: \(feePayer)")
            }
        }

        guard lamports > 0 else {
            throw SolanaTransactionError.invalidAmount("Amount must be greater than 0")
        }

        self.to = to
        self.lamports = lamports
        self.feePayer = feePayer
        self.recentBlockhash = recentBlockhash
        self.computeUnitLimit = computeUnitLimit
        self.computeUnitPrice = computeUnitPrice
        self.memo = memo
        type = "transfer"
    }

    /// Basic Solana address validation (Base58, 32-44 characters)
    private static func isValidAddress(_ address: String) -> Bool {
        let base58Charset = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return address.count >= 32 &&
            address.count <= 44 &&
            address.allSatisfy { base58Charset.contains($0) }
    }

    /// Convenience initializer for SOL transfers
    /// - Parameters:
    ///   - to: Recipient address
    ///   - sol: Amount in SOL (will be converted to lamports)
    public init(to: String, sol: Double) throws {
        try self.init(to: to, lamports: UInt64(sol * 1_000_000_000))
    }

    private enum CodingKeys: String, CodingKey {
        case to, lamports, feePayer, recentBlockhash, computeUnitLimit, computeUnitPrice, memo, type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        to = try container.decode(String.self, forKey: .to)
        lamports = try Self.decodeUInt64(from: container, forKey: .lamports)
        feePayer = try container.decodeIfPresent(String.self, forKey: .feePayer)
        recentBlockhash = try container.decodeIfPresent(String.self, forKey: .recentBlockhash)
        computeUnitLimit = try container.decodeIfPresent(UInt32.self, forKey: .computeUnitLimit)
        computeUnitPrice = try Self.decodeUInt64IfPresent(from: container, forKey: .computeUnitPrice)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        type = try container.decode(String.self, forKey: .type)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(to, forKey: .to)
        try container.encode(String(lamports), forKey: .lamports)
        try container.encodeIfPresent(feePayer, forKey: .feePayer)
        try container.encodeIfPresent(recentBlockhash, forKey: .recentBlockhash)
        try container.encodeIfPresent(computeUnitLimit, forKey: .computeUnitLimit)
        try container.encodeIfPresent(computeUnitPrice.map(String.init), forKey: .computeUnitPrice)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encode(type, forKey: .type)
    }

    private static func decodeUInt64(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
    ) throws -> UInt64 {
        if let string = try? container.decode(String.self, forKey: key), let value = UInt64(string) {
            return value
        }
        return try container.decode(UInt64.self, forKey: key)
    }

    private static func decodeUInt64IfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
    ) throws -> UInt64? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decodeUInt64(from: container, forKey: key)
    }
}
