import Foundation

/// Receipt returned after a smart account transaction (or batch) is mined.
///
/// Mirrors the subset of viem's `TransactionReceipt` that the AA bridge serializes —
/// all numeric fields arrive as decimal strings so they can hold `uint256` values
/// without loss of precision.
public struct AATransactionReceipt: Codable, Equatable, Sendable {
    /// Hash of the mined transaction that executed the UserOperation.
    public let transactionHash: String

    /// Hash of the block containing the transaction.
    public let blockHash: String

    /// Block number containing the transaction (decimal string).
    public let blockNumber: String

    /// Address the transaction was sent from. For AA flows this is typically the bundler / EntryPoint.
    public let from: String

    /// Address the transaction was sent to. May be nil for contract-creation transactions.
    public let to: String?

    /// Execution status — `"success"` or `"reverted"`.
    public let status: String

    /// Gas used by the transaction (decimal string).
    public let gasUsed: String

    /// Effective gas price paid (decimal string, in wei).
    public let effectiveGasPrice: String

    public init(
        transactionHash: String,
        blockHash: String,
        blockNumber: String,
        from: String,
        to: String?,
        status: String,
        gasUsed: String,
        effectiveGasPrice: String
    ) {
        self.transactionHash = transactionHash
        self.blockHash = blockHash
        self.blockNumber = blockNumber
        self.from = from
        self.to = to
        self.status = status
        self.gasUsed = gasUsed
        self.effectiveGasPrice = effectiveGasPrice
    }
}

/// A single call inside a smart account batch transaction.
public struct SmartAccountCall: Encodable, Equatable, Sendable {
    /// Destination address.
    public let to: String

    /// Value in wei, as a decimal string. Omit for zero-value calls.
    public let value: String?

    /// Hex-encoded calldata (including `0x` prefix). Omit for plain transfers.
    public let data: String?

    public init(to: String, value: String? = nil, data: String? = nil) {
        self.to = to
        self.value = value
        self.data = data
    }
}
