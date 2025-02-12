import Foundation

/// Represents the type of message being sent to/from MetaMask
public enum MetaMaskMessageType {
    case connect
    case signMessage
    case sendTransaction
}

/// Base response structure from MetaMask
struct MetaMaskResponse<T: Codable>: Codable {
    /// The response data containing either a result or an error
    let data: MetaMaskResponseData<T>
}

/// Data container for MetaMask responses
struct MetaMaskResponseData<T: Codable>: Codable {
    struct ErrorResponse: Codable {
        let code: Int
        let message: String
    }
    
    /// Optional error message from MetaMask
    let error: ErrorResponse?
    /// Optional successful result from MetaMask
    let result: T?
}

/// Connect response from MetaMask
struct ConnectResponse: Codable {
    /// The connection data containing chain ID and accounts
    struct Data: Codable {
        /// The connected chain ID (e.g., "0x1" for Ethereum mainnet)
        let chainId: String
        /// Array of connected account addresses
        let accounts: [String]
    }
    let data: Data
} 