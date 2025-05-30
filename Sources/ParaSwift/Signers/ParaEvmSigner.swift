//
//  ParaEvmSigner.swift
//  ParaSwift
//
//  Created by Brian Corbin on 2/5/25.
//

import Foundation

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
        let args = EthersSignerInitArgs(walletId: walletId, providerUrl: rpcUrl)
        let _ = try await paraManager.postMessage(method: "initEthersSigner", payload: args)
    }
    
    public func selectWallet(walletId: String) async throws {
        try await initEthersSigner(rpcUrl: self.rpcUrl, walletId: walletId)
    }
    
    public func signMessage(message: String) async throws -> String {
        let args = EthersSignMessageArgs(message: message)
        let result = try await paraManager.postMessage(method: "ethersSignMessage", payload: args)
        return try paraManager.decodeResult(result, expectedType: String.self, method: "ethersSignMessage")
    }
    
    public func signTransaction(transactionB64: String) async throws -> String {
        let args = EthersSignTransactionArgs(b64EncodedTx: transactionB64)
        let result = try await paraManager.postMessage(method: "ethersSignTransaction", payload: args)
        return try paraManager.decodeResult(result, expectedType: String.self, method: "ethersSignTransaction")
    }
    
    public func sendTransaction(transactionB64: String) async throws -> Any {
        let args = EthersSendTransactionArgs(b64EncodedTx: transactionB64)
        let result = try await paraManager.postMessage(method: "ethersSendTransaction", payload: args)
        return result!
    }
}
