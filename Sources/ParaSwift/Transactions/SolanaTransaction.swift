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
        computeUnitPrice: UInt64? = nil
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

}
