//
//  ParaCosmosSigner.swift
//  ParaSwift
//
//  Created by Para AI on 1/30/25.
//

import Foundation

/// Signing method for Cosmos transactions
public enum CosmosSigningMethod: String {
    case amino // Standard signing method (default)
    case proto // Modern Proto/Direct signing
}

/// Errors specific to ParaCosmosSigner operations
public enum ParaCosmosSignerError: Error, LocalizedError {
    case invalidWalletType
    case missingWalletId
    case invalidWalletAddress
    case signingFailed(underlyingError: Error?)
    case networkError(underlyingError: Error?)
    case bridgeError(String)
    case invalidTransaction(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWalletType: "Invalid wallet type - expected Cosmos wallet"
        case .missingWalletId: "Wallet ID is missing"
        case .invalidWalletAddress: "Wallet address is missing or invalid"
        case let .signingFailed(error): "Signing operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .networkError(error): "Network operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .bridgeError(message): "Bridge operation failed: \(message)"
        case let .invalidTransaction(message): "Invalid transaction: \(message)"
        }
    }
}

/// A signer for Cosmos blockchain operations using Para's secure key management via bridge
@MainActor
public class ParaCosmosSigner: ObservableObject {
    private let paraManager: ParaManager
    private var walletId: String?
    private let rpcUrl: String
    private let chainId: String
    private let prefix: String

    /// Initialize a new ParaCosmosSigner
    public init(
        paraManager: ParaManager,
        chainId: String = "provider",
        rpcUrl: String = "https://rpc.provider-sentry-01.ics-testnet.polypore.xyz",
        prefix: String = "cosmos",
        walletId: String? = nil
    ) throws {
        self.paraManager = paraManager
        self.chainId = chainId
        self.rpcUrl = rpcUrl
        self.prefix = prefix

        if let walletId {
            Task { try await selectWallet(walletId: walletId) }
        }
    }

    /// Select a wallet for signing operations
    public func selectWallet(walletId: String) async throws {
        let args = CosmosSignerInitArgs(walletId: walletId, prefix: prefix, messageSigningTimeoutMs: nil)
        _ = try await paraManager.postMessage(method: "initCosmJsSigners", payload: args)
        self.walletId = walletId
    }

    /// Get the current wallet's address for this chain
    public func getAddress() async throws -> String {
        guard let walletId else { throw ParaCosmosSignerError.missingWalletId }

        do {
            // Use the bridge to get the proper address for this chain
            let result = try await paraManager.postMessage(method: "getCosmosSignerAddress", payload: EmptyPayload())
            
            if let addressResponse = result as? [String: Any],
               let addressString = addressResponse["address"] as? String,
               !addressString.isEmpty {
                return addressString
            }
            
            // Fallback to wallet fetch if bridge method doesn't work
            let wallets = try await paraManager.fetchWallets()
            guard let wallet = wallets.first(where: { $0.id == walletId && $0.type == .cosmos }) else {
                throw ParaCosmosSignerError.invalidWalletType
            }

            guard let cosmosAddress = wallet.addressSecondary, !cosmosAddress.isEmpty else {
                throw ParaCosmosSignerError.invalidWalletAddress
            }

            // If the wallet address already has the correct prefix, use it
            if cosmosAddress.hasPrefix(prefix + "1") {
                return cosmosAddress
            }
            
            // For now, return the original address and let the bridge handle conversion
            return cosmosAddress
        } catch let error as ParaWebViewError {
            throw ParaCosmosSignerError.bridgeError("Failed to get address: \(error.localizedDescription)")
        }
    }

    /// Get the balance for this wallet
    public func getBalance(denom: String? = nil) async throws -> String {
        guard walletId != nil else { throw ParaCosmosSignerError.missingWalletId }

        let address = try await getAddress()
        let queryDenom = denom ?? getDefaultDenom()

        do {
            let args = ["address": address, "denom": queryDenom, "rpcUrl": rpcUrl]
            let result = try await paraManager.postMessage(method: "cosmJsGetBalance", payload: args)

            guard let balanceInfo = result as? [String: Any],
                  let amount = balanceInfo["amount"] as? String else {
                throw ParaCosmosSignerError.bridgeError("Invalid balance response from bridge")
            }

            return amount
        } catch let error as ParaWebViewError {
            throw ParaCosmosSignerError.networkError(underlyingError: error)
        } catch {
            throw ParaCosmosSignerError.networkError(underlyingError: error)
        }
    }

