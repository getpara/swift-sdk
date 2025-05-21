import SwiftUI
import AuthenticationServices
import WebKit
import os

@MainActor
/// Manages Para wallet services including authentication, wallet management, and transaction signing.
///
/// This class provides a comprehensive interface for applications to interact with Para wallet services.
/// It handles authentication flows, wallet creation and management, and transaction signing operations.
public class ParaManager: NSObject, ObservableObject {
    // MARK: - Properties
    /// Current package version.
    public static var packageVersion: String {
        return ParaPackage.version
    }
    /// Available Para wallets connected to this instance.
    @Published public var wallets: [Wallet] = []
    /// Current state of the Para Manager session.
    @Published public var sessionState: ParaSessionState = .unknown
    /// API key for Para services.
    public var apiKey: String
    /// Para environment configuration.
    public var environment: ParaEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    /// Indicates if the ParaManager is ready to receive requests.
    public var isReady: Bool {
        return paraWebView.isReady
    }
    // MARK: - Internal Properties
    /// Logger for internal diagnostics.
    internal let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
    /// Internal passkeys manager for handling authentication.
    internal let passkeysManager: PasskeysManager
    /// Web view interface for communicating with Para services.
    internal let paraWebView: ParaWebView
    /// Deep link for app authentication flows.
    internal let deepLink: String
    
    // MARK: - Initialization
    /// Creates a new Para manager instance.
    ///
    /// - Parameters:
    ///   - environment: The Para environment configuration.
    ///   - apiKey: Your Para API key.
    ///   - deepLink: Optional deep link for your application. Defaults to the app's bundle identifier.
    public init(environment: ParaEnvironment, apiKey: String, deepLink: String? = nil) {
        self.environment = environment
        self.apiKey = apiKey
        self.passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        self.paraWebView = ParaWebView(environment: environment, apiKey: apiKey)
        self.deepLink = deepLink ?? Bundle.main.bundleIdentifier!
        super.init()
        Task {
            await waitForParaReady()
        }
    }
    
    // MARK: - Internal Utilities & Bridge Communication
    
    /// Waits for the Para web view to be ready with a timeout
    private func waitForParaReady() async {
        let startTime = Date()
        let maxWaitDuration: TimeInterval = 30.0
        
        while !paraWebView.isReady && paraWebView.initializationError == nil && paraWebView.lastError == nil {
            if Date().timeIntervalSince(startTime) > maxWaitDuration {
                sessionState = .inactive
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if paraWebView.initializationError != nil || paraWebView.lastError != nil {
            sessionState = .inactive
            return
        }

        if let active = try? await isSessionActive(), active {
            if let loggedIn = try? await isFullyLoggedIn(), loggedIn {
                sessionState = .activeLoggedIn
            } else {
                sessionState = .active
            }
        } else {
            sessionState = .inactive
        }
    }
    
    /// Ensure that the web view is ready before sending messages
    func ensureWebViewReady() async throws {
        if !paraWebView.isReady {
            logger.debug("Waiting for WebView initialization...")
            await waitForParaReady()
            guard paraWebView.isReady else {
                throw ParaError.bridgeError("WebView failed to initialize")
            }
        }
    }
    
    /// Posts a message to the Para bridge
    /// - Parameters:
    ///   - method: The method name to call
    ///   - payload: The payload to pass
    /// - Returns: The response from the bridge
    internal func postMessage(method: String, payload: Encodable) async throws -> Any? {
        // Log payload as JSON string
        var payloadString: String = "<encoding error>"
        if let data: Data = try? JSONEncoder().encode(AnyEncodable(payload)),
           let jsonString: String = String(data: data, encoding: .utf8) {
            payloadString = jsonString
        }
        logger.debug("Posting message to bridge - Method: \(method), Payload: \(payloadString)")
        
        do {
            // Call the ParaWebView postMessage with payload
            let result: Any? = try await paraWebView.postMessage(method: method, payload: payload)
            logger.debug("Bridge response for method \(method): \(String(describing: result))")
            return result
        } catch {
            logger.error("Bridge error for method \(method): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Decodes a result from the bridge to the expected type
    /// - Parameters:
    ///   - result: The result from the bridge
    ///   - expectedType: The expected type
    ///   - method: The method name for error reporting
    /// - Returns: The decoded result
    internal func decodeResult<T>(_ result: Any?, expectedType: T.Type, method: String) throws -> T {
        guard let value = result as? T else {
            throw ParaError.bridgeError("METHOD_ERROR<\(method)>: Invalid result format expected \(T.self), but got \(String(describing: result))")
        }
        return value
    }
    
    /// Decodes a dictionary result from the bridge and extracts a specific key
    /// - Parameters:
    ///   - result: The result from the bridge
    ///   - expectedType: The expected type of the value
    ///   - method: The method name for error reporting
    ///   - key: The key to extract
    /// - Returns: The decoded value
    internal func decodeDictionaryResult<T>(_ result: Any?, expectedType: T.Type, method: String, key: String) throws -> T {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)
        guard let value = dict[key] as? T else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-\(key)>: Missing or invalid key result")
        }
        return value
    }
    
    // MARK: - Core Session Methods
    
    /// Check if the user is fully logged in
    /// - Returns: True if the user is fully logged in
    public func isFullyLoggedIn() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isFullyLoggedIn", payload: EmptyPayload())
        return try decodeResult(result, expectedType: Bool.self, method: "isFullyLoggedIn")
    }
    
    /// Check if the session is active
    /// - Returns: True if the session is active
    public func isSessionActive() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isSessionActive", payload: EmptyPayload())
        return try decodeResult(result, expectedType: Bool.self, method: "isSessionActive")
    }
    
    /// Export the current session for backup or transfer
    /// - Returns: Session data as a string
    public func exportSession() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "exportSession", payload: EmptyPayload())
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }
    
    /// Logs out the current user and clears all session data
    public func logout() async throws {
        _ = try await postMessage(method: "logout", payload: EmptyPayload())
        
        // Clear web data store
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        
        // Reset state
        wallets = []
        self.sessionState = .inactive
    }
    
    /// Gets the current user's persisted authentication details.
    ///
    /// - Returns: The current user's authentication state, or nil if no user is authenticated.
    /// - Note: The 'stage' will be set to 'login' for active sessions as this method retrieves
    ///         details from an already established session.
    public func getCurrentUserAuthDetails() async throws -> AuthState? {
        try await ensureWebViewReady()
        
        let result = try await postMessage(method: "getCurrentSessionDetails", payload: EmptyPayload())
        
        guard let resultDict = result as? [String: Any] else {
            return nil
        }
        
        guard let authInfoDict = resultDict["authInfo"] as? [String: Any],
              let userId = resultDict["userId"] as? String else {
            logger.debug("No authenticated session found")
            return nil
        }
        
        // Extract auth details from authInfoDict
        var email: String?
        var phone: String?
        
        if let auth = authInfoDict["auth"] as? [String: Any] {
            email = auth["email"] as? String
            phone = auth["phone"] as? String
        }
        
        // Create a synthetic AuthState with login stage
        return AuthState(
            stage: .login,
            userId: userId,
            email: email,
            phone: phone,
            displayName: authInfoDict["displayName"] as? String,
            pfpUrl: authInfoDict["pfpUrl"] as? String,
            username: authInfoDict["username"] as? String
        )
    }
}
