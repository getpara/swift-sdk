// swiftformat:disable:redundantSelf

import os
import SwiftUI
import WebKit

/// Structured error payload returned by the Para JavaScript bridge.
public struct ParaBridgeErrorPayload: Error, LocalizedError, CustomStringConvertible, Codable, Equatable, Sendable {
    public let message: String
    public let code: String?
    public let status: Int?
    public let details: BridgeJSONValue?

    public init(
        message: String,
        code: String? = nil,
        status: Int? = nil,
        details: BridgeJSONValue? = nil
    ) {
        self.message = message
        self.code = code
        self.status = status
        self.details = details
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case code
        case status
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        status = try container.decodeIfPresent(Int.self, forKey: .status)
        details = try container.decodeIfPresent(BridgeJSONValue.self, forKey: .details)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(code, forKey: .code)
        try container.encodeIfPresent(status, forKey: .status)
        if let details {
            try container.encode(UnvalidatedBridgeJSONValue(value: details), forKey: .details)
        }
    }

    public var formattedMessage: String {
        let nonEmptyCode = code.flatMap { $0.isEmpty ? nil : $0 }
        switch (nonEmptyCode, status) {
        case let (code?, status?):
            return "\(message) (code: \(code), status: \(status))"
        case let (code?, nil):
            return "\(message) (code: \(code))"
        case let (nil, status?):
            return "\(message) (status: \(status))"
        case (nil, nil):
            return message
        }
    }

    public var errorDescription: String? {
        formattedMessage
    }

    public var description: String {
        formattedMessage
    }
}

final class OnRampEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ParaOnRampEvent>.Continuation] = [:]

    func makeStream() -> AsyncStream<ParaOnRampEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    func emit(_ event: ParaOnRampEvent) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        for continuation in active {
            continuation.yield(event)
        }
    }

    func finishAll() {
        lock.lock()
        let active = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in active {
            continuation.finish()
        }
    }

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
}

final class PendingBridgeRequestStore: @unchecked Sendable {
    struct Entry {
        let continuation: CheckedContinuation<Any?, Error>
        let timeoutTask: Task<Void, Never>?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    var ids: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.keys)
    }

    func insert(_ entry: Entry, forKey key: String) {
        lock.lock()
        entries[key] = entry
        lock.unlock()
    }

    func removeValue(forKey key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.removeValue(forKey: key)
    }

    func drainAll() -> [Entry] {
        lock.lock()
        let all = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        return all
    }
}

/// A WebView implementation for Para that handles communication between Swift and JavaScript
/// This class manages the WebView lifecycle, message passing, and error handling for the Para SDK
@MainActor
public class ParaWebView: NSObject, ObservableObject {
    /// Indicates whether the WebView is ready to accept requests
    @Published public private(set) var isReady: Bool = false

    /// The error that occurred during initialization, if any
    @Published public var initializationError: Error?

    /// The last error that occurred during WebView operations
    @Published public var lastError: Error?

    /// Structured payload of the most recent bridge error for callers that inspect `code` or `details`
    var lastBridgeErrorPayload: ParaBridgeErrorPayload?

    /// The Para environment configuration
    public var environment: ParaEnvironment

    /// The API key for Para services
    public var apiKey: String

    /// The current package version of the SDK
    public static var packageVersion: String {
        ParaPackage.version
    }

    /// Stream of unsolicited on-ramp events emitted by the bridge.
    public nonisolated var onRampEvents: AsyncStream<ParaOnRampEvent> {
        onRampEventBroadcaster.makeStream()
    }

    private let webView: WKWebView
    private let requestTimeout: TimeInterval

    private nonisolated let pendingRequestStore = PendingBridgeRequestStore()
    private var isParaInitialized = false
    nonisolated let onRampEventBroadcaster = OnRampEventBroadcaster()

    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaWebView")

    nonisolated var pendingRequestIds: [String] {
        pendingRequestStore.ids
    }

    nonisolated var activeOnRampEventSubscriberCount: Int {
        onRampEventBroadcaster.subscriberCount
    }

    var javascriptEvaluator: ((String, @escaping (Any?, Error?) -> Void) -> Void)?

