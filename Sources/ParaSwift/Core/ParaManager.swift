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
public class ParaManager: NSObject, ObservableObject {
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
    public var apiKey: String {
        didSet {
            sessionPersistence.update(environment: environment, apiKey: apiKey)
        }
    }
    /// Para environment configuration.
    public var environment: ParaEnvironment {
        didSet {
            passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
            sessionPersistence.update(environment: environment, apiKey: apiKey)
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
    /// Track whether transmission keyshares have been loaded for the current session.
    /// This prevents unnecessary repeated calls to loadTransmissionKeyshares.
    internal var transmissionKeysharesLoaded = false
    /// Default web authentication session used for hosted auth flows.
    internal var defaultWebAuthenticationSession: WebAuthenticationSession?
    /// Controller responsible for persisting session snapshots.
    private var sessionPersistence: SessionPersistenceStoring
    /// Last serialized session we saved locally to avoid redundant writes.
    private var lastPersistedSession: String?
    /// Tracks whether we already attempted to restore a stored session.
    private var attemptedSessionRestore = false
    
    // MARK: - Initialization

    /// Creates a new Para manager instance.
    ///
    /// - Parameters:
    ///   - environment: The Para environment configuration.
    ///   - apiKey: Your Para API key.
    ///   - appScheme: Optional app scheme for authentication callbacks. Defaults to the app's bundle identifier.
    ///   - sessionPersistence: Optional persistence controller for session snapshots.
    public init(
        environment: ParaEnvironment,
        apiKey: String,
        appScheme: String? = nil
    ) {
        logger.info("ParaManager init: \(environment.name)")

        self.environment = environment
        self.apiKey = apiKey
        passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        paraWebView = ParaWebView(environment: environment, apiKey: apiKey)
        self.appScheme = appScheme ?? Bundle.main.bundleIdentifier!
        self.sessionPersistence = SessionPersistenceController()
        
        super.init()

        self.sessionPersistence.update(environment: environment, apiKey: apiKey)

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

        if !attemptedSessionRestore {
            attemptedSessionRestore = true
            if await restorePersistedSession() {
                return
            }
        }

        if let active = try? await isSessionActive(), active {
            if let loggedIn = try? await isFullyLoggedIn(), loggedIn {
                logger.info("Session active and user logged in")
                await MainActor.run {
                    self.objectWillChange.send()
                    self.sessionState = .activeLoggedIn
                }
                await persistCurrentSession(reason: "waitForParaReady-activeLoggedIn")
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
            lastPersistedSession = nil
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

    // MARK: - Configuration

    /// Sets the default web authentication session to use for hosted Para auth flows.
    ///
    /// - Parameter session: The session instance to store. Pass `nil` to clear.
    public func setDefaultWebAuthenticationSession(_ session: WebAuthenticationSession?) {
        defaultWebAuthenticationSession = session
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
        } catch let error as ParaWebViewError {
            logger.error("Bridge error for \(method): \(error.localizedDescription)")
            // Convert ParaWebViewError to ParaError for better user experience
            switch error {
            case .bridgeError(let message):
                // Attempt to extract a concise message from a JSON payload produced by the bridge
                if let data = message.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let details = json["details"] as? [String: Any]
                    let userMessage = (details?["message"] as? String)
                        ?? (json["message"] as? String)
                        ?? message
                    throw ParaError.bridgeError(userMessage)
                }
                throw ParaError.bridgeError(message)
            case .webViewNotReady:
                throw ParaError.bridgeError("WebView is not ready")
            case .requestTimeout:
                throw ParaError.bridgeTimeoutError
            case .invalidArguments(let message):
                throw ParaError.error("Invalid arguments: \(message)")
            }
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

    /// Attempts to refresh the server-side session cookie without reauthenticating.
    /// - Returns: `true` when the session was refreshed successfully.
    public func keepSessionAlive() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "keepSessionAlive", payload: EmptyPayload())

        if let boolResult = result as? Bool {
            return boolResult
        }

        if let numberResult = result as? NSNumber {
            return numberResult.boolValue
        }

        if let stringResult = result as? String {
            let normalized = stringResult.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1"].contains(normalized) {
                return true
            }
            if ["false", "0"].contains(normalized) {
                return false
            }
        }

        logger.error("Unexpected keepSessionAlive response: \(String(describing: result))")
        throw ParaError.bridgeError("Invalid keepSessionAlive response")
    }

    private struct ExportSessionArgs: Encodable {
        let excludeSigners: Bool
    }

    /// Export the current session for backup or transfer
    /// - Returns: Session data as a string
    public func exportSession(excludeSigners: Bool = false) async throws -> String {
        try await ensureWebViewReady()
        let payload = ExportSessionArgs(excludeSigners: excludeSigners)
        let result = try await postMessage(method: "exportSession", payload: payload)
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }

    /// Imports a previously exported session.
    /// - Parameter serializedSession: The base64-encoded session payload.
    public func importSession(_ serializedSession: String) async throws {
        let trimmed = serializedSession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParaError.error("Serialized session cannot be empty")
        }

        try await ensureWebViewReady()
        _ = try await postMessage(method: "importSession", payload: trimmed)

        transmissionKeysharesLoaded = false
        do {
            try await ensureTransmissionKeysharesLoaded()
        } catch {
            logger.warning("Failed to reload transmission keyshares after import: \(error.localizedDescription)")
        }

        lastPersistedSession = trimmed
    }

    /// Restores a session snapshot from persistence if it exists.
    /// - Returns: `true` when a snapshot was found and imported successfully.
    @discardableResult
    public func restorePersistedSession(refreshSession: Bool = true) async -> Bool {
        sessionState = .restoring

        do {
            guard let snapshot = try await sessionPersistence.load() else {
                logger.debug("No persisted session snapshot to restore")
                sessionState = .inactive
                return false
            }

            guard snapshot.environmentName == environment.name, snapshot.apiKey == apiKey else {
                logger.warning("Persisted session metadata mismatch; clearing snapshot")
                try? await sessionPersistence.clear()
                sessionState = .inactive
                return false
            }

            do {
                try await importSession(snapshot.session)
            } catch {
                logger.error("Failed to import persisted session: \(error.localizedDescription)")
                try? await sessionPersistence.clear()
                sessionState = .inactive
                return false
            }

            if refreshSession {
                do {
                    _ = try await touchSession()
                } catch {
                    logger.warning("touchSession failed during restore: \(error.localizedDescription)")
                }
            }

            var restoredAuthState: AuthState?
            if let details = try? await getCurrentUserAuthDetails() {
                restoredAuthState = details
            }

            do {
                let restoredWallets = try await fetchWallets()
                wallets = restoredWallets
            } catch {
                logger.warning("Fetching wallets after restore failed: \(error.localizedDescription)")
            }

            let isLoggedIn: Bool
            if restoredAuthState?.userId != nil {
                isLoggedIn = true
            } else if let fullyLoggedIn = try? await isFullyLoggedIn(), fullyLoggedIn {
                isLoggedIn = true
            } else {
                isLoggedIn = false
            }

            sessionState = isLoggedIn ? .activeLoggedIn : .active
            lastPersistedSession = snapshot.session
            logger.info("Session restored from persistence")
            await persistCurrentSession(reason: "restorePersistedSession")
            return true
        } catch SessionPersistenceError.misconfigured {
            logger.warning("Session persistence misconfigured; skipping restore")
        } catch SessionPersistenceError.keychainError(let status) {
            logger.error("Keychain error during session restore: \(status, privacy: .public)")
        } catch SessionPersistenceError.decoding(let error) {
            logger.error("Failed to decode persisted session: \(error.localizedDescription, privacy: .public)")
        } catch {
            logger.error("Unexpected restore error: \(error.localizedDescription, privacy: .public)")
        }

        sessionState = .inactive
        return false
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
        // Reset transmission keyshares flag since we're logging out
        transmissionKeysharesLoaded = false
        lastPersistedSession = nil
        try? await sessionPersistence.clear()
    }

    /// Persists the current session snapshot if it differs from the last saved copy.
    func persistCurrentSession(reason: String) async {
        guard paraWebView.isReady else {
            logger.debug("Skipping session persist (\(reason)) - web view not ready")
            return
        }

        do {
            let serializedSession = try await exportSession()
            if serializedSession == lastPersistedSession {
                logger.debug("Skipping session persist (\(reason)) - snapshot unchanged")
                return
            }

            var userId: String?
            if let authDetails = try? await getCurrentUserAuthDetails() {
                userId = authDetails.userId
            }

            let snapshot = SessionSnapshot(
                session: serializedSession,
                savedAt: Date(),
                environmentName: environment.name,
                apiKey: apiKey,
                userId: userId
            )

            try await sessionPersistence.save(snapshot: snapshot)
            lastPersistedSession = serializedSession
            logger.debug("Session snapshot persisted (\(reason))")
        } catch {
            logger.error("Failed to persist session (\(reason)): \(error.localizedDescription)")
        }
    }
    
    /// Ensures transmission keyshares are loaded for the current session.
    /// This is automatically called by wallet-related operations to ensure
    /// wallet signers are properly loaded from the backend.
    /// - Note: This method is idempotent and tracks whether keyshares have already been loaded.
    internal func ensureTransmissionKeysharesLoaded() async throws {
        // Skip if already loaded in this session
        if transmissionKeysharesLoaded {
            logger.debug("Transmission keyshares already loaded, skipping.")
            return
        }
        
        logger.debug("Loading transmission keyshares for the first time in this session...")
        
        do {
            // This method is defined in ParaManager+Auth.swift
            let sharesLoaded = try await loadTransmissionKeyshares()
            transmissionKeysharesLoaded = true
            logger.debug("Successfully loaded \(sharesLoaded) transmission keyshares.")
        } catch {
            // Log the error but don't mark as loaded so it can be retried
            logger.error("Failed to load transmission keyshares: \(error.localizedDescription)")
            // Re-throw the error to let the caller handle it
            throw error
        }
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
}
