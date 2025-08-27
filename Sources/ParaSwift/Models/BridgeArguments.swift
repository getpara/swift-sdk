import Foundation

struct GeneratePasskeyArgs: Encodable {
    let attestationObject: String // Base64 encoded
    let clientDataJson: String // Base64 encoded
    let credentialsId: String
    let userHandle: String // Base64 encoded
    let biometricsId: String
}

struct VerifyWebChallengeArgs: Encodable {
    let publicKey: String
    let authenticatorData: String // Base64 encoded
    let clientDataJSON: String // Base64 encoded
    let signature: String // Base64 encoded
}

struct LoginWithPasskeyArgs: Encodable {
    let userId: String
    let credentialsId: String
    let userHandle: String // Base64 encoded
}

struct GetWebChallengeArgs: Encodable {
    // Optional because it can be called without authInfo
    let email: String?
    let phone: String?
}

struct VerifyNewAccountArgs: Encodable {
    let verificationCode: String
}

struct CreateWalletArgs: Encodable {
    let type: String // Use WalletType.rawValue
    let skipDistributable: Bool
}

struct CreateWalletPerTypeArgs: Encodable {
    let types: [String]?
    let skipDistribute: Bool?
    
    init(types: [String]? = nil, skipDistribute: Bool? = nil) {
        self.types = types
        self.skipDistribute = skipDistribute
    }
}

// Renaming existing Params structs for consistency
struct SignMessageArgs: Encodable {
    let walletId: String
    let messageBase64: String
    let timeoutMs: Int?
}

struct SignTransactionArgs: Encodable {
    let walletId: String
    let rlpEncodedTxBase64: String
    let chainId: String
    let timeoutMs: Int?
}

// Signer-specific arguments removed - using unified API

struct DistributeNewWalletShareArgs: Encodable {
    let walletId: String
    let userShare: String
}

// Cosmos-specific arguments removed - using unified API

// Keep only the generic display address args that might be used elsewhere
struct GetDisplayAddressArgs: Encodable {
    let walletId: String
    let addressType: String
    let cosmosPrefix: String?
}
