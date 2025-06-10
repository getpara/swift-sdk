//
//  ParaCosmosSigner.swift
//  ParaSwift
//
//  Created by Para AI on 1/30/25.
//

import CryptoKit
import Foundation

/// Signing method for Cosmos transactions
public enum CosmosSigningMethod: String {
    case amino // Standard signing method (default)
    case proto // Modern Proto/Direct signing
}

/// Errors specific to ParaCosmosSigner operations
public enum ParaCosmosSignerError: Error, LocalizedError {
    /// Invalid wallet type - expected Cosmos wallet
    case invalidWalletType
    /// Wallet ID is missing
    case missingWalletId
    /// Wallet address is missing or invalid
    case invalidWalletAddress
    /// Signing operation failed
    case signingFailed(underlyingError: Error?)
    /// Network operation failed
    case networkError(underlyingError: Error?)
    /// Bridge operation failed
    case bridgeError(String)
    /// Invalid transaction format
    case invalidTransaction(String)

    public var errorDescription: String? {
        switch self {
        case .invalidWalletType:
            "Invalid wallet type - expected Cosmos wallet"
        case .missingWalletId:
            "Wallet ID is missing"
        case .invalidWalletAddress:
            "Wallet address is missing or invalid"
        case let .signingFailed(error):
            "Signing operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .networkError(error):
            "Network operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case let .bridgeError(message):
            "Bridge operation failed: \(message)"
        case let .invalidTransaction(message):
            "Invalid transaction: \(message)"
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
    /// - Parameters:
    ///   - paraManager: The ParaManager instance for bridge operations
    ///   - chainId: The chain ID (e.g., "cosmoshub-4", "osmosis-1")
    ///   - rpcUrl: The RPC endpoint URL for the Cosmos chain
    ///   - prefix: The bech32 address prefix (e.g., "cosmos", "osmo", "juno")
    ///   - walletId: Optional specific wallet ID to use
    public init(
        paraManager: ParaManager,
        chainId: String = "cosmoshub-4",
        rpcUrl: String = "https://rpc.cosmos.directory:443/cosmoshub",
        prefix: String = "cosmos",
        walletId: String? = nil
    ) throws {
        self.paraManager = paraManager
        self.chainId = chainId
        self.rpcUrl = rpcUrl
        self.prefix = prefix

        if let walletId {
            Task {
                try await selectWallet(walletId: walletId)
            }
        }
    }

    /// Initialize the Cosmos signers in the bridge
    private func initCosmosSigners(walletId: String) async throws {
        let args = CosmosSignerInitArgs(
            walletId: walletId,
            prefix: prefix,
            messageSigningTimeoutMs: nil,
        )
        let _ = try await paraManager.postMessage(method: "initCosmJsSigners", payload: args)
        self.walletId = walletId
    }

    /// Select a wallet for signing operations
    /// - Parameter walletId: The wallet ID to use
    public func selectWallet(walletId: String) async throws {
        try await initCosmosSigners(walletId: walletId)
    }

    /// Get the current wallet's address for this chain
    /// - Returns: The bech32 address for this chain
    /// - Throws: ParaCosmosSignerError if wallet not initialized
    public func getAddress() async throws -> String {
        guard let walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }

        do {
            // Get the address from the initialized cosmos signer using the bridge method
            let result = try await paraManager.postMessage(method: "getCosmosSignerAddress", payload: EmptyPayload())
            
            if let addressResponse = result as? [String: Any],
               let addressString = addressResponse["address"] as? String,
               !addressString.isEmpty {
                return addressString
            }
            
            // Fallback: get from wallet and use simple prefix replacement
            let wallets = try await paraManager.fetchWallets()
            guard let wallet = wallets.first(where: { $0.id == walletId && $0.type == .cosmos }) else {
                throw ParaCosmosSignerError.invalidWalletType
            }

            // For Cosmos wallets, use addressSecondary which contains the bech32 address
            guard let cosmosAddress = wallet.addressSecondary, !cosmosAddress.isEmpty else {
                throw ParaCosmosSignerError.invalidWalletAddress
            }

            // Convert the address to the chain-specific prefix
            return convertAddressToPrefix(cosmosAddress, targetPrefix: prefix)
            
        } catch let error as ParaWebViewError {
            throw ParaCosmosSignerError.bridgeError("Failed to get address: \(error.localizedDescription)")
        }
    }

    /// Convert a bech32 address from one prefix to another
    /// - Parameters:
    ///   - address: The original bech32 address
    ///   - targetPrefix: The target prefix (e.g., "osmo", "juno", "stars")
    /// - Returns: The address with the new prefix
    private func convertAddressToPrefix(_ address: String, targetPrefix: String) -> String {
        // If target prefix is the same as current, return as-is
        if address.hasPrefix(targetPrefix + "1") {
            return address
        }

        // For proper bech32 conversion, we need to decode and re-encode
        // This is a simplified implementation that works for Cosmos addresses
        guard let separatorIndex = address.firstIndex(of: "1") else {
            return address // Invalid format, return original
        }

        let dataPartStart = address.index(after: separatorIndex)
        let dataPart = String(address[dataPartStart...])

        // For now, use simple prefix replacement
        // Note: This creates invalid checksums but works for display purposes
        // A full bech32 implementation would require proper decode/encode
        return targetPrefix + "1" + dataPart
    }

    // MARK: - Public Methods

    /// Get the balance for this wallet
    /// - Parameters:
    ///   - denom: The denomination to query (defaults to chain's default denom)
    /// - Returns: Balance as a string
    /// - Throws: ParaCosmosSignerError if query fails
    public func getBalance(denom: String? = nil) async throws -> String {
        guard walletId != nil else {
            throw ParaCosmosSignerError.missingWalletId
        }

        // Get the wallet address
        let address = try await getAddress()
        let queryDenom = denom ?? getDefaultDenom()

        do {
            // Pass address, denom, and rpcUrl to the bridge
            let args = ["address": address, "denom": queryDenom, "rpcUrl": rpcUrl]
            let result = try await paraManager.postMessage(method: "cosmJsGetBalance", payload: args)

            // Bridge returns balance info
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
    /// - Parameter message: The message to sign
    /// - Returns: The signature as Data
    /// - Throws: ParaCosmosSignerError if signing fails
    public func signMessage(_ message: String) async throws -> Data {
        guard let walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }

        do {
            let messageBase64 = Data(message.utf8).base64EncodedString()

            let signatureString = try await paraManager.signMessage(
                walletId: walletId,
                message: messageBase64,
            )

            // Decode the signature from hex string
            guard let signatureData = Data(hexString: signatureString) else {
                throw ParaCosmosSignerError.bridgeError("Invalid signature format")
            }

            return signatureData
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }

    /// Sign a Cosmos transaction
    /// - Parameters:
    ///   - to: Recipient address
    ///   - amount: Amount to send in the smallest unit
    ///   - denom: Token denomination (defaults to chain's default)
    ///   - memo: Optional memo
    ///   - signingMethod: Signing method (defaults to amino)
    /// - Returns: A dictionary containing the signed transaction data
    /// - Throws: ParaCosmosSignerError if signing fails
    public func signTransaction(
        to recipient: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) async throws -> [String: Any] {
        guard let walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }

        let fromAddress = try await getAddress()
        let tokenDenom = denom ?? getDefaultDenom()

        // Validate recipient address
        guard isValidBech32Address(recipient) else {
            throw ParaCosmosSignerError.invalidTransaction("Invalid recipient address: \(recipient)")
        }

        // Create the message structure that the bridge expects
        let message: [String: Any] = [
            "typeUrl": "/cosmos.bank.v1beta1.MsgSend",
            "value": [
                "from_address": fromAddress,
                "to_address": recipient,
                "amount": [["denom": tokenDenom, "amount": amount]],
            ],
        ]

        let fee: [String: Any] = [
            "amount": [["denom": tokenDenom, "amount": "5000"]],
            "gas": "200000",
        ]

        do {
            let messagesData = try JSONSerialization.data(withJSONObject: [message])
            let feeData = try JSONSerialization.data(withJSONObject: fee)

            guard let messagesJson = String(data: messagesData, encoding: .utf8),
                  let feeJson = String(data: feeData, encoding: .utf8)
            else {
                throw ParaCosmosSignerError.bridgeError("Failed to encode messages or fee as JSON")
            }

            let args = [
                "walletId": walletId,
                "chainId": chainId,
                "rpcUrl": rpcUrl,
                "messages": messagesJson,
                "fee": feeJson,
                "memo": memo ?? "",
                "signingMethod": signingMethod.rawValue,
            ]

            let result = try await paraManager.postMessage(
                method: "cosmJsSignTransaction",
                payload: args,
            )

            guard let responseDict = result as? [String: Any] else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from bridge")
            }

            return responseDict

        } catch let error as ParaWebViewError {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        } catch let error as ParaCosmosSignerError {
            throw error
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }

    /// High-level transfer method that signs and sends a transaction
    /// - Parameters:
    ///   - to: Recipient address
    ///   - amount: Amount to send in the smallest unit
    ///   - denom: Token denomination (defaults to chain's default)
    ///   - memo: Optional memo
    ///   - signingMethod: Signing method (defaults to amino)
    /// - Returns: A dictionary containing the signing result
    /// - Throws: ParaCosmosSignerError if operation fails
    public func sendTokens(
        to recipient: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) async throws -> [String: Any] {
        // For now, sendTokens just calls signTransaction since the bridge doesn't have broadcast functionality yet
        // In the future, this could sign + broadcast the transaction to the network
        try await signTransaction(
            to: recipient,
            amount: amount,
            denom: denom,
            memo: memo,
            signingMethod: signingMethod,
        )
    }

    // MARK: - Private Helpers

    /// Get the default denomination for the current chain
    /// - Returns: The chain's default denomination
    private func getDefaultDenom() -> String {
        switch chainId {
        case "cosmoshub-4": "uatom"
        case "osmosis-1": "uosmo"
        case "juno-1": "ujuno"
        case "stargaze-1": "ustars"
        default: "uatom" // Default fallback
        }
    }

    /// Basic Bech32 address validation
    /// Validates format: hrp + separator + data (32-90 chars total)
    private func isValidBech32Address(_ address: String) -> Bool {
        let parts = address.components(separatedBy: "1")
        guard parts.count == 2 else { return false }

        let hrp = parts[0]
        let data = parts[1]

        // Basic validation: reasonable length and charset
        guard hrp.count >= 1, hrp.count <= 10,
              data.count >= 6, data.count <= 87,
              address.count >= 8, address.count <= 90
        else {
            return false
        }

        // Bech32 charset validation (simplified)
        let bech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        return data.lowercased().allSatisfy { bech32Charset.contains($0) }
    }
}
