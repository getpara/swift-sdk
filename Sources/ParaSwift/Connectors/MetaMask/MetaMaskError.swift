import Foundation

/// Errors that can occur during MetaMask operations
public enum MetaMaskError: LocalizedError {
    case alreadyProcessing
    case invalidURL
    case invalidResponse
    case metaMaskError(code: Int, message: String)
    case notInstalled

    public var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            "Already processing a request"
        case .invalidURL:
            "Invalid URL construction"
        case .invalidResponse:
            "Invalid response from MetaMask"
        case let .metaMaskError(code, message):
            "MetaMask error (\(code)): \(message)"
        case .notInstalled:
            "MetaMask is not installed."
        }
    }

    /// Whether the error represents a user rejection
    public var isUserRejected: Bool {
        if case .metaMaskError(code: 4001, _) = self {
            return true
        }
        return false
    }
}
