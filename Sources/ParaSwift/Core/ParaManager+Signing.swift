import Foundation

// MARK: - Signing Operations

/// Result of a signing operation
public struct SignatureResult {
    /// The signature string
    public let signature: String
    /// The wallet ID that signed
    public let walletId: String
    /// The wallet type (e.g., "evm", "solana", "cosmos")
    public let type: String
    
    public init(signature: String, walletId: String, type: String) {
        self.signature = signature
        self.walletId = walletId
        self.type = type
    }
}

// Helper structs for formatting methods
struct FormatAndSignMessageParams: Encodable {
    let walletId: String
    let message: String
}

struct FormatAndSignTransactionParams: Encodable {
    let walletId: String
    let transaction: [String: Any]
    let chainId: String?
    let rpcUrl: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(walletId, forKey: .walletId)
        try container.encode(JSONValue(transaction), forKey: .transaction)
        try container.encodeIfPresent(chainId, forKey: .chainId)
        try container.encodeIfPresent(rpcUrl, forKey: .rpcUrl)
    }

    enum CodingKeys: String, CodingKey {
        case walletId, transaction, chainId, rpcUrl
    }
}

public extension ParaManager {
    /// Signs a message with any wallet type.
    ///
    /// This unified method works with all wallet types (EVM, Solana, Cosmos, etc.).
    /// The bridge handles the chain-specific signing logic internally.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - message: The message to sign (plain text).
    /// - Returns: A SignatureResult containing the signature and metadata.
    func signMessage(walletId: String, message: String) async throws -> SignatureResult {
        try await withErrorTracking(
            methodName: "formatAndSignMessage",
            userId: getCurrentUserId(),
            operation: {
                try await ensureWebViewReady()

                let params = FormatAndSignMessageParams(
                    walletId: walletId,
                    message: message
                )

                let result = try await postMessage(method: "formatAndSignMessage", payload: params)
                
                // Parse the response from bridge
                let dict = try decodeResult(result, expectedType: [String: Any].self, method: "formatAndSignMessage")
                
                let signature = dict["signature"] as? String ?? ""
                let returnedWalletId = dict["walletId"] as? String ?? walletId
                let walletType = dict["type"] as? String ?? "unknown"
                
                return SignatureResult(
                    signature: signature,
                    walletId: returnedWalletId,
                    type: walletType
                )
            }
        )
    }

    /// Signs a transaction with any wallet type.
    ///
    /// This unified method works with all wallet types. It accepts transaction parameters
    /// as an Encodable object that will be formatted by the bridge based on wallet type.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - transaction: The transaction parameters (EVMTransaction, SolanaTransaction, etc.).
    ///   - chainId: Optional chain ID (primarily for EVM chains).
    /// - Parameters:
    ///   - rpcUrl: Optional RPC URL (required for Solana if recentBlockhash is not provided).
    /// - Returns: A SignatureResult containing the signature and metadata.
    func signTransaction<T: Encodable>(
        walletId: String,
        transaction: T,
        chainId: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> SignatureResult {
        try await withErrorTracking(
            methodName: "formatAndSignTransaction",
            userId: getCurrentUserId(),
            operation: {
                try await ensureWebViewReady()

                // Encode the transaction object to JSON
                let encoder = JSONEncoder()
                let transactionData = try encoder.encode(transaction)
                let transactionDict = try JSONSerialization.jsonObject(with: transactionData, options: []) as? [String: Any] ?? [:]
                
                let params = FormatAndSignTransactionParams(
                    walletId: walletId,
                    transaction: transactionDict,
                    chainId: chainId,
                    rpcUrl: rpcUrl
                )

                let result = try await postMessage(method: "formatAndSignTransaction", payload: params)
                
                // Parse the response from bridge
                let dict = try decodeResult(result, expectedType: [String: Any].self, method: "formatAndSignTransaction")
                
                let signature = dict["signature"] as? String ?? ""
                let returnedWalletId = dict["walletId"] as? String ?? walletId
                let walletType = dict["type"] as? String ?? "unknown"
                
                return SignatureResult(
                    signature: signature,
                    walletId: returnedWalletId,
                    type: walletType
                )
            }
        )
    }
    
    /// Gets the balance for any wallet type.
    ///
    /// This unified method works with all wallet types. For token balances,
    /// provide the token contract address or symbol.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet.
    ///   - token: Optional token identifier (contract address for EVM, mint address for Solana, etc.).
    ///   - rpcUrl: Optional RPC URL (recommended for Solana and Cosmos to avoid 403/CORS issues).
    ///   - chainPrefix: Optional bech32 prefix for Cosmos (e.g., "juno", "stars").
    ///   - denom: Optional denom for Cosmos balances (e.g., "ujuno", "ustars").
    /// - Returns: The balance as a string (format depends on the chain).
    func getBalance(walletId: String, token: String? = nil, rpcUrl: String? = nil, chainPrefix: String? = nil, denom: String? = nil) async throws -> String {
        try await withErrorTracking(
            methodName: "getBalance",
            userId: getCurrentUserId(),
            operation: {
                try await ensureWebViewReady()

                struct GetBalanceParams: Encodable {
                    let walletId: String
                    let token: String?
                    let rpcUrl: String?
                    let chainPrefix: String?
                    let denom: String?
                }

                let params = GetBalanceParams(
                    walletId: walletId,
                    token: token,
                    rpcUrl: rpcUrl,
                    chainPrefix: chainPrefix,
                    denom: denom
                )

                let result = try await postMessage(method: "getBalance", payload: params)
                return try decodeResult(result, expectedType: String.self, method: "getBalance")
            }
        )
    }
    
    /// High-level transfer method for any wallet type.
    ///
    /// This convenience method handles token transfers across all supported chains.
    /// The bridge handles the chain-specific transaction construction internally.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to transfer from.
    ///   - to: The recipient address.
    ///   - amount: The amount to transfer (as a string to handle large numbers).
    ///   - token: Optional token identifier (contract address for EVM, mint address for Solana, etc.).
    /// - Returns: The transaction hash.
    func transfer(
        walletId: String,
        to: String,
        amount: String,
        token: String? = nil
    ) async throws -> String {
        try await withErrorTracking(
            methodName: "transfer",
            userId: getCurrentUserId(),
            operation: {
                try await ensureWebViewReady()

                struct TransferParams: Encodable {
                    let walletId: String
                    let to: String
                    let amount: String
                    let token: String?
                }

                let params = TransferParams(
                    walletId: walletId,
                    to: to,
                    amount: amount,
                    token: token
                )

                let result = try await postMessage(method: "transfer", payload: params)
                return try decodeResult(result, expectedType: String.self, method: "transfer")
            }
        )
    }
}
