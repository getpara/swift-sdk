//
//  ParaEvmSigner.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/5/25.
//

import Foundation
import BigInt

/// A struct representing an Ethereum transaction
public struct EVMTransaction: Codable {
    /// The recipient address
    public let to: String?
    /// The value in wei
    public let value: BigUInt?
    /// Gas limit for the transaction
    public let gasLimit: BigUInt?
    /// Legacy gas price in wei
    public let gasPrice: BigUInt?
    /// EIP-1559 max priority fee per gas
    public let maxPriorityFeePerGas: BigUInt?
    /// EIP-1559 max fee per gas
    public let maxFeePerGas: BigUInt?
    /// Transaction nonce
    public let nonce: BigUInt?
    /// Chain ID
    public let chainId: BigUInt?
    /// Smart contract ABI (if contract interaction)
    public let smartContractAbi: String?
    /// Smart contract function name (if contract interaction)
    public let smartContractFunctionName: String?
    /// Smart contract function arguments (if contract interaction)
    public let smartContractFunctionArgs: [String]?
    /// Smart contract bytecode (if contract deployment)
    public let smartContractByteCode: String?
    /// Transaction type (0 = legacy, 1 = access list, 2 = EIP-1559)
    public let type: Int?
    
    /// Creates a new EVM transaction
    /// - Parameters:
    ///   - to: The recipient address
    ///   - value: The value in wei
    ///   - gasLimit: Gas limit for the transaction
    ///   - gasPrice: Legacy gas price in wei
    ///   - maxPriorityFeePerGas: EIP-1559 max priority fee per gas
    ///   - maxFeePerGas: EIP-1559 max fee per gas
    ///   - nonce: Transaction nonce
    ///   - chainId: Chain ID
    ///   - smartContractAbi: Smart contract ABI (if contract interaction)
    ///   - smartContractFunctionName: Smart contract function name (if contract interaction)
    ///   - smartContractFunctionArgs: Smart contract function arguments (if contract interaction)
    ///   - smartContractByteCode: Smart contract bytecode (if contract deployment)
    ///   - type: Transaction type (0 = legacy, 1 = access list, 2 = EIP-1559)
    public init(
        to: String? = nil,
        value: BigUInt? = nil,
        gasLimit: BigUInt? = nil,
        gasPrice: BigUInt? = nil,
        maxPriorityFeePerGas: BigUInt? = nil,
        maxFeePerGas: BigUInt? = nil,
        nonce: BigUInt? = nil,
        chainId: BigUInt? = nil,
        smartContractAbi: String? = nil,
        smartContractFunctionName: String? = nil,
        smartContractFunctionArgs: [String]? = nil,
        smartContractByteCode: String? = nil,
        type: Int? = nil
    ) {
        self.to = to
        self.value = value
        self.gasLimit = gasLimit
        self.gasPrice = gasPrice
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.nonce = nonce
        self.chainId = chainId
        self.smartContractAbi = smartContractAbi
        self.smartContractFunctionName = smartContractFunctionName
        self.smartContractFunctionArgs = smartContractFunctionArgs
        self.smartContractByteCode = smartContractByteCode
        self.type = type
    }
    
    /// Convenience initializer for simple ETH transfers
    /// - Parameters:
    ///   - to: Recipient address
    ///   - value: Amount in wei
    ///   - gasLimit: Gas limit
    public init(to: String, value: BigUInt, gasLimit: BigUInt) {
        self.init(
            to: to,
            value: value,
            gasLimit: gasLimit,
            type: 2  // Default to EIP-1559
        )
    }
    
    /// Convenience initializer for contract interactions
    /// - Parameters:
    ///   - contract: Contract address
    ///   - abi: Contract ABI
    ///   - function: Function name
    ///   - args: Function arguments
    ///   - value: Value in wei (if payable)
    ///   - gasLimit: Gas limit
    public init(
        contract: String,
        abi: String,
        function: String,
        args: [String],
        value: BigUInt? = nil,
        gasLimit: BigUInt
    ) {
        self.init(
            to: contract,
            value: value,
            gasLimit: gasLimit,
            smartContractAbi: abi,
            smartContractFunctionName: function,
            smartContractFunctionArgs: args,
            type: 2  // Default to EIP-1559
        )
    }
    
    public func b64Encoded() -> String {
        let encodedTransaction = try! JSONEncoder().encode(self)
        return encodedTransaction.base64EncodedString()
    }
}

// MARK: - MetaMask Conversion