    func insertPendingRequestForTesting(
        id: String,
        continuation: CheckedContinuation<Any?, Error>,
        timeoutTask: Task<Void, Never>?
    ) {
        pendingRequestStore.insert(.init(continuation: continuation, timeoutTask: timeoutTask), forKey: id)
    }

    deinit {
        onRampEventBroadcaster.finishAll()
        for entry in pendingRequestStore.drainAll() {
            entry.timeoutTask?.cancel()
            entry.continuation.resume(throwing: ParaWebViewError.bridgeError("ParaWebView deallocated before response arrived"))
        }
    }

    /// Creates a new ParaWebView instance
    /// - Parameters:
    ///   - environment: The Para environment configuration
    ///   - apiKey: The API key for Para services
    ///   - requestTimeout: The timeout duration for requests in seconds (default: 120.0, accommodates AA UserOp inclusion)
    public init(environment: ParaEnvironment, apiKey: String, requestTimeout: TimeInterval = 120.0) {
        logger.info("ParaWebView init: \(environment.name), bridge: \(environment.jsBridgeUrl.absoluteString)")

        self.environment = environment
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout

        let config = WKWebViewConfiguration()

        if #available(iOS 17.0, *) {
            config.preferences.inactiveSchedulingPolicy = .none
        }

        let userContentController = WKUserContentController()
        config.userContentController = userContentController
        self.webView = WKWebView(frame: .zero, configuration: config)

        webView.isInspectable = true

        super.init()

        userContentController.add(LeakAvoider(delegate: self), name: "callback")

        // Add console logging support
        let consoleScript = """
        (function() {
            if (window.__paraConsoleBridgeInstalled) {
                return;
            }
            window.__paraConsoleBridgeInstalled = true;

            const serializeArg = (arg) => {
                if (arg instanceof Error) {
                    const errorPayload = {
                        name: arg.name,
                        message: arg.message,
                        stack: arg.stack
                    };
                    try {
                        const enumerableKeys = Object.keys(arg);
                        for (const key of enumerableKeys) {
                            if (!(key in errorPayload)) {
                                errorPayload[key] = arg[key];
                            }
                        }
                    } catch (_) {}
                    return JSON.stringify(errorPayload, null, 2);
                }

                if (typeof arg === 'object' && arg !== null) {
                    try {
                        return JSON.stringify(arg, null, 2);
                    } catch (_) {
                        return Object.prototype.toString.call(arg);
                    }
                }

                return String(arg);
            };

            const sendToNative = (level, args) => {
                const formatted = Array.from(args).map(serializeArg).join(' ');
                const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.console;
                if (handler && typeof handler.postMessage === 'function') {
                    handler.postMessage({
                        level,
                        message: formatted
                    });
                }
            };

            const originalMethods = {
                log: console.originalLog || (console.log ? console.log.bind(console) : function() {}),
                info: console.originalInfo || (console.info ? console.info.bind(console) : (console.log ? console.log.bind(console) : function() {})),
                debug: console.originalDebug || (console.debug ? console.debug.bind(console) : (console.log ? console.log.bind(console) : function() {})),
                warn: console.originalWarn || (console.warn ? console.warn.bind(console) : (console.log ? console.log.bind(console) : function() {})),
                error: console.originalError || (console.error ? console.error.bind(console) : (console.log ? console.log.bind(console) : function() {}))
            };

            console.originalLog = originalMethods.log;
            console.originalInfo = originalMethods.info;
            console.originalDebug = originalMethods.debug;
            console.originalWarn = originalMethods.warn;
            console.originalError = originalMethods.error;

            const wrapConsole = (method, level) => {
                const original = originalMethods[method];
                console[method] = function(...args) {
                    original(...args);
                    sendToNative(level, args);
                };
            };

            wrapConsole('log', 'log');
            wrapConsole('info', 'info');
            wrapConsole('debug', 'debug');
            wrapConsole('warn', 'warn');
            wrapConsole('error', 'error');

            window.addEventListener('error', (e) => {
                console.error('JavaScript Error:', {
                    message: e.message,
                    filename: e.filename,
                    lineno: e.lineno,
                    colno: e.colno,
                    error: e.error
                });
            });

            window.addEventListener('unhandledrejection', (e) => {
                console.error('Unhandled Promise Rejection:', e.reason);
            });
        })();
        """