    /// Sign arbitrary message (for demo/testing purposes)
    public func signMessage(_ message: String) async throws -> Data {
        guard let walletId else { throw ParaCosmosSignerError.missingWalletId }

        do {
            let messageBase64 = Data(message.utf8).base64EncodedString()
            let signatureString = try await paraManager.signMessage(walletId: walletId, message: messageBase64)

            guard let signatureData = Data(hexString: signatureString) else {
                throw ParaCosmosSignerError.bridgeError("Invalid signature format")
            }

            return signatureData
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }

    /// Sign a Cosmos transaction (without broadcasting)
    public func signTransaction(
        to recipient: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) async throws -> [String: Any] {
        guard let walletId else { throw ParaCosmosSignerError.missingWalletId }
        guard isValidBech32Address(recipient) else {
            throw ParaCosmosSignerError.invalidTransaction("Invalid recipient address: \(recipient)")
        }

        let fromAddress = try await getAddress()
        let tokenDenom = denom ?? getDefaultDenom()

        do {
            // Create transaction data for signing only
            let (messagesJson, feeJson) = try createTransactionData(
                fromAddress: fromAddress,
                toAddress: recipient,
                amount: amount,
                denom: tokenDenom
            )

            let args = [
                "walletId": walletId,
                "chainId": chainId,
                "rpcUrl": rpcUrl,
                "messages": messagesJson,
                "fee": feeJson,
                "memo": memo ?? "",
                "signingMethod": signingMethod.rawValue
            ]

            let result = try await paraManager.postMessage(method: "cosmJsSignTransaction", payload: args)

            guard let responseDict = result as? [String: Any] else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from bridge")
            }

            return responseDict
        } catch let error as ParaCosmosSignerError {
            throw error
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }

    /// Send a Cosmos transaction (sign and broadcast) using standard CosmJS pattern
    public func sendTransaction(
        to recipient: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .proto
    ) async throws -> String {
        guard let walletId else { throw ParaCosmosSignerError.missingWalletId }
        guard isValidBech32Address(recipient) else {
            throw ParaCosmosSignerError.invalidTransaction("Invalid recipient address: \(recipient)")
        }

        let fromAddress = try await getAddress()
        let tokenDenom = denom ?? getDefaultDenom()

        do {
            // Initialize SigningStargateClient
            let clientArgs = ["rpcUrl": rpcUrl, "signingMethod": signingMethod.rawValue]
            _ = try await paraManager.postMessage(method: "initCosmosStargateClient", payload: clientArgs)

            // Create transaction data
            let (messagesJson, feeJson) = try createTransactionData(
                fromAddress: fromAddress,
                toAddress: recipient,
                amount: amount,
                denom: tokenDenom
            )

            // Sign and broadcast
            let broadcastArgs = [
                "signerAddress": fromAddress,
                "messages": messagesJson,
                "fee": feeJson,
                "memo": memo ?? ""
            ]

            let result = try await paraManager.postMessage(method: "cosmosSignAndBroadcast", payload: broadcastArgs)

            guard let responseDict = result as? [String: Any],
                  let transactionHash = responseDict["transactionHash"] as? String else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from bridge")
            }

            return transactionHash
        } catch let error as ParaCosmosSignerError {
            throw error
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }

    // MARK: - Private Helpers

    private func convertAddressToPrefix(_ address: String, targetPrefix: String) -> String {
        if address.hasPrefix(targetPrefix + "1") { return address }

        guard let separatorIndex = address.firstIndex(of: "1") else { return address }
        let dataPartStart = address.index(after: separatorIndex)
        let dataPart = String(address[dataPartStart...])
        return targetPrefix + "1" + dataPart
    }

    private func getDefaultDenom() -> String {
        switch chainId {
        case "provider": "uatom"
        case "osmo-test-5": "uosmo"
        case "cosmoshub-4": "uatom"
        case "osmosis-1": "uosmo"
        case "juno-1": "ujuno"
        case "stargaze-1": "ustars"
        default: "uatom"
        }
    }

    private func createTransactionData(fromAddress: String, toAddress: String, amount: String, denom: String) throws -> (String, String) {
        let message: [String: Any] = [
            "typeUrl": "/cosmos.bank.v1beta1.MsgSend",
            "value": [
                "fromAddress": fromAddress,
                "toAddress": toAddress,
                "amount": [["denom": denom, "amount": amount]]
            ]
        ]

        let fee: [String: Any] = [
            "amount": [["denom": denom, "amount": "5000"]],
            "gas": "200000"
        ]

        let messagesData = try JSONSerialization.data(withJSONObject: [message])
        let feeData = try JSONSerialization.data(withJSONObject: fee)

        guard let messagesJson = String(data: messagesData, encoding: .utf8),
              let feeJson = String(data: feeData, encoding: .utf8) else {
            throw ParaCosmosSignerError.bridgeError("Failed to encode transaction data")
        }

        return (messagesJson, feeJson)
    }

    private func isValidBech32Address(_ address: String) -> Bool {
        let parts = address.components(separatedBy: "1")
        guard parts.count == 2 else { return false }

        let hrp = parts[0], data = parts[1]
        guard hrp.count >= 1, hrp.count <= 10,
              data.count >= 6, data.count <= 87,
              address.count >= 8, address.count <= 90 else { return false }

        let bech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        return data.lowercased().allSatisfy { bech32Charset.contains($0) }
    }
}
