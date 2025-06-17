//
//  ParaCosmosSigner.swift
//  ParaSwift
//
//  Created by Para AI on 6/17/25.
//

import Foundation

/// Errors specific to ParaCosmosSigner operations
public enum ParaCosmosSignerError: Error, LocalizedError {
    case invalidWalletType
    case missingWalletId
    case invalidWalletAddress
    case signingFailed(underlyingError: Error?)
    case networkError(underlyingError: Error?)
    case bridgeError(String)
    case invalidTransaction(String)
    case protoSigningFailed(underlyingError: Error?)
    case aminoSigningFailed(underlyingError: Error?)
    case invalidSignDoc(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWalletType: "Invalid wallet type - expected Cosmos wallet"
        case .missingWalletId: "Wallet ID is missing"
        case .invalidWalletAddress: "Wallet address is missing or invalid"
        case let .signingFailed(error): "Signing operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .networkError(error): "Network operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .bridgeError(message): "Bridge operation failed: \(message)"
        case let .invalidTransaction(message): "Invalid transaction: \(message)"
        case let .protoSigningFailed(error): "Proto/Direct signing failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .aminoSigningFailed(error): "Amino signing failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .invalidSignDoc(message): "Invalid SignDoc: \(message)"
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
        chainId: String = "cosmoshub-4",
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
               !addressString.isEmpty
            {
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
        guard let _ = walletId else { throw ParaCosmosSignerError.missingWalletId }

        let address = try await getAddress()
        let queryDenom = denom ?? getDefaultDenom()

        do {
            let args = CosmJsGetBalanceArgs(address: address, denom: queryDenom, rpcUrl: rpcUrl)
            let result = try await paraManager.postMessage(method: "cosmJsGetBalance", payload: args)

            guard let balanceInfo = result as? [String: Any],
                  let amount = balanceInfo["amount"] as? String
            else {
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

    /// Sign a transaction using direct/proto signing
    /// Uses the cosmJsSignDirect bridge method for direct access to CosmJS proto signing
    /// Note: "Direct" and "Proto" refer to the same signing method in CosmJS
    public func signDirect(signDocBase64: String) async throws -> [String: Any] {
        guard let _ = walletId else { throw ParaCosmosSignerError.missingWalletId }

        let address = try await getAddress()
        let args = CosmJsSignDirectArgs(signerAddress: address, signDocBase64: signDocBase64)

        do {
            let result = try await paraManager.postMessage(method: "cosmJsSignDirect", payload: args)
            guard let responseDict = result as? [String: Any] else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from cosmJsSignDirect")
            }
            return responseDict
        } catch {
            throw ParaCosmosSignerError.protoSigningFailed(underlyingError: error)
        }
    }

    /// Sign a transaction using amino signing
    /// Uses the cosmJsSignAmino bridge method for direct access to CosmJS amino signing
    public func signAmino(signDocBase64: String) async throws -> [String: Any] {
        guard let _ = walletId else { throw ParaCosmosSignerError.missingWalletId }

        let address = try await getAddress()
        let args = CosmJsSignAminoArgs(signerAddress: address, signDocBase64: signDocBase64)

        do {
            let result = try await paraManager.postMessage(method: "cosmJsSignAmino", payload: args)
            guard let responseDict = result as? [String: Any] else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from cosmJsSignAmino")
            }
            return responseDict
        } catch {
            throw ParaCosmosSignerError.aminoSigningFailed(underlyingError: error)
        }
    }

    // MARK: - Private Helpers

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
}
