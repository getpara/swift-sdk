//
//  File.swift
//  
//
//  Created by Brian Corbin on 6/4/24.
//

import Foundation

public enum WalletType: String {
    case evm = "EVM", solana = "SOLANA", cosmos = "COSMOS"
}

public struct Wallet {
    public let id: String
    public let userId: String?
    public let type: WalletType?
    public let pregenIdentifier: String?
    public let pregenIdentifierType: String?
    public let keyGenComplete: Bool?
    public let updatedAt: Date?
    public let partnerId: String?
    public let signer: String?
    public let address: String?
    public let scheme: String?
    public let publicKey: String?
    public let createdAt: Date?
    public let name: String?
    
    public init(id: String, signer: String?, address: String?, publicKey: String?) {
        self.id = id
        self.userId = nil
        self.type = nil
        self.pregenIdentifier = nil
        self.pregenIdentifierType = nil
        self.keyGenComplete = nil
        self.updatedAt = nil
        self.partnerId = nil
        self.signer = signer
        self.address = address
        self.scheme = nil
        self.publicKey = publicKey
        self.createdAt = nil
        self.name = nil
    }
    
    public init(result: [String: Any]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        id = result["id"]! as! String
        userId = result["userId"] as? String
        
        let typeString = result["type"] as? String
        type = typeString.flatMap(WalletType.init)
        pregenIdentifier = result["pregenIdentifier"] as? String
        pregenIdentifierType = result["pregenIdentifierType"] as? String
        keyGenComplete = result["keyGenComplete"] as? Bool
        let updatedAtString = result["updatedAt"] as? String
        updatedAt = updatedAtString != nil ? dateFormatter.date(from: updatedAtString!) : nil
        partnerId = result["partnerId"] as? String
        signer = result["signer"] as? String
        address = result["address"] as? String
        scheme = result["scheme"] as? String
        publicKey = result["publicKey"] as? String
        let createdAtString = result["createdAt"] as? String
        createdAt = createdAtString != nil ? dateFormatter.date(from: createdAtString!) : nil
        name = result["name"] as? String
    }
}