        let consoleUserScript = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(consoleUserScript)
        userContentController.add(LeakAvoider(delegate: self), name: "console")

        self.webView.navigationDelegate = self

        loadBridge()
    }

    /// Posts a message to the JavaScript bridge
    /// - Parameters:
    ///   - method: The method name to call
    ///   - payload: The payload object to pass to the method
    ///   - timeout: Overrides the request timeout for a call that can legitimately run longer
    /// - Returns: The result from the JavaScript call
    /// - Throws: ParaWebViewError if the WebView is not ready or if the request fails
    @discardableResult
    public func postMessage(method: String, payload: Encodable, timeout: TimeInterval? = nil) async throws -> Any? {
        guard isReady else {
            logger.error("WebView not ready for \(method)")
            throw ParaWebViewError.webViewNotReady
        }

        guard isParaInitialized else {
            logger.error("Para not initialized for \(method)")
            throw ParaWebViewError.bridgeError("Para not initialized")
        }

        try Task.checkCancellation()

        let requestId = "req-\(UUID().uuidString)"
        logger.debug("Sending message: method=\(method) requestId=\(requestId)")

        let encodedPayload: Any
        do {
            let data = try JSONEncoder().encode(AnyEncodable(payload))
            encodedPayload = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            logger.error("Failed to encode payload: \(Self.redactLogMessage(error.localizedDescription))")
            throw ParaWebViewError.invalidArguments("Failed to encode payload: \(error)")
        }

        let message: [String: Any] = [
            "messageType": "Para#invokeMethod",
            "methodName": method,
            "arguments": encodedPayload,
            "requestId": requestId,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            logger.error("Failed to serialize message for method: \(method)")
            throw ParaWebViewError.invalidArguments("Unable to serialize message")
        }

        let store = pendingRequestStore
        let timeoutNanoseconds = Self.clampedTimeoutNanoseconds(timeout ?? requestTimeout)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let timeoutTask: Task<Void, Never> = Task { [weak self, store] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }

                    if let entry = store.removeValue(forKey: requestId) {
                        self?.logger.warning("Request timed out: method=\(method) requestId=\(requestId)")
                        entry.continuation.resume(throwing: ParaWebViewError.requestTimeout)
                    }
                }

                store.insert(.init(continuation: continuation, timeoutTask: timeoutTask), forKey: requestId)

                if Task.isCancelled, let entry = store.removeValue(forKey: requestId) {
                    entry.timeoutTask?.cancel()
                    entry.continuation.resume(throwing: CancellationError())
                    return
                }

                let script = "window.postMessage(\(jsonString));"
                let requestLogger = logger
                if let javascriptEvaluator {
                    javascriptEvaluator(script) { _, error in
                        Self.handleJavaScriptEvaluationError(
                            error,
                            requestId: requestId,
                            store: store,
                            logger: requestLogger
                        )
                    }
                } else {
                    webView.evaluateJavaScript(script) { _, error in
                        Self.handleJavaScriptEvaluationError(
                            error,
                            requestId: requestId,
                            store: store,
                            logger: requestLogger
                        )
                    }
                }
            }
        } onCancel: {
            if let entry = store.removeValue(forKey: requestId) {
                entry.timeoutTask?.cancel()
                entry.continuation.resume(throwing: CancellationError())
            }
        }
    }

    nonisolated static func clampedTimeoutNanoseconds(_ duration: TimeInterval) -> UInt64 {
        let maxSleepSeconds: TimeInterval = 31_536_000
        guard !duration.isNaN, duration > 0 else {
            return 0
        }
        if !duration.isFinite || duration >= maxSleepSeconds {
            return UInt64(maxSleepSeconds) * 1_000_000_000
        }
        return UInt64((duration * 1_000_000_000.0).rounded(.down))
    }

    private nonisolated static func handleJavaScriptEvaluationError(
        _ error: Error?,
        requestId: String,
        store: PendingBridgeRequestStore,
        logger: Logger
    ) {
        guard let error else { return }
        logger.error("JavaScript evaluation failed: \(redactLogMessage(error.localizedDescription))")
        if let entry = store.removeValue(forKey: requestId) {
            entry.timeoutTask?.cancel()
            entry.continuation.resume(throwing: error)
        }
    }

    /// Loads the JavaScript bridge into the WebView
    private func loadBridge() {
        logger.info("Loading bridge: \(Self.redactLogMessage(self.environment.jsBridgeUrl.absoluteString))")
        let request = URLRequest(url: environment.jsBridgeUrl)
        webView.load(request)
    }

    /// Initializes Para with the current environment and API key
    private func initPara() {
        logger.info("Initializing Para bridge")

        // WebAuthn/Passkeys support requires iOS 16.0+
        let isPasskeySupported = if #available(iOS 16.0, *) {
            true
        } else {
            false
        }

        let finalArgs = Self.buildInitArguments(
            environment: environment,
            apiKey: apiKey,
            packageVersion: Self.packageVersion,
            isPasskeySupported: isPasskeySupported
        )

        guard let jsonData = try? JSONSerialization.data(withJSONObject: finalArgs, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            logger.error("Failed to encode init arguments")
            lastError = ParaWebViewError.invalidArguments("Failed to encode init arguments")
            return
        }

        let script = Self.buildInitScript(argumentsJSON: jsonString)

        logger.debug("Executing Para#init script")

        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                let redacted = Self.redactLogMessage(error.localizedDescription)
                self?.logger.error("Para#init script failed: \(redacted)")
                self?.lastError = ParaWebViewError.bridgeError(redacted)
            } else {
                self?.logger.debug("Para#init script executed, waiting for response...")
            }
        }
    }

    /// Builds the JS snippet that waits for every external module script on the bridge page
    /// (including Vite dev server modules like `/@vite/client`) before posting `Para#init`.
    /// `void` ensures `WKWebView.evaluateJavaScript` evaluates to `undefined` rather than failing
    /// to serialize the returned Promise (`WKErrorJavaScriptResultTypeIsUnsupported`).
    nonisolated static func buildInitScript(argumentsJSON: String) -> String {
        """
        void (async () => {
          const scripts = Array.from(document.querySelectorAll('script[type="module"][src]'));
          await Promise.all(scripts.map((s) => import(s.src).catch(() => {})));
          console.log('Para Swift SDK: Sending init message');
          window.postMessage({
            messageType: 'Para#init',
            arguments: \(argumentsJSON)
          });
        })();
        """
    }

    /// Handles callbacks from the JavaScript bridge
    /// - Parameter response: The response data from JavaScript
    func handleCallback(response: [String: Any]) {
        let method = response["method"] as? String
        let requestId = response["requestId"] as? String

        if method == "Para#init", requestId == nil {
            if let payload = Self.parseBridgeError(response["error"]) {
                let redacted = Self.redactLogMessage(payload.formattedMessage)
                logger.error("Para initialization failed: \(redacted)")
                let error = ParaWebViewError.bridgeError(redacted)
                self.initializationError = error
                self.lastError = error
                return
            }
            logger.info("Para initialization completed")
            self.isParaInitialized = true
            self.isReady = true
            return
        }

        if method == "Para#event", requestId == nil {
            if let event = Self.parseOnRampEvent(from: response) {
                onRampEventBroadcaster.emit(event)
            } else {
                let eventName = Self.eventName(from: response) ?? "unknown"
                if Self.isKnownOnRampEventName(eventName) {
                    let rawPayload = response["payload"] ?? response["data"] ?? response["responseData"]
                    logger.warning("Failed to decode Para#event \(eventName): \(Self.redactLogMessage(String(describing: rawPayload)))")
                } else {
                    logger.debug("Ignoring unrecognized Para#event: \(eventName)")
                }
            }
            return
        }

        guard let requestId else {
            let methodLabel = Self.redactLogMessage(method ?? "missing")
            if method == nil {
                logger.error("Invalid response: missing method")
                lastError = ParaWebViewError.bridgeError("Invalid response: missing 'method'")
            } else {
                logger.error("Invalid response: missing requestId for method=\(methodLabel)")
                lastError = ParaWebViewError.bridgeError("Invalid response: missing 'requestId' for \(methodLabel)")
            }
            return
        }

        guard let entry = pendingRequestStore.removeValue(forKey: requestId) else {
            logger.error("Unknown requestId received: \(requestId)")
            lastError = ParaWebViewError.bridgeError("Received response for unknown requestId: \(requestId)")
            return
        }

        entry.timeoutTask?.cancel()

        if let errorPayload = Self.parseBridgeError(response["error"]) {
            let redacted = Self.redactLogMessage(errorPayload.formattedMessage)
            logger.error("Bridge error received: method=\(method ?? "unknown") error=\(redacted)")
            entry.continuation.resume(throwing: ParaWebViewError.bridgeError(errorPayload.formattedMessage))
            return
        }

        let responseData = response["responseData"]
        logger.debug("Request completed: method=\(method ?? "unknown") requestId=\(requestId)")
        entry.continuation.resume(returning: responseData)
    }

    // MARK: - Pure Testable Helpers

    nonisolated static func buildInitArguments(
        environment: ParaEnvironment,
        apiKey: String,
        packageVersion: String,
        isPasskeySupported: Bool
    ) -> [String: Any] {
        [
            "environment": environment.name,
            "apiKey": apiKey,
            "platform": "iOS",
            "hostOs": "ios",
            "package": packageVersion,
            "isPasskeySupported": isPasskeySupported,
            // This SDK drives auth v2 through `authenticateWithEmailOrPhone`. The bridge keeps the stage-based
            // methods on the legacy flow regardless, so declaring it changes nothing for apps that don't call it.
            "supportsAuthV2": true,
            "supportsEvents": true,
        ]
    }

    public nonisolated static func parseBridgeError(_ errorValue: Any?) -> ParaBridgeErrorPayload? {
        guard let errorValue, !(errorValue is NSNull) else {
            return nil
        }

        if let str = errorValue as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return ParaBridgeErrorPayload(message: "Unknown bridge error")
            }
            if trimmed.hasPrefix("{"),
               let data = trimmed.data(using: .utf8),
               let jsonDict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            {
                return parseBridgeErrorDictionary(jsonDict)
            }
            return ParaBridgeErrorPayload(message: str)
        }

        if let dict = errorValue as? [String: Any] {
            return parseBridgeErrorDictionary(dict)
        }

        return ParaBridgeErrorPayload(message: String(describing: errorValue))
    }

    public nonisolated static func redactLogMessage(_ message: String) -> String {
        var sanitized = message
        for rule in logRedactionRules {
            let range = NSRange(sanitized.startIndex ..< sanitized.endIndex, in: sanitized)
            sanitized = rule.regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return sanitized
    }

    public nonisolated static func parseOnRampEvent(from response: [String: Any]) -> ParaOnRampEvent? {
        let nestedResponseData = response["responseData"] as? [String: Any]
        let nestedPayload = response["payload"] as? [String: Any]

        guard let eventName = eventName(from: response),
              isKnownOnRampEventName(eventName)
        else {
            return nil
        }

        guard let dataDict = (response["data"] as? [String: Any])
            ?? (nestedResponseData?["data"] as? [String: Any])
            ?? (nestedPayload?["data"] as? [String: Any]),
            JSONSerialization.isValidJSONObject(dataDict),
            let jsonData = try? JSONSerialization.data(withJSONObject: dataDict, options: []),
            let payload = try? JSONDecoder().decode(ParaOnRampEventPayload.self, from: jsonData)
        else {
            return nil
        }

        switch eventName {
        case "ONRAMP_LAUNCHED", "paraOnRampLaunched":
            return .launched(payload)
        case "ONRAMP_TRANSACTION_COMPLETE_V2", "paraOnRampTransactionCompleteV2":
            return .completed(payload)
        default:
            return nil
        }
    }

    private nonisolated static func eventName(from response: [String: Any]) -> String? {
        let nestedResponseData = response["responseData"] as? [String: Any]
        let nestedPayload = response["payload"] as? [String: Any]
        return (response["event"] as? String)
            ?? (nestedResponseData?["event"] as? String)
            ?? (nestedPayload?["event"] as? String)
    }

    private nonisolated static func isKnownOnRampEventName(_ eventName: String) -> Bool {
        eventName == "ONRAMP_LAUNCHED"
            || eventName == "paraOnRampLaunched"
            || eventName == "ONRAMP_TRANSACTION_COMPLETE_V2"
            || eventName == "paraOnRampTransactionCompleteV2"
    }

    private nonisolated static func parseBridgeErrorDictionary(_ dict: [String: Any]) -> ParaBridgeErrorPayload {
        let detailsDict = dict["details"] as? [String: Any]
        let detailsDataDict = detailsDict?["data"] as? [String: Any]
        let dataDict = dict["data"] as? [String: Any]
        let nestedErrorDict = dict["error"] as? [String: Any]

        let code = nonEmptyString(detailsDataDict?["code"])
            ?? nonEmptyString(dataDict?["code"])
            ?? nonEmptyString(nestedErrorDict?["code"])
            ?? nonEmptyString(detailsDict?["code"])
            ?? nonEmptyString(dict["code"])
        let status = parseInt(detailsDataDict?["status"])
            ?? parseInt(detailsDataDict?["statusCode"])
            ?? parseInt(dict["status"])
            ?? parseInt(dict["statusCode"])
            ?? parseInt(detailsDict?["status"])
            ?? parseInt(detailsDict?["statusCode"])
            ?? parseInt(nestedErrorDict?["status"])
            ?? parseInt(nestedErrorDict?["statusCode"])
        let details = dict["details"].flatMap { BridgeJSONValue(any: $0) }

        let message = if let friendly = nonEmptyString(detailsDataDict?["message"])
            ?? nonEmptyString(dataDict?["message"])
            ?? nonEmptyString(nestedErrorDict?["message"])
            ?? nonEmptyString(detailsDict?["message"])
            ?? nonEmptyString(dict["message"])
            ?? nonEmptyString(dict["error"])
            ?? nonEmptyString(detailsDict?["data"])
        {
            friendly
        } else if let code {
            code
        } else if let status {
            "Bridge request failed with status \(status)"
        } else if JSONSerialization.isValidJSONObject(dict),
                  let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
                  let jsonStr = String(data: data, encoding: .utf8)
        {
            jsonStr
        } else {
            String(describing: dict)
        }

        return ParaBridgeErrorPayload(message: message, code: code, status: status, details: details)
    }

    private nonisolated static func nonEmptyString(_ value: Any?) -> String? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : str
    }

    private nonisolated static func parseInt(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private nonisolated static let sensitiveLogKeysPattern =
        "(?:publicToken|plaidLinkToken|launchToken|providerKey|accessToken|apiKey|secret|authentication_token|rampLaunchToken|paymentLink|upgradeUrl)"

    private nonisolated static let logRedactionRules: [(regex: NSRegularExpression, template: String)] = {
        let patterns: [(String, String)] = [
            // Escaped JSON object values, e.g. \"paymentLink\":{\"url\":\"...\"}
            (
                #"(\\"?\b\#(sensitiveLogKeysPattern)\b\\"?\s*:\s*)\{[^{}]*\}"#,
                #"$1\"[REDACTED]\""#
            ),
            // Plain JSON object values, e.g. "paymentLink":{"url":"..."}
            (
                #"(["']?\b\#(sensitiveLogKeysPattern)\b["']?\s*:\s*)\{[^{}]*\}"#,
                #"$1"[REDACTED]""#
            ),
            // Escaped JSON strings, e.g. \"apiKey\":\"sec_123\"
            (
                #"(\\"?\b\#(sensitiveLogKeysPattern)\b\\"?\s*:\s*\\")((?:\\(?!").|[^\\"])*)(\\")"#,
                "$1[REDACTED]$3"
            ),
            // Double-quoted JSON strings
            (
                #"(["']?\b\#(sensitiveLogKeysPattern)\b["']?\s*:\s*")((?:\\.|[^"\\])*)(")"#,
                "$1[REDACTED]$3"
            ),
            // Single-quoted strings
            (
                #"(["']?\b\#(sensitiveLogKeysPattern)\b["']?\s*:\s*')((?:\\.|[^'\\])*)(')"#,
                "$1[REDACTED]$3"
            ),
            // Query / fragment / key=value pairs
            (
                #"([?&#]|\b)(\#(sensitiveLogKeysPattern)\b)\s*=\s*([^\s?&#"'`<>)}\],]+)"#,
                "$1$2=[REDACTED]"
            ),
            // Plain unquoted key: value pairs
            (
                #"(\b\#(sensitiveLogKeysPattern)\b\s*:\s*)(?!null\b|undefined\b|\[REDACTED\])([^\s"',{}\[\]]+)"#,
                "$1[REDACTED]"
            ),
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex, template)
        }
    }()
}

