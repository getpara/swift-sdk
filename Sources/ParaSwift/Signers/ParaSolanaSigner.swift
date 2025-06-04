//
//  ParaSolanaSigner.swift
//  ParaSwift
//
//  Created by Para AI on 1/27/25.
//

import Foundation
import SolanaSwift

/// Errors specific to ParaSolanaSigner operations
public enum ParaSolanaSignerError: Error, LocalizedError {
    /// Invalid wallet type - expected Solana wallet
    case invalidWalletType
    /// Wallet ID is missing
    case missingWalletId
    /// Wallet address is missing or invalid
    case invalidWalletAddress
    /// Signing operation failed
    case signingFailed(underlyingError: Error?)
    /// Network operation failed
    case networkError(underlyingError: Error?)
    /// Invalid signature format
    case invalidSignature
    /// Transaction compilation failed
    case transactionCompilationFailed(underlyingError: Error?)
    /// Bridge operation failed
    case bridgeError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWalletType:
            "Invalid wallet type - expected Solana wallet"
        case .missingWalletId:
            "Wallet ID is missing"
        case .invalidWalletAddress:
            "Wallet address is missing or invalid"
        case let .signingFailed(error):
            "Signing operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .networkError(error):
            "Network operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case .invalidSignature:
            "Invalid signature format"
        case let .transactionCompilationFailed(error):
            "Transaction compilation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .bridgeError(message):
            "Bridge operation failed: \(message)"
        }
    }
}

/// A signer for Solana blockchain operations using Para's secure key management via bridge
@MainActor
public class ParaSolanaSigner: ObservableObject {
    private let paraManager: ParaManager
    private let rpcUrl: String
    private var walletId: String?

    /// Initialize a new ParaSolanaSigner
    /// - Parameters:
    ///   - paraManager: The ParaManager instance for bridge operations
    ///   - rpcUrl: The Solana RPC endpoint URL
    ///   - walletId: Optional specific wallet ID to use
    public init(paraManager: ParaManager, rpcUrl: String, walletId: String? = nil) throws {
        self.paraManager = paraManager
        self.rpcUrl = rpcUrl

        if let walletId {
            Task {
                try await selectWallet(walletId: walletId)
            }
        }
    }

    /// Initialize the Solana signer in the bridge with a specific wallet
    private func initSolanaSigner(rpcUrl: String, walletId: String) async throws {
        let args = SolanaSignerInitArgs(walletId: walletId, rpcUrl: rpcUrl)
        let _ = try await paraManager.postMessage(method: "initSolanaWeb3Signer", payload: args)
        self.walletId = walletId
    }

    /// Select a wallet for signing operations
    /// - Parameter walletId: The wallet ID to use
    public func selectWallet(walletId: String) async throws {
        try await initSolanaSigner(rpcUrl: rpcUrl, walletId: walletId)
    }

    /// Get the current wallet's public key
    /// - Returns: The Solana public key
    /// - Throws: ParaSolanaSignerError if wallet not initialized
    public func getPublicKey() async throws -> SolanaSwift.PublicKey {
        guard let walletId else {
            throw ParaSolanaSignerError.missingWalletId
        }

        // Fetch wallets to get the address
        let wallets = try await paraManager.fetchWallets()
        guard let wallet = wallets.first(where: { $0.id == walletId && $0.type == .solana }) else {
            throw ParaSolanaSignerError.invalidWalletType
        }

        guard let address = wallet.address else {
            throw ParaSolanaSignerError.invalidWalletAddress
        }

        return try SolanaSwift.PublicKey(string: address)
    }

    // MARK: - Public Methods

    /// Get the SOL balance for this wallet via bridge
    /// - Returns: Balance in lamports
    /// - Throws: ParaSolanaSignerError if network request fails
    public func getBalance() async throws -> UInt64 {
        guard walletId != nil else {
            throw ParaSolanaSignerError.missingWalletId
        }

        // Get the wallet address
        let publicKey = try await getPublicKey()
        let address = publicKey.base58EncodedString

        do {
            // Pass address to the bridge (not walletId)
            let args = ["address": address]
            let result = try await paraManager.postMessage(method: "solanaWeb3GetBalance", payload: args)

            // Bridge returns balance as string
            guard let balanceString = result as? String,
                  let balance = UInt64(balanceString)
            else {
                throw ParaSolanaSignerError.bridgeError("Invalid balance response from bridge")
            }
            return balance
        } catch let error as ParaWebViewError {
            // Check if the method is not implemented
            if error.localizedDescription.contains("not implemented") {
                throw ParaSolanaSignerError.bridgeError("Solana balance fetching is not yet supported in the bridge")
            }
            throw ParaSolanaSignerError.networkError(underlyingError: error)
        } catch {
            throw ParaSolanaSignerError.networkError(underlyingError: error)
        }
    }

    /// Sign arbitrary bytes (for demo/testing purposes)
    /// - Parameter data: The data to sign
    /// - Returns: The signature as Data
    /// - Throws: ParaSolanaSignerError if signing fails
    public func signBytes(_ data: Data) async throws -> Data {
        guard let walletId else {
            throw ParaSolanaSignerError.missingWalletId
        }

        // Use Para's signMessage method directly
        let messageBase64 = data.base64EncodedString()

        do {
            let signatureString = try await paraManager.signMessage(
                walletId: walletId,
                message: messageBase64,
            )

            // Decode the signature
            guard let signatureData = Data(base64Encoded: signatureString) else {
                throw ParaSolanaSignerError.invalidSignature
            }

            return signatureData
        } catch {
            throw ParaSolanaSignerError.signingFailed(underlyingError: error)
        }
    }

