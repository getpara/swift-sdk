//
//  ParaManager+Solana.swift
//  ParaSwift
//
//  Solana-specific extensions for ParaManager
//

import Foundation

// Helper struct for pre-serialized transactions
private struct PreSerializedTransaction: Encodable {
    let type = "serialized"
    let data: String
}

public extension ParaManager {
    /// Sign a pre-serialized Solana transaction (for backward compatibility)
    /// 
    /// This method supports customers who have pre-serialized base64 Solana transactions
    /// that they need to sign. It uses the unified signTransaction API with a special
    /// format that the bridge recognizes.
    /// 
    /// - Parameters:
    ///   - walletId: The ID of the Solana wallet to use for signing
    ///   - base64Tx: The base64-encoded serialized transaction
    /// - Returns: A SignatureResult containing the signature
    /// - Throws: ParaWebViewError if signing fails
    func signSolanaSerializedTransaction(
        walletId: String,
        base64Tx: String
    ) async throws -> SignatureResult {
        let transaction = PreSerializedTransaction(data: base64Tx)
        
        return try await signTransaction(
            walletId: walletId,
            transaction: transaction
        )
    }
}