/// Represents an empty payload for bridge calls with no arguments
struct EmptyPayload: Encodable {}

/// Extension implementing WKNavigationDelegate for ParaWebView
extension ParaWebView: WKNavigationDelegate {
    /// Called when navigation starts
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        logger.info("WebView started loading: \(Self.redactLogMessage(webView.url?.absoluteString ?? "unknown"))")
    }

    /// Called when content starts arriving
    public func webView(_: WKWebView, didCommit _: WKNavigation!) {
        logger.debug("WebView committed navigation")
    }

    /// Called when the WebView finishes loading
    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        logger.info("Bridge loaded, initializing Para...")
        initPara()
    }

    /// Called when the WebView fails to load
    public func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        let redacted = Self.redactLogMessage(error.localizedDescription)
        logger.error("WebView failed to load: \(redacted)")
        logger.error("Failed URL: \(Self.redactLogMessage(webView.url?.absoluteString ?? "unknown"))")
        initializationError = ParaWebViewError.bridgeError(redacted)
    }

    /// Called when the WebView fails to load provisionally
    public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        let redacted = Self.redactLogMessage(error.localizedDescription)
        logger.error("WebView failed provisional navigation: \(redacted)")
        logger.error("Failed URL: \(Self.redactLogMessage(self.environment.jsBridgeUrl.absoluteString))")
        initializationError = ParaWebViewError.bridgeError(redacted)
    }

    /// Called to handle navigation policy decisions
    public func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        logger.debug("Navigation policy decision for: \(Self.redactLogMessage(navigationAction.request.url?.absoluteString ?? "unknown"))")
        decisionHandler(.allow)
    }
}

