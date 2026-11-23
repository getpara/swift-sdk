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

    /// The JSON-RPC id of the request this reply answers, when MetaMask sent one
    let id: String?
    /// Optional error message from MetaMask
    let error: ErrorResponse?
    /// Optional successful result from MetaMask
    let result: T?

    private enum CodingKeys: String, CodingKey {
        case id, error, result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Request ids are always strings here; any other type cannot match a pending request.
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        error = try container.decodeIfPresent(ErrorResponse.self, forKey: .error)
        result = try container.decodeIfPresent(T.self, forKey: .result)
    }
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

/// The parts of a MetaMask reply needed to decide whether it answers the pending request.
struct MetaMaskReplyHeader: Decodable {
    struct Data: Decodable {
        let id: String?
        let hasError: Bool
        let hasResult: Bool

        private enum CodingKeys: String, CodingKey {
            case id, error, result
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            hasError = try container.contains(.error) && !container.decodeNil(forKey: .error)
            hasResult = try container.contains(.result) && !container.decodeNil(forKey: .result)
        }
    }

    let data: Data
}
