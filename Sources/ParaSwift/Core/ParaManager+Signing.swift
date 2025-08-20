import os
import SwiftUI // Keep if @MainActor is used, otherwise Foundation

// MARK: - Signing Operations

public extension ParaManager {
    /// Signs a message with a wallet.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - message: The message to sign.
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation.
    /// - Returns: The signature as a string.
    func signMessage(walletId: String, message: String, timeoutMs: Int? = nil) async throws -> String {
        try await ensureWebViewReady()

        struct SignMessageParams: Encodable {
            let walletId: String
            let messageBase64: String
            let timeoutMs: Int?
        }

        let messageBase64 = message.toBase64()
        let params = SignMessageParams(
            walletId: walletId,
            messageBase64: messageBase64,
            timeoutMs: timeoutMs,
        )

        let result = try await postMessage(method: "signMessage", payload: params)
        return try decodeDictionaryResult(
            result,
            expectedType: String.self,
            method: "signMessage",
            key: "signature",
        )
    }

    /// Signs a transaction with a wallet.
    ///
    /// - Parameters:
    ///   - walletId: The ID of the wallet to use for signing.
    ///   - rlpEncodedTx: The RLP-encoded transaction.
    ///   - chainId: The chain ID.
    ///   - timeoutMs: Optional timeout in milliseconds for the signing operation.
    /// - Returns: The signature as a string.
    func signTransaction(
        walletId: String,
        rlpEncodedTx: String,
        chainId: String,
        timeoutMs: Int? = nil
    ) async throws -> String {
        try await ensureWebViewReady()

        struct SignTransactionParams: Encodable {
            let walletId: String
            let rlpEncodedTxBase64: String
            let chainId: String
            let timeoutMs: Int?
        }

        let params = SignTransactionParams(
            walletId: walletId,
            rlpEncodedTxBase64: rlpEncodedTx.toBase64(),
            chainId: chainId,
            timeoutMs: timeoutMs,
        )

        let result = try await postMessage(method: "signTransaction", payload: params)
        return try decodeDictionaryResult(
            result,
            expectedType: String.self,
            method: "signTransaction",
            key: "signature",
        )
    }
}
