//
//  ParaCosmosSigner.swift
//  ParaSwift
//
//  Created by Para AI on 1/30/25.
//

import Foundation

/// Errors specific to ParaCosmosSigner operations
public enum ParaCosmosSignerError: Error, LocalizedError {
    /// Invalid wallet type - expected Cosmos wallet
    case invalidWalletType
    /// Wallet ID is missing
    case missingWalletId
    /// Wallet address is missing or invalid
    case invalidWalletAddress
    /// Invalid chain prefix
    case invalidPrefix(String)
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
            return "Invalid wallet type - expected Cosmos wallet"
        case .missingWalletId:
            return "Wallet ID is missing"
        case .invalidWalletAddress:
            return "Wallet address is missing or invalid"
        case .invalidPrefix(let prefix):
            return "Invalid chain prefix: \(prefix)"
        case .signingFailed(let error):
            return "Signing operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case .networkError(let error):
            return "Network operation failed: \(error?.localizedDescription ?? "Unknown error")"
        case .bridgeError(let message):
            return "Bridge operation failed: \(message)"
        case .invalidTransaction(let message):
            return "Invalid transaction: \(message)"
        }
    }
}

/// Supported Cosmos chains - keeping it simple for v1
public enum CosmosChain: String {
    case cosmos = "cosmos"
    
    /// The bech32 prefix for this chain
    public var prefix: String {
        return self.rawValue
    }
    
    /// Default denomination for this chain
    public var defaultDenom: String {
        return "uatom"
    }
}

/// A signer for Cosmos blockchain operations using Para's secure key management via bridge
@MainActor
public class ParaCosmosSigner: ObservableObject {
    private let paraManager: ParaManager
    private let prefix: String
    private var walletId: String?
    private let messageSigningTimeoutMs: Int?
    private let rpcUrl: String
    
    /// The chain this signer is configured for
    public let chain: CosmosChain?
    
    /// Initialize a new ParaCosmosSigner with a specific chain
    /// - Parameters:
    ///   - paraManager: The ParaManager instance for bridge operations
    ///   - chain: The Cosmos chain to use
    ///   - rpcUrl: The RPC endpoint URL for the Cosmos chain
    ///   - walletId: Optional specific wallet ID to use
    ///   - messageSigningTimeoutMs: Optional timeout for signing operations
    public init(
        paraManager: ParaManager,
        chain: CosmosChain,
        rpcUrl: String = "https://rpc.cosmos.directory:443/cosmoshub",
        walletId: String? = nil,
        messageSigningTimeoutMs: Int? = nil
    ) throws {
        self.paraManager = paraManager
        self.prefix = chain.prefix
        self.chain = chain
        self.rpcUrl = rpcUrl
        self.messageSigningTimeoutMs = messageSigningTimeoutMs
        
        if let walletId = walletId {
            Task {
                try await selectWallet(walletId: walletId)
            }
        }
    }
    
    /// Initialize a new ParaCosmosSigner with a custom prefix
    /// - Parameters:
    ///   - paraManager: The ParaManager instance for bridge operations
    ///   - prefix: Custom chain prefix (e.g., "cosmos", "osmo")
    ///   - rpcUrl: The RPC endpoint URL for the Cosmos chain
    ///   - walletId: Optional specific wallet ID to use
    ///   - messageSigningTimeoutMs: Optional timeout for signing operations
    public init(
        paraManager: ParaManager,
        prefix: String,
        rpcUrl: String = "https://rpc.cosmos.directory:443/cosmoshub",
        walletId: String? = nil,
        messageSigningTimeoutMs: Int? = nil
    ) throws {
        guard !prefix.isEmpty else {
            throw ParaCosmosSignerError.invalidPrefix("Prefix cannot be empty")
        }
        
        self.paraManager = paraManager
        self.prefix = prefix
        self.chain = CosmosChain(rawValue: prefix)
        self.rpcUrl = rpcUrl
        self.messageSigningTimeoutMs = messageSigningTimeoutMs
        
        if let walletId = walletId {
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
            messageSigningTimeoutMs: messageSigningTimeoutMs
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
        guard let walletId = self.walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }
        
        // Fetch wallets to get the address
        let wallets = try await paraManager.fetchWallets()
        guard let wallet = wallets.first(where: { $0.id == walletId && $0.type == .cosmos }) else {
            throw ParaCosmosSignerError.invalidWalletType
        }
        
        // For Cosmos wallets, use addressSecondary which contains the bech32 address
        guard let cosmosAddress = wallet.addressSecondary, !cosmosAddress.isEmpty else {
            throw ParaCosmosSignerError.invalidWalletAddress
        }
        
        return cosmosAddress
    }
    
    // MARK: - Public Methods
    