/// Extension implementing WKScriptMessageHandler for ParaWebView
extension ParaWebView: WKScriptMessageHandler {
    /// Handles messages received from JavaScript
    public func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "console" {
            if let consoleData = message.body as? [String: Any],
               let level = consoleData["level"] as? String,
               let consoleMessage = consoleData["message"] as? String
            {
                let redacted = Self.redactLogMessage(consoleMessage)
                switch level {
                case "error":
                    logger.error("[JS Console] \(redacted)")
                case "warn":
                    logger.warning("[JS Console] \(redacted)")
                default:
                    logger.debug("[JS Console] \(redacted)")
                }
            }
            return
        }

        guard message.name == "callback" else {
            logger.warning("Received unknown message handler: \(message.name)")
            return
        }

        guard let resp = message.body as? [String: Any] else {
            logger.error("Invalid JS callback payload: \(Self.redactLogMessage(String(describing: message.body)))")
            lastError = ParaWebViewError.bridgeError("Invalid JS callback payload")
            return
        }
        handleCallback(response: resp)
    }
}

/// Errors that can occur during WebView operations
enum ParaWebViewError: Error, CustomStringConvertible, LocalizedError {
    /// The WebView is not ready to accept requests
    case webViewNotReady
    /// Invalid arguments were provided
    case invalidArguments(String)
    /// The request timed out
    case requestTimeout
    /// An error occurred in the bridge
    case bridgeError(String)

    /// A human-readable description of the error
    var description: String {
        switch self {
        case .webViewNotReady:
            "WebView is not ready to accept requests."
        case let .invalidArguments(msg):
            "Invalid arguments: \(msg)"
        case .requestTimeout:
            "The request timed out."
        case let .bridgeError(msg):
            "Bridge error: \(msg)"
        }
    }

    /// Provide nicer strings for SwiftUI alerts and NSError bridging
    var errorDescription: String? {
        switch self {
        case .webViewNotReady:
            "WebView is not ready to accept requests."
        case let .invalidArguments(msg):
            "Invalid arguments: \(msg)"
        case .requestTimeout:
            "The request timed out."
        case let .bridgeError(msg):
            msg // Return the raw error message without "Bridge error:" prefix
        }
    }
}

/// A helper class to avoid retain cycles in script message handling
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler?) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// A wrapper for any encodable type
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ value: some Encodable) {
        encodeFunc = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
