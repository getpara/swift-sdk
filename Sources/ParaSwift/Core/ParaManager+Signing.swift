import Foundation

// MARK: - Signing Operations

/// Result of a signing operation
public struct SignatureResult {
    /// The signed transaction data (for EVM, complete RLP-encoded transaction; for others, the signature)
    public let signedTransaction: String
    /// The wallet ID that signed
    public let walletId: String
    /// The wallet type (e.g., "evm", "solana", "cosmos")
    public let type: String
    
    public init(signedTransaction: String, walletId: String, type: String) {
        self.signedTransaction = signedTransaction
        self.walletId = walletId
        self.type = type
    }
    
    /// Returns the transaction data for broadcasting.
    public var transactionData: String {
        return signedTransaction
    }
}

/// Result of a transfer operation
public struct TransferResult {
    /// The transaction hash
    public let hash: String
    /// The sender address
    public let from: String
    /// The recipient address
    public let to: String
    /// The amount transferred (in wei for EVM)
    public let amount: String
    /// The chain ID
    public let chainId: String
    
    public init(hash: String, from: String, to: String, amount: String, chainId: String) {
        self.hash = hash
        self.from = from
        self.to = to
        self.amount = amount
        self.chainId = chainId
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
        try await ensureWebViewReady()
        
        // Ensure transmission keyshares are loaded before signing
        // This is critical for wallet operations to work properly
        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            // Log the error but continue - some wallets may work without transmission keyshares
            logger.warning("Failed to load transmission keyshares before signing message: \(error.localizedDescription)")
        }

        let params = FormatAndSignMessageParams(
            walletId: walletId,
            message: message
        )

        let result = try await postMessage(method: "formatAndSignMessage", payload: params)
        
        // Parse the response from bridge
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: "formatAndSignMessage")
        
        // Bridge returns signedTransaction for all chains
        guard let signedTransaction = dict["signedTransaction"] as? String else {
            throw ParaError.bridgeError("Missing signedTransaction in response")
        }
        let returnedWalletId = dict["walletId"] as? String ?? walletId
        let walletType = dict["type"] as? String ?? "unknown"
        
        return SignatureResult(
            signedTransaction: signedTransaction,
            walletId: returnedWalletId,
            type: walletType
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
    ///   - rpcUrl: Optional RPC URL (required for Solana if recentBlockhash is not provided).
    /// - Returns: A SignatureResult containing the signature and metadata.
    /// - Note: This method automatically ensures transmission keyshares are loaded before signing.
    func signTransaction<T: Encodable>(
        walletId: String,
        transaction: T,
        chainId: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> SignatureResult {
        try await ensureWebViewReady()
        
        // Ensure transmission keyshares are loaded before signing
        // This is critical for wallet operations to work properly
        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            // Log the error but continue - some wallets may work without transmission keyshares
            logger.warning("Failed to load transmission keyshares before signing transaction: \(error.localizedDescription)")
        }

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
        
        // Bridge returns signedTransaction for all chains
        guard let signedTransaction = dict["signedTransaction"] as? String else {
            throw ParaError.bridgeError("Missing signedTransaction in response")
        }
        let returnedWalletId = dict["walletId"] as? String ?? walletId
        let walletType = dict["type"] as? String ?? "unknown"
        
        return SignatureResult(
            signedTransaction: signedTransaction,
            walletId: returnedWalletId,
            type: walletType
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
    
    /// High-level transfer method for EVM chains.
    ///
    /// This method handles ETH/ERC20 transfers on EVM-compatible chains.
    /// The bridge handles transaction construction, signing, and broadcasting.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the EVM wallet to transfer from.
    ///   - to: The recipient address.
    ///   - amount: The amount to transfer in wei (as a string to handle large numbers).
    ///   - chainId: Optional chain ID (auto-detected if not provided).
    ///   - rpcUrl: Optional RPC URL (defaults to Ethereum mainnet if not provided).
    /// - Returns: Transaction result containing hash and details.
    /// - Note: This method automatically ensures transmission keyshares are loaded before transferring.
    func transfer(
        walletId: String,
        to: String,
        amount: String,
        chainId: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> TransferResult {
        try await ensureWebViewReady()
        
        // Ensure transmission keyshares are loaded before transferring
        // This is critical for wallet operations to work properly
        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            // Log the error but continue - some wallets may work without transmission keyshares
            logger.warning("Failed to load transmission keyshares before transfer: \(error.localizedDescription)")
        }

        struct TransferParams: Encodable {
            let walletId: String
            let toAddress: String
            let amount: String
            let chainId: String?
            let rpcUrl: String?
        }

        let params = TransferParams(
            walletId: walletId,
            toAddress: to,
            amount: amount,
            chainId: chainId,
            rpcUrl: rpcUrl
        )

        let result = try await postMessage(method: "transfer", payload: params)
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: "transfer")
        
        return TransferResult(
            hash: dict["hash"] as? String ?? "",
            from: dict["from"] as? String ?? "",
            to: dict["to"] as? String ?? "",
            amount: dict["amount"] as? String ?? "",
            chainId: dict["chainId"] as? String ?? ""
        )
    }
}