    /// Get the balance for this wallet
    /// - Parameters:
    ///   - denom: The denomination to query (defaults to chain's default denom)
    /// - Returns: Balance as a string
    /// - Throws: ParaCosmosSignerError if query fails
    public func getBalance(denom: String? = nil) async throws -> String {
        guard self.walletId != nil else {
            throw ParaCosmosSignerError.missingWalletId
        }
        
        // Get the wallet address
        let address = try await getAddress()
        let queryDenom = denom ?? chain?.defaultDenom ?? "uatom"
        
        do {
            // Pass address, denom, and rpcUrl to the bridge
            let args = ["address": address, "denom": queryDenom, "rpcUrl": rpcUrl]
            let result = try await paraManager.postMessage(method: "cosmJsGetBalance", payload: args)
            
            // Bridge returns balance info
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
    
    /// Sign a Cosmos transaction using the specified method
    /// - Parameters:
    ///   - transaction: The CosmosTransaction to sign
    ///   - method: The signing method to use (defaults to transaction's preferred method)
    /// - Returns: The signed transaction response
    /// - Throws: ParaCosmosSignerError if signing fails
    public func signTransaction(
        _ transaction: CosmosTransaction,
        method: CosmosSigningMethod? = nil
    ) async throws -> CosmosSignResponse {
        guard let walletId = self.walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }
        
        let signingMethod = method ?? transaction.signingMethod
        
        do {
            // Use simple string dictionary like other signers do
            let messagesArray = transaction.messages.map { msg in
                ["typeUrl": msg.typeUrl, "value": msg.value]
            }
            let feeDict: [String: Any] = [
                "amount": transaction.fee.amount.map { coin in
                    ["denom": coin.denom, "amount": coin.amount]
                },
                "gas": transaction.fee.gas
            ]
            
            let messagesData = try JSONSerialization.data(withJSONObject: messagesArray)
            let feeData = try JSONSerialization.data(withJSONObject: feeDict)
            
            guard let messagesJson = String(data: messagesData, encoding: .utf8),
                  let feeJson = String(data: feeData, encoding: .utf8) else {
                throw ParaCosmosSignerError.bridgeError("Failed to encode messages or fee as JSON")
            }
            
            // Use simple string dictionary like other working signers
            let args = [
                "walletId": walletId,
                "chainId": "cosmoshub-4",
                "rpcUrl": rpcUrl,
                "messages": messagesJson,
                "fee": feeJson,
                "memo": transaction.memo ?? "",
                "signingMethod": signingMethod.rawValue
            ]
            
            let result = try await paraManager.postMessage(
                method: "cosmJsSignTransaction",
                payload: args
            )
            
            // Parse the response
            guard let responseDict = result as? [String: Any] else {
                throw ParaCosmosSignerError.bridgeError("Invalid response format from bridge")
            }
            
            return try parseSignResponse(responseDict, signingMethod: signingMethod)
            
        } catch let error as ParaWebViewError {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        } catch let error as ParaCosmosSignerError {
            throw error
        } catch {
            throw ParaCosmosSignerError.signingFailed(underlyingError: error)
        }
    }
    
    /// Sign arbitrary message (for demo/testing purposes)
    /// - Parameter message: The message to sign
    /// - Returns: The signature as Data
    /// - Throws: ParaCosmosSignerError if signing fails
    public func signMessage(_ message: String) async throws -> Data {
        guard let walletId = self.walletId else {
            throw ParaCosmosSignerError.missingWalletId
        }
        
        do {
            let messageBase64 = Data(message.utf8).base64EncodedString()
            
            let signatureString = try await paraManager.signMessage(
                walletId: walletId,
                message: messageBase64
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
    
    /// Create a transfer transaction for this chain
    /// - Parameters:
    ///   - toAddress: Recipient address
    ///   - amount: Amount to send
    ///   - denom: Token denomination (defaults to chain's default)
    ///   - memo: Optional memo
    ///   - signingMethod: Signing method (defaults to amino)
    /// - Returns: A configured CosmosTransaction
    /// - Throws: CosmosTransactionError if parameters are invalid
    public func createTransferTransaction(
        toAddress: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) async throws -> CosmosTransaction {
        let fromAddress = try await getAddress()
        let tokenDenom = denom ?? chain?.defaultDenom ?? "uatom"
        
        return try CosmosTransaction.transfer(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
            denom: tokenDenom,
            memo: memo,
            signingMethod: signingMethod
        )
    }
    
    /// High-level transfer method
    /// - Parameters:
    ///   - to: Recipient address
    ///   - amount: Amount to send in the smallest unit
    ///   - denom: Token denomination (defaults to chain's default)
    ///   - memo: Optional memo
    ///   - signingMethod: Signing method (defaults to amino)
    /// - Returns: The signed transaction response
    /// - Throws: ParaCosmosSignerError if operation fails
    public func sendTokens(
        to recipient: String,
        amount: String,
        denom: String? = nil,
        memo: String? = nil,
        signingMethod: CosmosSigningMethod = .amino
    ) async throws -> CosmosSignResponse {
        let fromAddress = try await getAddress()
        let tokenDenom = denom ?? chain?.defaultDenom ?? "uatom"
        
        let transaction = try CosmosTransaction(
            messages: [
                try CosmosMessage.send(
                    fromAddress: fromAddress,
                    toAddress: recipient,
                    amount: [CosmosCoin(denom: tokenDenom, amount: amount)]
                )
            ],
            fee: try CosmosFee(denom: tokenDenom, amount: "5000", gas: "200000"),
            memo: memo,
            signingMethod: signingMethod
        )
        
        return try await signTransaction(transaction)
    }
    
    // MARK: - Private Helpers
    
    /// Parse the sign response from the bridge
    private func parseSignResponse(
        _ responseDict: [String: Any],
        signingMethod: CosmosSigningMethod
    ) throws -> CosmosSignResponse {
        // Extract signature information - both Amino and Proto responses have similar structure
        guard let signature = responseDict["signature"] as? [String: Any],
              let sig = signature["signature"] as? String else {
            throw ParaCosmosSignerError.bridgeError("Missing signature in response")
        }
        
        // Extract pubkey if available (optional since bridge handles this)
        var pubKey: CosmosPubKey?
        if let pubKeyDict = signature["pub_key"] as? [String: Any],
           let pubKeyType = pubKeyDict["type"] as? String,
           let pubKeyValue = pubKeyDict["value"] as? String {
            pubKey = CosmosPubKey(type: pubKeyType, value: pubKeyValue)
        }
        
        let cosmosSignature = CosmosSignature(pubKey: pubKey, signature: sig)
        
        // Extract signed document
        let signedDoc = responseDict["signed"] as? [String: Any] ?? [:]
        
        return CosmosSignResponse(signature: cosmosSignature, signedDoc: signedDoc)
    }
}