    /// Sign a Solana transaction using the bridge
    /// - Parameter transaction: The SolanaTransaction to sign
    /// - Returns: The base64 encoded signed transaction
    /// - Throws: ParaSolanaSignerError if signing fails
    public func signTransaction(_ transaction: SolanaTransaction) async throws -> String {
        guard walletId != nil else {
            throw ParaSolanaSignerError.missingWalletId
        }

        do {
            // Convert SolanaTransaction to actual SolanaSwift.Transaction
            var solanaTransaction = try await buildSolanaTransaction(from: transaction)

            // Serialize the transaction to bytes
            let serializedTx = try solanaTransaction.serialize()
            let b64EncodedTx = serializedTx.base64EncodedString()

            // Call bridge method to sign
            let args = SolanaSignTransactionArgs(b64EncodedTx: b64EncodedTx)

            do {
                let result = try await paraManager.postMessage(method: "solanaWeb3SignTransaction", payload: args)

                // Bridge returns base64 encoded signed transaction
                guard let signedTxBase64 = result as? String else {
                    throw ParaSolanaSignerError.bridgeError("Invalid response from bridge")
                }

                return signedTxBase64
            } catch let error as ParaWebViewError {
                if error.localizedDescription.contains("not implemented") {
                    throw ParaSolanaSignerError.bridgeError("Solana transaction signing is not yet supported in the bridge")
                }
                throw error
            }
        } catch let error as ParaSolanaSignerError {
            throw error
        } catch {
            throw ParaSolanaSignerError.transactionCompilationFailed(underlyingError: error)
        }
    }

    /// Send a transaction to the network using the bridge
    /// - Parameter transaction: The SolanaTransaction to send
    /// - Returns: The transaction signature
    /// - Throws: ParaSolanaSignerError if operation fails
    public func sendTransaction(_ transaction: SolanaTransaction) async throws -> String {
        guard walletId != nil else {
            throw ParaSolanaSignerError.missingWalletId
        }

        do {
            // Convert SolanaTransaction to actual SolanaSwift.Transaction
            var solanaTransaction = try await buildSolanaTransaction(from: transaction)

            // Serialize the transaction to bytes
            let serializedTx = try solanaTransaction.serialize()
            let b64EncodedTx = serializedTx.base64EncodedString()

            // Call bridge method to send (signs and sends in one operation)
            let args = SolanaSendTransactionArgs(b64EncodedTx: b64EncodedTx)

            do {
                let result = try await paraManager.postMessage(method: "solanaWeb3SendTransaction", payload: args)

                // Bridge returns transaction signature
                guard let signature = result as? String else {
                    throw ParaSolanaSignerError.bridgeError("Invalid response from bridge")
                }

                return signature
            } catch let error as ParaWebViewError {
                if error.localizedDescription.contains("not implemented") {
                    throw ParaSolanaSignerError.bridgeError("Solana transaction sending is not yet supported in the bridge")
                }
                throw error
            }
        } catch let error as ParaSolanaSignerError {
            throw error
        } catch {
            throw ParaSolanaSignerError.networkError(underlyingError: error)
        }
    }

    /// Converts a SolanaTransaction abstraction to a proper SolanaSwift.Transaction
    /// - Parameter transaction: The SolanaTransaction to convert
    /// - Returns: A properly constructed SolanaSwift.Transaction
    /// - Throws: ParaSolanaSignerError if conversion fails
    private func buildSolanaTransaction(from transaction: SolanaTransaction) async throws -> SolanaSwift.Transaction {
        do {
            // Get the public key for fee payer
            let publicKey = try await getPublicKey()

            // Create recipient public key
            let recipientKey = try SolanaSwift.PublicKey(string: transaction.to)

            // Create transfer instruction
            let instruction = SystemProgram.transferInstruction(
                from: publicKey,
                to: recipientKey,
                lamports: transaction.lamports,
            )

            // Create transaction with instructions
            var solanaTransaction = SolanaSwift.Transaction(instructions: [instruction])

            // Set fee payer
            if let feePayerAddress = transaction.feePayer {
                solanaTransaction.feePayer = try SolanaSwift.PublicKey(string: feePayerAddress)
            } else {
                solanaTransaction.feePayer = publicKey
            }

            // Set recent blockhash if provided, otherwise fetch it via bridge
            if let blockhash = transaction.recentBlockhash {
                solanaTransaction.recentBlockhash = blockhash
            } else {
                do {
                    // Bridge doesn't expect any parameters for getRecentBlockhash
                    let result = try await paraManager.postMessage(method: "solanaWeb3GetRecentBlockhash", payload: [String: String]())

                    // Bridge returns an object with blockhash and lastValidBlockHeight
                    guard let blockhashResult = result as? [String: Any],
                          let blockhash = blockhashResult["blockhash"] as? String
                    else {
                        throw ParaSolanaSignerError.bridgeError("Invalid blockhash response from bridge")
                    }
                    solanaTransaction.recentBlockhash = blockhash
                } catch let error as ParaWebViewError {
                    if error.localizedDescription.contains("not implemented") {
                        throw ParaSolanaSignerError.bridgeError("Solana blockhash fetching is not yet supported in the bridge")
                    }
                    throw error
                }
            }

            return solanaTransaction
        } catch {
            throw ParaSolanaSignerError.transactionCompilationFailed(underlyingError: error)
        }
    }
}
