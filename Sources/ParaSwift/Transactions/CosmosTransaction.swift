//
//  CosmosTransaction.swift
//  ParaSwift
//
//  Transaction parameters for Cosmos blockchain operations
//

import Foundation

/// Represents transaction parameters for Cosmos blockchain operations
///
/// This struct encapsulates all the necessary information for creating
/// and signing Cosmos transactions through the Para bridge.
public struct CosmosTransaction: Codable {
    /// The recipient address (bech32 format, e.g., "cosmos1...")
    public let to: String
    
    /// The amount to send (in smallest denomination, e.g., "1000000" for 1 ATOM)
    public let amount: String
    
    /// The denomination of the token (e.g., "uatom", "uosmo")
    public let denom: String?
    
    /// Optional memo for the transaction
    public let memo: String?
    
    /// Gas limit for the transaction (defaults to "200000")
    public let gasLimit: String?
    
    /// Gas price/fee amount (defaults to "5000")
    public let gasPrice: String?
    
    /// Transaction sequence number (defaults to 0)
    public let sequence: Int?
    
    /// Account number (defaults to 0)
    public let accountNumber: Int?
    
    /// Chain ID (e.g., "cosmoshub-4", "osmosis-1")
    public let chainId: String?
    
    /// Transaction format: "proto" (default) or "amino"
    public let format: String?
    
    /// Creates a new Cosmos transaction
    ///
    /// - Parameters:
    ///   - to: The recipient address in bech32 format
    ///   - amount: The amount to send in smallest denomination
    ///   - denom: The token denomination (defaults to "uatom")
    ///   - memo: Optional transaction memo
    ///   - gasLimit: Gas limit (defaults to "200000")
    ///   - gasPrice: Gas price/fee amount (defaults to "5000")
    ///   - sequence: Transaction sequence number
    ///   - accountNumber: Account number
    ///   - chainId: The chain ID
    ///   - format: Transaction format ("proto" or "amino", defaults to "proto")
    public init(
        to: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        gasLimit: String? = nil,
        gasPrice: String? = nil,
        sequence: Int? = nil,
        accountNumber: Int? = nil,
        chainId: String? = nil,
        format: String? = nil
    ) {
        self.to = to
        self.amount = amount
        self.denom = denom
        self.memo = memo
        self.gasLimit = gasLimit
        self.gasPrice = gasPrice
        self.sequence = sequence
        self.accountNumber = accountNumber
        self.chainId = chainId
        self.format = format
    }
    
    /// Creates a simple transfer transaction
    ///
    /// - Parameters:
    ///   - to: The recipient address
    ///   - amount: The amount to send
    ///   - denom: The token denomination (defaults to "uatom")
    ///   - chainId: The chain ID
    /// - Returns: A configured CosmosTransaction for a simple transfer
    public static func transfer(
        to: String,
        amount: String,
        denom: String = "uatom",
        chainId: String
    ) -> CosmosTransaction {
        return CosmosTransaction(
            to: to,
            amount: amount,
            denom: denom,
            chainId: chainId
        )
    }
}