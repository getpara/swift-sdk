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
            return "Already processing a request"
        case .invalidURL:
            return "Invalid URL construction"
        case .invalidResponse:
            return "Invalid response from MetaMask"
        case .metaMaskError(let code, let message):
            return "MetaMask error (\(code)): \(message)"
        case .notInstalled:
            return "MetaMask is not installed."
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
