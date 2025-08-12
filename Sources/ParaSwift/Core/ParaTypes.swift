import Foundation

/// Current package version.
public enum ParaPackage {
    /// Package version of the Swift SDK
    public static let version = "2.0.0"
}

/// Specifies the intended authentication method.
public enum AuthMethod {
    case passkey
    case password
}

/// Context information for Para operations
public struct ParaErrorContext: Codable {
    public let operation: String
    public let chainId: String?
    public let walletType: String?
    public let method: String?

    public init(operation: String, chainId: String? = nil, walletType: String? = nil, method: String? = nil) {
        self.operation = operation
        self.chainId = chainId
        self.walletType = walletType
        self.method = method
    }
}

/// Structured bridge error from Para bridge-v2
public struct ParaBridgeError: Codable {
    public let code: String
    public let message: String
    public let userMessage: String?
    public let context: ParaErrorContext
    public let retryable: Bool

    public init(code: String, message: String, userMessage: String? = nil, context: ParaErrorContext, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.userMessage = userMessage
        self.context = context
        self.retryable = retryable
    }

    /// Returns the user message if available, otherwise the technical message
    public var displayMessage: String {
        return userMessage ?? message
    }
}

/// Errors that can occur during Para operations.
public enum ParaError: Error, CustomStringConvertible {
    /// Authentication-related errors (passkey, password, OAuth)
    case authenticationError(ParaBridgeError)
    /// Wallet operation errors (connection, initialization)
    case walletError(ParaBridgeError)
    /// Signing operation errors (transaction signing, message signing)
    case signingError(ParaBridgeError)
    /// Network-related errors (RPC, connectivity)
    case networkError(ParaBridgeError)
    /// Bridge communication errors with structured context
    case bridgeError(ParaBridgeError)
    /// Legacy bridge error (for backward compatibility)
    case legacyBridgeError(String)
    /// The JavaScript bridge did not respond in time
    case bridgeTimeoutError
    /// A general error occurred
    case error(String)
    /// Feature not implemented yet
    case notImplemented(String)

    public var description: String {
        switch self {
        case let .authenticationError(bridgeError):
            formatStructuredError(bridgeError, prefix: "Authentication failed")
        case let .walletError(bridgeError):
            formatStructuredError(bridgeError, prefix: "Wallet operation failed")
        case let .signingError(bridgeError):
            formatStructuredError(bridgeError, prefix: "Signing operation failed")
        case let .networkError(bridgeError):
            formatStructuredError(bridgeError, prefix: "Network error")
        case let .bridgeError(bridgeError):
            formatStructuredError(bridgeError, prefix: "Bridge error")
        case let .legacyBridgeError(info):
            "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            "The javascript bridge did not respond in time and the continuation has been cancelled."
        case let .error(info):
            "An error occurred: \(info)"
        case let .notImplemented(feature):
            "Feature not implemented: \(feature)"
        }
    }

    /// User-friendly error message for display to end users
    public var userMessage: String {
        switch self {
        case let .authenticationError(bridgeError),
             let .walletError(bridgeError),
             let .signingError(bridgeError),
             let .networkError(bridgeError),
             let .bridgeError(bridgeError):
            bridgeError.displayMessage
        case let .legacyBridgeError(info):
            "An error occurred: \(info)"
        case .bridgeTimeoutError:
            "The request timed out. Please try again."
        case let .error(info):
            "An error occurred: \(info)"
        case let .notImplemented(feature):
            "Feature not available: \(feature)"
        }
    }

    /// Error code for structured errors
    public var errorCode: String? {
        switch self {
        case let .authenticationError(bridgeError),
             let .walletError(bridgeError),
             let .signingError(bridgeError),
             let .networkError(bridgeError),
             let .bridgeError(bridgeError):
            bridgeError.code
        case .bridgeTimeoutError:
            "BRIDGE_TIMEOUT"
        default:
            nil
        }
    }

    /// Whether the operation can be retried
    public var isRetryable: Bool {
        switch self {
        case let .authenticationError(bridgeError),
             let .walletError(bridgeError),
             let .signingError(bridgeError),
             let .networkError(bridgeError),
             let .bridgeError(bridgeError):
            bridgeError.retryable
        case .bridgeTimeoutError:
            true
        default:
            false
        }
    }

    /// Operation context for structured errors
    public var context: ParaErrorContext? {
        switch self {
        case let .authenticationError(bridgeError),
             let .walletError(bridgeError),
             let .signingError(bridgeError),
             let .networkError(bridgeError),
             let .bridgeError(bridgeError):
            bridgeError.context
        default:
            nil
        }
    }

    private func formatStructuredError(_ bridgeError: ParaBridgeError, prefix: String) -> String {
        var components: [String] = [prefix]

        // Add operation context
        if let chainId = bridgeError.context.chainId {
            let chainName = formatChainName(chainId)
            components.append("on \(chainName)")
        }

        if let walletType = bridgeError.context.walletType {
            components.append("(\(walletType) wallet)")
        }

        // Add error details
        components.append("- Error: \(bridgeError.code)")
        components.append("- Reason: \(bridgeError.displayMessage)")

        if bridgeError.retryable {
            components.append("- Suggestion: Please try again")
        }

        return components.joined(separator: " ")
    }

    private func formatChainName(_ chainId: String) -> String {
        switch chainId {
        case "1": "Ethereum mainnet"
        case "137": "Polygon"
        case "56": "BNB Chain"
        case "43114": "Avalanche"
        case "42161": "Arbitrum One"
        case "10": "Optimism"
        case "8453": "Base"
        case "solana-mainnet": "Solana mainnet"
        case "solana-devnet": "Solana devnet"
        case "cosmoshub-4": "Cosmos Hub"
        case "osmosis-1": "Osmosis"
        default: "chain \(chainId)"
        }
    }
}

/// Response type for 2FA setup operation
public enum TwoFactorSetupResponse {
    /// 2FA is already set up
    case alreadySetup
    /// 2FA needs to be set up, contains the URI for configuration
    case needsSetup(uri: String)
}