extension EVMTransaction {
    /// Converts the transaction to MetaMask format
    /// - Parameter from: The sender address
    /// - Returns: Transaction in MetaMask format
    func toMetaMaskFormat(from: String) -> [String: String] {
        var tx: [String: String] = ["from": from]
        
        // Helper function to convert BigUInt to hex string
        func toHexString(_ value: BigUInt?) -> String? {
            value.map { "0x" + String($0, radix: 16) }
        }
        
        if let to = to { tx["to"] = to }
        if let value = toHexString(value) { tx["value"] = value }
        if let gasLimit = toHexString(gasLimit) { tx["gasLimit"] = gasLimit }
        if let gasPrice = toHexString(gasPrice) { tx["gasPrice"] = gasPrice }
        if let maxPriorityFeePerGas = toHexString(maxPriorityFeePerGas) { tx["maxPriorityFeePerGas"] = maxPriorityFeePerGas }
        if let maxFeePerGas = toHexString(maxFeePerGas) { tx["maxFeePerGas"] = maxFeePerGas }
        if let nonce = toHexString(nonce) { tx["nonce"] = nonce }
        if let type = type { tx["type"] = "0x" + String(type, radix: 16) }
        
        return tx
    }
}

// MARK: - Codable Implementation

extension EVMTransaction {
    private enum CodingKeys: String, CodingKey {
        case to, value, gasLimit, gasPrice, maxPriorityFeePerGas, maxFeePerGas
        case nonce, chainId, smartContractAbi, smartContractFunctionName
        case smartContractFunctionArgs, smartContractByteCode, type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Helper function to decode hex strings to BigUInt
        func decodeBigUInt(_ key: CodingKeys) throws -> BigUInt? {
            guard let hexString = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
            return BigUInt(hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString, radix: 16)
        }
        
        to = try container.decodeIfPresent(String.self, forKey: .to)
        value = try decodeBigUInt(.value)
        gasLimit = try decodeBigUInt(.gasLimit)
        gasPrice = try decodeBigUInt(.gasPrice)
        maxPriorityFeePerGas = try decodeBigUInt(.maxPriorityFeePerGas)
        maxFeePerGas = try decodeBigUInt(.maxFeePerGas)
        nonce = try decodeBigUInt(.nonce)
        chainId = try decodeBigUInt(.chainId)
        smartContractAbi = try container.decodeIfPresent(String.self, forKey: .smartContractAbi)
        smartContractFunctionName = try container.decodeIfPresent(String.self, forKey: .smartContractFunctionName)
        smartContractFunctionArgs = try container.decodeIfPresent([String].self, forKey: .smartContractFunctionArgs)
        smartContractByteCode = try container.decodeIfPresent(String.self, forKey: .smartContractByteCode)
        type = try container.decodeIfPresent(Int.self, forKey: .type)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Helper function to encode BigUInt as hex string
        func encode(_ value: BigUInt?, for key: CodingKeys) throws {
            if let value = value {
                try container.encode("0x" + String(value, radix: 16), forKey: key)
            }
        }
        
        try container.encodeIfPresent(to, forKey: .to)
        try encode(value, for: .value)
        try encode(gasLimit, for: .gasLimit)
        try encode(gasPrice, for: .gasPrice)
        try encode(maxPriorityFeePerGas, for: .maxPriorityFeePerGas)
        try encode(maxFeePerGas, for: .maxFeePerGas)
        try encode(nonce, for: .nonce)
        try encode(chainId, for: .chainId)
        try container.encodeIfPresent(smartContractAbi, forKey: .smartContractAbi)
        try container.encodeIfPresent(smartContractFunctionName, forKey: .smartContractFunctionName)
        try container.encodeIfPresent(smartContractFunctionArgs, forKey: .smartContractFunctionArgs)
        try container.encodeIfPresent(smartContractByteCode, forKey: .smartContractByteCode)
        try container.encodeIfPresent(type, forKey: .type)
    }
}

@available(iOS 16.4, *)
@MainActor
public class ParaEvmSigner: ObservableObject {
    private let paraManager: ParaManager
    private let rpcUrl: String
    
    public init(paraManager: ParaManager, rpcUrl: String, walletId: String?) throws {
        self.paraManager = paraManager
        self.rpcUrl = rpcUrl
        
        if let walletId {
            Task {
                try await selectWallet(walletId: walletId)
            }
        }
    }
    
    private func initEthersSigner(rpcUrl: String, walletId: String) async throws {
        let _ = try await paraManager.postMessage(method: "initEthersSigner", arguments: [walletId, rpcUrl])
    }
    
    public func selectWallet(walletId: String) async throws {
        try await initEthersSigner(rpcUrl: self.rpcUrl, walletId: walletId)
    }
    
    public func signMessage(message: String) async throws -> String {
        let result = try await paraManager.postMessage(method: "ethersSignMessage", arguments: [message])
        return try paraManager.decodeResult(result, expectedType: String.self, method: "ethersSignMessage")
    }
    
    public func signTransaction(transactionB64: String) async throws -> String {
        let result = try await paraManager.postMessage(method: "ethersSignTransaction", arguments: [transactionB64])
        return try paraManager.decodeResult(result, expectedType: String.self, method: "ethersSignTransaction")
    }
    
    public func sendTransaction(transactionB64: String) async throws -> Any {
        let result = try await paraManager.postMessage(method: "ethersSendTransaction", arguments: [transactionB64])
        return result!
    }
}
