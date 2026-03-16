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
    /// Sets a global handler for transaction review URLs. When a signing operation
    /// requires user approval (due to permissions policies), the SDK calls this
    /// handler with the review URL before throwing ``ParaError/transactionDenied``.
    ///
    /// ```swift
    /// paraManager.setTransactionReviewHandler { url in
    ///     UIApplication.shared.open(URL(string: url)!)
    /// }
    /// ```
    func setTransactionReviewHandler(_ handler: @escaping (String) -> Void) {
        transactionReviewHandler = handler
    }

    /// Signs a message with any wallet type.
    ///
    /// - Throws: ``ParaError/transactionDenied`` if a permissions policy requires approval.
    func signMessage(walletId: String, message: String) async throws -> SignatureResult {
        try await ensureWebViewReady()

        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            logger.warning("Failed to load transmission keyshares before signing message: \(error.localizedDescription)")
        }

        let params = FormatAndSignMessageParams(walletId: walletId, message: message)
        let result = try await postMessage(method: "formatAndSignMessage", payload: params)
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: "formatAndSignMessage")

        try checkForTransactionDenial(dict)

        guard let signature = dict["signature"] as? String else {
            throw ParaError.bridgeError("Missing signature in response")
        }

        return SignatureResult(
            signedTransaction: signature,
            walletId: dict["walletId"] as? String ?? walletId,
            type: dict["type"] as? String ?? "unknown"
        )
    }

    /// Signs a transaction with any wallet type.
    ///
    /// - Throws: ``ParaError/transactionDenied`` if a permissions policy requires approval.
    func signTransaction<T: Encodable>(
        walletId: String,
        transaction: T,
        chainId: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> SignatureResult {
        try await ensureWebViewReady()

        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            logger.warning("Failed to load transmission keyshares before signing transaction: \(error.localizedDescription)")
        }

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
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: "formatAndSignTransaction")

        try checkForTransactionDenial(dict)

        let signedTransaction: String
        if let tx = dict["signedTransaction"] as? String {
            signedTransaction = tx
        } else if let sig = dict["signature"] as? String {
            signedTransaction = sig
        } else {
            throw ParaError.bridgeError("Missing signedTransaction or signature in response")
        }

        return SignatureResult(
            signedTransaction: signedTransaction,
            walletId: dict["walletId"] as? String ?? walletId,
            type: dict["type"] as? String ?? "unknown"
        )
    }

    /// Gets the balance for any wallet type.
    func getBalance(walletId: String, token: String? = nil, rpcUrl: String? = nil, chainPrefix: String? = nil, denom: String? = nil) async throws -> String {
        try await ensureWebViewReady()

        struct GetBalanceParams: Encodable {
            let walletId: String
            let token: String?
            let rpcUrl: String?
            let chainPrefix: String?
            let denom: String?
        }

        let params = GetBalanceParams(walletId: walletId, token: token, rpcUrl: rpcUrl, chainPrefix: chainPrefix, denom: denom)
        let result = try await postMessage(method: "getBalance", payload: params)
        return try decodeResult(result, expectedType: String.self, method: "getBalance")
    }

    /// High-level transfer method for EVM chains.
    func transfer(
        walletId: String,
        to: String,
        amount: String,
        chainId: String? = nil,
        rpcUrl: String? = nil
    ) async throws -> TransferResult {
        try await ensureWebViewReady()

        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            logger.warning("Failed to load transmission keyshares before transfer: \(error.localizedDescription)")
        }

        struct TransferParams: Encodable {
            let walletId: String
            let toAddress: String
            let amount: String
            let chainId: String?
            let rpcUrl: String?
        }

        let params = TransferParams(walletId: walletId, toAddress: to, amount: amount, chainId: chainId, rpcUrl: rpcUrl)
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

    // MARK: - Private

    /// Checks a bridge response for pendingTransactionId (permissions denial).
    /// Calls the transaction review handler if set, then throws.
    private func checkForTransactionDenial(_ dict: [String: Any]) throws {
        guard let pendingTransactionId = dict["pendingTransactionId"] as? String else { return }
        let reviewUrl = dict["transactionReviewUrl"] as? String
        if let reviewUrl { transactionReviewHandler?(reviewUrl) }
        throw ParaError.transactionDenied(pendingTransactionId: pendingTransactionId, transactionReviewUrl: reviewUrl)
    }
}
