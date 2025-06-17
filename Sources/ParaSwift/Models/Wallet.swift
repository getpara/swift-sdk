//
//  Wallet.swift
//
//
//  Created by Brian Corbin on 6/4/24.
//

import Foundation

/// Types of wallets supported by Para
public enum WalletType: String {
    /// Ethereum Virtual Machine compatible wallet
    case evm = "EVM"
    /// Solana blockchain wallet
    case solana = "SOLANA"
    /// Cosmos blockchain wallet
    case cosmos = "COSMOS"
}

/// Represents a cryptocurrency wallet in the Para system
public struct Wallet {
    /// Unique identifier for the wallet
    public let id: String
    /// ID of the user who owns the wallet
    public let userId: String?
    /// Type of the wallet (EVM, Solana, Cosmos)
    public let type: WalletType?
    /// Identifier for pre-generated wallet
    public let pregenIdentifier: String?
    /// Type of pre-generated wallet identifier
    public let pregenIdentifierType: String?
    /// Whether key generation is complete
    public let keyGenComplete: Bool?
    /// Last update timestamp
    public let updatedAt: Date?
    /// ID of the partner associated with the wallet
    public let partnerId: String?
    /// Signer information for the wallet
    public let signer: String?
    /// Public address of the wallet
    public let address: String?
    /// Secondary address (e.g., Cosmos bech32 address for Cosmos wallets)
    public let addressSecondary: String?
    /// Scheme used by the wallet
    public let scheme: String?
    /// Public key of the wallet
    public let publicKey: String?
    /// Creation timestamp
    public let createdAt: Date?
    /// Name of the wallet
    public let name: String?

    /// Creates a new wallet with basic information
    /// - Parameters:
    ///   - id: Unique identifier for the wallet
    ///   - signer: Signer information for the wallet
    ///   - address: Public address of the wallet
    ///   - publicKey: Public key of the wallet
    public init(id: String, signer: String?, address: String?, publicKey: String?) {
        self.id = id
        userId = nil
        type = nil
        pregenIdentifier = nil
        pregenIdentifierType = nil
        keyGenComplete = nil
        updatedAt = nil
        partnerId = nil
        self.signer = signer
        self.address = address
        addressSecondary = nil
        scheme = nil
        self.publicKey = publicKey
        createdAt = nil
        name = nil
    }

    /// Creates a wallet from a dictionary of values
    /// - Parameter result: Dictionary containing wallet information
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
        addressSecondary = result["addressSecondary"] as? String
        scheme = result["scheme"] as? String
        publicKey = result["publicKey"] as? String
        let createdAtString = result["createdAt"] as? String
        createdAt = createdAtString != nil ? dateFormatter.date(from: createdAtString!) : nil
        name = result["name"] as? String
    }
}
