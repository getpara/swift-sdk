import Foundation

/// Describes a smart (EIP-4337 / EIP-7702) account provisioned for a Para wallet via an
/// Account Abstraction provider such as Alchemy.
public struct SmartAccountInfo: Codable, Equatable, Sendable {
    /// Counterfactual address of the smart account. This is the address that sends
    /// transactions and holds funds — not the underlying EOA signer.
    public let smartAccountAddress: String

    /// Operational mode of the account. Currently `"4337"` (UserOperation) or `"7702"`
    /// (EIP-7702 delegated EOA).
    public let mode: String

    /// AA provider that created this account, e.g. `"ALCHEMY"`.
    public let provider: String

    /// EVM chain ID the smart account is deployed on.
    public let chainId: Int

    public init(smartAccountAddress: String, mode: String, provider: String, chainId: Int) {
        self.smartAccountAddress = smartAccountAddress
        self.mode = mode
        self.provider = provider
        self.chainId = chainId
    }
}
