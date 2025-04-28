import Foundation

struct GeneratePasskeyArgs: Encodable {
    let attestationObject: String // Base64 encoded
    let clientDataJson: String    // Base64 encoded
    let credentialsId: String
    let userHandle: String        // Base64 encoded
    let biometricsId: String
}

struct VerifyWebChallengeArgs: Encodable {
    let publicKey: String
    let authenticatorData: String // Base64 encoded
    let clientDataJSON: String    // Base64 encoded
    let signature: String         // Base64 encoded
}

struct LoginWithPasskeyArgs: Encodable {
    let userId: String
    let credentialsId: String
    let userHandle: String        // Base64 encoded
}

struct GetWebChallengeArgs: Encodable {
    // Optional because it can be called without authInfo
    let email: String?
}

struct VerifyNewAccountArgs: Encodable {
    let verificationCode: String
}

struct CreateWalletArgs: Encodable {
    let type: String // Use WalletType.rawValue
    let skipDistributable: Bool
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

// For Signers
struct EthersSignerInitArgs: Encodable {
    let walletId: String
    let providerUrl: String // Matches bridge name
}

struct EthersSignMessageArgs: Encodable {
    let message: String
}

struct EthersSignTransactionArgs: Encodable {
    let b64EncodedTx: String
}

struct EthersSendTransactionArgs: Encodable {
     let b64EncodedTx: String
}

struct DistributeNewWalletShareArgs: Encodable {
    let walletId: String
    let userShare: String
}

// TODO: Add any other structs needed for methods like setEmail, cosmJs*, solana* based on the bridge types.
// For example:
// struct SetEmailArgs: Encodable {
//     let email: String
// } 