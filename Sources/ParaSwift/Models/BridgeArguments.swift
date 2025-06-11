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

// Solana bridge arguments
struct SolanaSignerInitArgs: Encodable {
    let walletId: String
    let rpcUrl: String
}

struct SolanaSignTransactionArgs: Encodable {
    let b64EncodedTx: String
}

struct SolanaSignVersionedTransactionArgs: Encodable {
    let b64EncodedTx: String
}

struct SolanaSendTransactionArgs: Encodable {
    let b64EncodedTx: String
}

struct DistributeNewWalletShareArgs: Encodable {
    let walletId: String
    let userShare: String
}

// Cosmos bridge arguments
struct CosmosSignerInitArgs: Encodable {
    let walletId: String
    let prefix: String
    let messageSigningTimeoutMs: Int?
}

struct GetDisplayAddressArgs: Encodable {
    let walletId: String
    let addressType: String
    let cosmosPrefix: String?
}

// Cosmos signing arguments for low-level bridge methods
// Note: "Direct" == "Proto" signing in CosmJS terminology
struct CosmJsSignDirectArgs: Encodable {
    let signerAddress: String
    let signDocBase64: String
}

struct CosmJsSignAminoArgs: Encodable {
    let signerAddress: String
    let signDocBase64: String
}
