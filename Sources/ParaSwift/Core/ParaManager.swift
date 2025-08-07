// swiftformat:disable:redundantSelf

import AuthenticationServices
import os
import SwiftUI
import WebKit

/// Manages Para wallet services including authentication, wallet management, and transaction signing.
///
/// This class provides a comprehensive interface for applications to interact with Para wallet services.
/// It handles authentication flows, wallet creation and management, and transaction signing operations.
@MainActor
public class ParaManager: NSObject, ObservableObject, ErrorTrackable {
    // MARK: - Properties

    /// Current package version.
    public static var packageVersion: String {
        ParaPackage.version
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
            passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
            
            // Reinitialize error reporting client when environment changes
            let apiBaseURL = deriveApiBaseURL(from: environment)
            errorReportingClient = ErrorReportingClient(baseURL: apiBaseURL, apiKey: apiKey, environment: environment.name)
        }
    }

    /// Indicates if the ParaManager is ready to receive requests.
    public var isReady: Bool {
        paraWebView.isReady
    }

    // MARK: - Internal Properties

    /// Logger for internal diagnostics.
    let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
    /// Internal passkeys manager for handling authentication.
    let passkeysManager: PasskeysManager
    /// Web view interface for communicating with Para services.
    let paraWebView: ParaWebView
    /// App scheme for authentication callbacks.
    let appScheme: String
    
    // MARK: - Error Reporting Properties
    
    /// Error reporting client for tracking SDK errors
    internal var errorReportingClient: ErrorReportingClient?
    
    /// Whether error tracking is enabled (always enabled - backend decides what to log)
    internal var isErrorTrackingEnabled: Bool {
        true
    }

    // MARK: - Initialization

    /// Creates a new Para manager instance.
    ///
    /// - Parameters:
    ///   - environment: The Para environment configuration.
    ///   - apiKey: Your Para API key.
    ///   - appScheme: Optional app scheme for authentication callbacks. Defaults to the app's bundle identifier.
    public init(environment: ParaEnvironment, apiKey: String, appScheme: String? = nil) {
        logger.info("ParaManager init: \(environment.name)")

        self.environment = environment
        self.apiKey = apiKey
        passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        paraWebView = ParaWebView(environment: environment, apiKey: apiKey)
        self.appScheme = appScheme ?? Bundle.main.bundleIdentifier!
        
        super.init()
        
        // Initialize error reporting client
        let apiBaseURL = deriveApiBaseURL(from: environment)
        errorReportingClient = ErrorReportingClient(baseURL: apiBaseURL, apiKey: apiKey, environment: environment.name)

        Task { @MainActor in
            await waitForParaReady()
        }
    }

    // MARK: - Internal Utilities & Bridge Communication

    /// Waits for the Para web view to be ready with a timeout
    private func waitForParaReady() async {
        let startTime = Date()
        let maxWaitDuration: TimeInterval = 30.0

        while !paraWebView.isReady && paraWebView.initializationError == nil && paraWebView.lastError == nil {
            let elapsed = Date().timeIntervalSince(startTime)

            if elapsed > maxWaitDuration {
                logger.error("WebView initialization timeout after \(elapsed) seconds")
                await MainActor.run {
                    self.objectWillChange.send()
                    self.sessionState = .inactive
                }
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if self.paraWebView.initializationError != nil || self.paraWebView.lastError != nil {
            logger.error("WebView initialization failed: \(self.paraWebView.initializationError?.localizedDescription ?? self.paraWebView.lastError?.localizedDescription ?? "unknown")")
            await MainActor.run {
                self.objectWillChange.send()
                self.sessionState = .inactive
            }
            return
        }

        if let active = try? await isSessionActive(), active {
            if let loggedIn = try? await isFullyLoggedIn(), loggedIn {
                logger.info("Session active and user logged in")
                await MainActor.run {
                    self.objectWillChange.send()
                    self.sessionState = .activeLoggedIn
                }
            } else {
                logger.info("Session active but user not fully logged in")
                await MainActor.run {
                    self.objectWillChange.send()
                    self.sessionState = .active
                }
            }
        } else {
            logger.info("Session not active")
            await MainActor.run {
                self.objectWillChange.send()
                self.sessionState = .inactive
            }
        }
    }

    /// Ensure that the web view is ready before sending messages
    func ensureWebViewReady() async throws {
        if !paraWebView.isReady {
            logger.debug("WebView not ready, waiting for initialization...")
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
    func postMessage(method: String, payload: Encodable) async throws -> Any? {
        logger.debug("Calling bridge method: \(method)")

        do {
            let result: Any? = try await self.paraWebView.postMessage(method: method, payload: payload)
            return result
        } catch {
            logger.error("Bridge error for \(method): \(error.localizedDescription)")
            throw error
        }
    }

    /// Decodes a result from the bridge to the expected type
    /// - Parameters:
    ///   - result: The result from the bridge
    ///   - expectedType: The expected type
    ///   - method: The method name for error reporting
    /// - Returns: The decoded result
    func decodeResult<T>(_ result: Any?, expectedType _: T.Type, method: String) throws -> T {
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
    func decodeDictionaryResult<T>(_ result: Any?, expectedType _: T.Type, method: String, key: String) throws -> T {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)
        guard let value = dict[key] as? T else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-\(key)>: Missing or invalid key result")
        }
        return value
    }

    // MARK: - Core Session Methods

    /// Manually check and update session state
    public func checkSessionState() async {
        await waitForParaReady()
    }

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
        sessionState = .inactive
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
              let userId = resultDict["userId"] as? String
        else {
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
            username: authInfoDict["username"] as? String,
        )
    }
    
    // MARK: - Error Reporting Support
    
    /// Derive API base URL from environment
    private func deriveApiBaseURL(from environment: ParaEnvironment) -> String {
        switch environment {
        case .dev:
            return "http://localhost:8080"
        case .sandbox:
            return "https://api.sandbox.getpara.com"
        case .beta:
            return "https://api.beta.getpara.com"
        case .prod:
            return "https://api.getpara.com"
        }
    }
    
    /// Get current user ID for error reporting context
    func getCurrentUserId() -> String? {
        // This is a synchronous version to avoid async complications in error tracking
        // Return the userId from the first wallet if available
        // All wallets for a user should have the same userId
        wallets.first?.userId
    }
}
