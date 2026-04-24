import Foundation

// MARK: - Smart Account (Account Abstraction) Operations

// Inline request payloads — local to the AA bridge module so `BridgeArguments.swift`
// remains focused on auth/wallet creation.

private struct CreateSmartAccountParams: Encodable {
    let provider: String
    let apiKey: String
    let chainId: Int
    let gasPolicyId: String?
    let mode: String
    let walletId: String?
    let address: String?
}

private struct SendSmartAccountTransactionParams: Encodable {
    let provider: String
    let smartAccountAddress: String
    let chainId: Int
    let to: String
    let value: String?
    let data: String?
}

private struct SendSmartAccountBatchTransactionParams: Encodable {
    let provider: String
    let smartAccountAddress: String
    let chainId: Int
    let calls: [SmartAccountCall]
}

public extension ParaManager {
    /// Creates (or materializes the counterfactual address of) a smart account backed by an
    /// Account Abstraction provider such as Alchemy.
    ///
    /// The returned ``SmartAccountInfo/smartAccountAddress`` is the address that should send
    /// transactions and hold funds — not the Para EOA.
    ///
    /// - Parameters:
    ///   - provider: AA provider identifier. Defaults to `"ALCHEMY"`.
    ///   - apiKey: Provider API key (e.g. your Alchemy app key).
    ///   - chainId: EVM chain ID to deploy the account on (e.g. `11155111` for Sepolia).
    ///   - gasPolicyId: Optional Alchemy gas manager policy ID used to sponsor gas.
    ///   - mode: `"4337"` (default) or `"7702"`.
    ///   - walletId: Optional Para wallet ID to use as the signer.
    ///   - address: Optional wallet address to use as the signer. Takes precedence over `walletId`
    ///     when both are supplied. If neither is provided, defaults to the active EVM wallet.
    /// - Returns: Metadata describing the smart account.
    func createSmartAccount(
        provider: String = "ALCHEMY",
        apiKey: String,
        chainId: Int,
        gasPolicyId: String? = nil,
        mode: String = "4337",
        walletId: String? = nil,
        address: String? = nil
    ) async throws -> SmartAccountInfo {
        try await ensureWebViewReady()
        try await ensureTransmissionKeysharesLoaded()

        let params = CreateSmartAccountParams(
            provider: provider,
            apiKey: apiKey,
            chainId: chainId,
            gasPolicyId: gasPolicyId,
            mode: mode,
            walletId: walletId,
            address: address
        )

        let result = try await postMessage(method: "createSmartAccount", payload: params)
        return try decodeSmartAccountInfo(result, method: "createSmartAccount")
    }

    /// Sends a single sponsored transaction through the smart account.
    ///
    /// - Parameters:
    ///   - smartAccountAddress: The address returned by ``createSmartAccount(provider:apiKey:chainId:gasPolicyId:mode:walletId:address:)``.
    ///   - chainId: EVM chain ID.
    ///   - to: Destination address.
    ///   - value: Amount in wei as a decimal string. Omit for zero-value calls.
    ///   - data: Optional hex-encoded calldata (including `0x` prefix).
    ///   - provider: AA provider identifier. Defaults to `"ALCHEMY"`.
    /// - Returns: A receipt once the UserOperation is mined.
    func sendSmartAccountTransaction(
        smartAccountAddress: String,
        chainId: Int,
        to: String,
        value: String? = nil,
        data: String? = nil,
        provider: String = "ALCHEMY"
    ) async throws -> AATransactionReceipt {
        try await ensureWebViewReady()
        try await ensureTransmissionKeysharesLoaded()

        let params = SendSmartAccountTransactionParams(
            provider: provider,
            smartAccountAddress: smartAccountAddress,
            chainId: chainId,
            to: to,
            value: value,
            data: data
        )

        let result = try await postMessage(method: "sendSmartAccountTransaction", payload: params)
        return try decodeReceipt(result, method: "sendSmartAccountTransaction")
    }

    /// Sends multiple calls atomically through the smart account as a single UserOperation.
    ///
    /// - Parameters:
    ///   - smartAccountAddress: The address returned by ``createSmartAccount(provider:apiKey:chainId:gasPolicyId:mode:walletId:address:)``.
    ///   - chainId: EVM chain ID.
    ///   - calls: Ordered list of calls to batch.
    ///   - provider: AA provider identifier. Defaults to `"ALCHEMY"`.
    /// - Returns: A single receipt for the batched UserOperation.
    func sendSmartAccountBatchTransaction(
        smartAccountAddress: String,
        chainId: Int,
        calls: [SmartAccountCall],
        provider: String = "ALCHEMY"
    ) async throws -> AATransactionReceipt {
        try await ensureWebViewReady()
        try await ensureTransmissionKeysharesLoaded()

        let params = SendSmartAccountBatchTransactionParams(
            provider: provider,
            smartAccountAddress: smartAccountAddress,
            chainId: chainId,
            calls: calls
        )

        let result = try await postMessage(method: "sendSmartAccountBatchTransaction", payload: params)
        return try decodeReceipt(result, method: "sendSmartAccountBatchTransaction")
    }

    // MARK: - Private decoding helpers

    private func decodeSmartAccountInfo(_ result: Any?, method: String) throws -> SmartAccountInfo {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)

        guard let smartAccountAddress = dict["smartAccountAddress"] as? String else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-smartAccountAddress>: Missing smartAccountAddress in response")
        }

        let mode = dict["mode"] as? String ?? "4337"
        let provider = dict["provider"] as? String ?? "ALCHEMY"
        let chainId = (dict["chainId"] as? Int)
            ?? ((dict["chainId"] as? NSNumber)?.intValue)
            ?? (dict["chainId"] as? String).flatMap { Int($0) }
            ?? 0

        return SmartAccountInfo(
            smartAccountAddress: smartAccountAddress,
            mode: mode,
            provider: provider,
            chainId: chainId
        )
    }

    private func decodeReceipt(_ result: Any?, method: String) throws -> AATransactionReceipt {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)

        if let pendingTransactionId = dict["pendingTransactionId"] as? String {
            let reviewUrl = dict["transactionReviewUrl"] as? String
            if let reviewUrl { transactionReviewHandler?(reviewUrl) }
            throw ParaError.transactionDenied(pendingTransactionId: pendingTransactionId, transactionReviewUrl: reviewUrl)
        }

        guard let transactionHash = dict["transactionHash"] as? String else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-transactionHash>: Missing transactionHash in response")
        }

        return AATransactionReceipt(
            transactionHash: transactionHash,
            blockHash: dict["blockHash"] as? String ?? "",
            blockNumber: dict["blockNumber"] as? String ?? "",
            from: dict["from"] as? String ?? "",
            to: dict["to"] as? String,
            status: dict["status"] as? String ?? "",
            gasUsed: dict["gasUsed"] as? String ?? "",
            effectiveGasPrice: dict["effectiveGasPrice"] as? String ?? ""
        )
    }
}
