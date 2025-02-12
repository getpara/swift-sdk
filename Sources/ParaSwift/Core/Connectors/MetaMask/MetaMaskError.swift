import Foundation

/// Errors that can occur during MetaMask operations
public enum MetaMaskError: LocalizedError {
    case alreadyProcessing
    case invalidURL
    case invalidResponse
    case metaMaskError(String)
    case notInstalled
    
    public var errorDescription: String? {
        switch self {
        case .alreadyProcessing:
            return "Already processing a request"
        case .invalidURL:
            return "Invalid URL construction"
        case .invalidResponse:
            return "Invalid response from MetaMask"
        case .metaMaskError(let message):
            return message
        case .notInstalled:
            return "MetaMask is not installed."
        }
    }
} 
