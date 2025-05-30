import SwiftUI
import WebKit
import os

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
    
    /// The Para environment configuration
    public var environment: ParaEnvironment
    
    /// The API key for Para services
    public var apiKey: String
    
    /// The current package version of the SDK
    public static var packageVersion: String {
        return ParaPackage.version
    }
    
    private let webView: WKWebView
    private let requestTimeout: TimeInterval
    
    private var pendingRequests: [String: (continuation: CheckedContinuation<Any?, Error>, timeoutTask: Task<Void, Never>?)] = [:]
    private var isParaInitialized = false
    
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaWebView")
    
    /// Creates a new ParaWebView instance
    /// - Parameters:
    ///   - environment: The Para environment configuration
    ///   - apiKey: The API key for Para services
    ///   - requestTimeout: The timeout duration for requests in seconds (default: 30.0)
    public init(environment: ParaEnvironment, apiKey: String, requestTimeout: TimeInterval = 30.0) {
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
        console.originalLog = console.log;
        console.originalError = console.error;
        console.originalWarn = console.warn;
        
        console.log = function() {
            console.originalLog.apply(console, arguments);
            window.webkit.messageHandlers.console?.postMessage({level: 'log', message: Array.from(arguments).join(' ')});
        };
        
        console.error = function() {
            console.originalError.apply(console, arguments);
            window.webkit.messageHandlers.console?.postMessage({level: 'error', message: Array.from(arguments).join(' ')});
        };
        
        console.warn = function() {
            console.originalWarn.apply(console, arguments);
            window.webkit.messageHandlers.console?.postMessage({level: 'warn', message: Array.from(arguments).join(' ')});
        };
        
        window.addEventListener('error', function(e) {
            console.error('JavaScript Error:', e.message, 'at', e.filename + ':' + e.lineno);
        });
        
        window.addEventListener('unhandledrejection', function(e) {
            console.error('Unhandled Promise Rejection:', e.reason);
        });
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
    /// - Returns: The result from the JavaScript call
    /// - Throws: ParaWebViewError if the WebView is not ready or if the request fails
    @discardableResult
    public func postMessage(method: String, payload: Encodable) async throws -> Any? {
        guard isReady else {
            logger.error("WebView not ready for method: \(method)")
            throw ParaWebViewError.webViewNotReady
        }
        
        guard isParaInitialized else {
            logger.error("Para not initialized for method: \(method)")
            throw ParaWebViewError.bridgeError("Para not initialized")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let requestId = "req-\(UUID().uuidString)"
            logger.debug("Sending message: method=\(method) requestId=\(requestId)")
            
            let encodedPayload: Any
            do {
                let data = try JSONEncoder().encode(AnyEncodable(payload))
                encodedPayload = try JSONSerialization.jsonObject(with: data, options: [])
            } catch {
                logger.error("Failed to encode payload: \(error.localizedDescription)")
                continuation.resume(throwing: ParaWebViewError.invalidArguments("Failed to encode payload: \(error)"))
                return
            }
            
            let message: [String: Any] = [
                "messageType": "Para#invokeMethod",
                "methodName": method,
                "arguments": encodedPayload,
                "requestId": requestId
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: message, options: []),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                logger.error("Failed to serialize message for method: \(method)")
                continuation.resume(throwing: ParaWebViewError.invalidArguments("Unable to serialize message"))
                return
            }
            
            let timeoutTask: Task<Void, Never> = Task { [weak self] in
                let duration = self?.requestTimeout ?? 30.0
                do {
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    self?.logger.warning("Request timed out: method=\(method) requestId=\(requestId)")
                } catch {
                    return
                }
                
                guard let self = self else { return }
                if let entry = self.pendingRequests.removeValue(forKey: requestId) {
                    entry.continuation.resume(throwing: ParaWebViewError.requestTimeout)
                }
            }
            
            pendingRequests[requestId] = (continuation, timeoutTask)
            
            webView.evaluateJavaScript("window.postMessage(\(jsonString));") { [weak self] _, error in
                guard let self = self else { return }
                if let error = error {
                    logger.error("JavaScript evaluation failed: \(error.localizedDescription)")
                    let entry = self.pendingRequests.removeValue(forKey: requestId)
                    entry?.timeoutTask?.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Loads the JavaScript bridge into the WebView
    private func loadBridge() {
        logger.info("Loading bridge from URL: \(self.environment.jsBridgeUrl.absoluteString)")
        let request = URLRequest(url: environment.jsBridgeUrl)
        webView.load(request)
    }
    
    /// Initializes Para with the current environment and API key
    private func initPara() {
        logger.info("Initializing Para with environment: \(self.environment.name), apiKey: \(String(self.apiKey.prefix(8)))...")
        
        let args: [String: String] = [
            "environment": environment.name,
            "apiKey": apiKey,
            "platform": "iOS",
            "package": Self.packageVersion
        ]
        
        var finalArgs: [String: Any] = args

        // WebAuthn/Passkeys support requires iOS 16.0+
        if #available(iOS 16.0, *) {
            finalArgs["isPasskeySupported"] = true
        } else {
            finalArgs["isPasskeySupported"] = false
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: finalArgs, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to encode init arguments")
            lastError = ParaWebViewError.invalidArguments("Failed to encode init arguments")
            return
        }
        
        let script = """
        console.log('Para Swift SDK: Sending init message');
        window.postMessage({
          messageType: 'Para#init',
          arguments: \(jsonString)
        });
        """
        
        logger.debug("Executing init script: \(script)")
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error = error {
                self?.logger.error("JavaScript init failed: \(error.localizedDescription)")
                self?.lastError = error
            } else {
                self?.logger.debug("JavaScript init executed successfully")
            }
        }
    }
    
    /// Handles callbacks from the JavaScript bridge
    /// - Parameter response: The response data from JavaScript
    private func handleCallback(response: [String: Any]) {
        guard let method = response["method"] as? String else {
            logger.error("Invalid response: missing method")
            lastError = ParaWebViewError.bridgeError("Invalid response: missing 'method'")
            return
        }
        
        if method == "Para#init" && response["requestId"] == nil {
            logger.debug("Para initialization completed")
            self.isParaInitialized = true
            self.isReady = true
            return
        }
        
        guard let requestId = response["requestId"] as? String else {
            logger.error("Invalid response: missing requestId for method=\(method)")
            lastError = ParaWebViewError.bridgeError("Invalid response: missing 'requestId' for \(method)")
            return
        }
        
        guard let entry = pendingRequests.removeValue(forKey: requestId) else {
            logger.error("Unknown requestId received: \(requestId)")
            lastError = ParaWebViewError.bridgeError("Received response for unknown requestId: \(requestId)")
            return
        }
        
        entry.timeoutTask?.cancel()
        
        if let errorValue = response["error"] {
            var errorMessage = ""
            if let dict = errorValue as? [String: Any] {
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    errorMessage = jsonStr
                } else {
                    errorMessage = String(describing: dict)
                }
            } else if let message = errorValue as? String {
                errorMessage = message
            } else {
                errorMessage = String(describing: errorValue)
            }
            logger.error("Bridge error received: method=\(method) error=\(errorMessage)")
            entry.continuation.resume(throwing: ParaWebViewError.bridgeError(errorMessage))
            return
        }
        
        let responseData = response["responseData"]
        logger.debug("Request completed: method=\(method) requestId=\(requestId)")
        entry.continuation.resume(returning: responseData)
    }
}

/// Represents an empty payload for bridge calls with no arguments
struct EmptyPayload: Encodable {}

/// Extension implementing WKNavigationDelegate for ParaWebView
extension ParaWebView: WKNavigationDelegate {
    /// Called when navigation starts
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.info("WebView started loading: \(webView.url?.absoluteString ?? "unknown")")
    }
    
    /// Called when content starts arriving
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        logger.debug("WebView committed navigation")
    }
    
    /// Called when the WebView finishes loading
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView finished loading: \(webView.url?.absoluteString ?? "unknown")")
        logger.info("Initializing Para...")
        initPara()
    }
    
    /// Called when the WebView fails to load
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed to load: \(error.localizedDescription)")
        logger.error("Failed URL: \(webView.url?.absoluteString ?? "unknown")")
        initializationError = error
    }
    
    /// Called when the WebView fails to load provisionally
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed provisional navigation: \(error.localizedDescription)")
        logger.error("Failed URL: \(self.environment.jsBridgeUrl.absoluteString)")
        initializationError = error
    }
    
    /// Called to handle navigation policy decisions
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        logger.debug("Navigation policy decision for: \(navigationAction.request.url?.absoluteString ?? "unknown")")
        decisionHandler(.allow)
    }
}

/// Extension implementing WKScriptMessageHandler for ParaWebView
extension ParaWebView: WKScriptMessageHandler {
    /// Handles messages received from JavaScript
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "console" {
            if let consoleData = message.body as? [String: Any],
               let level = consoleData["level"] as? String,
               let consoleMessage = consoleData["message"] as? String {
                switch level {
                case "error":
                    logger.error("[JS Console] \(consoleMessage)")
                case "warn":
                    logger.warning("[JS Console] \(consoleMessage)")
                default:
                    logger.debug("[JS Console] \(consoleMessage)")
                }
            }
            return
        }
        
        guard message.name == "callback" else { 
            logger.warning("Received unknown message handler: \(message.name)")
            return 
        }
        
        guard let resp = message.body as? [String: Any] else {
            logger.error("Invalid JS callback payload: \(String(describing: message.body))")
            lastError = ParaWebViewError.bridgeError("Invalid JS callback payload")
            return
        }
        handleCallback(response: resp)
    }
}

/// Errors that can occur during WebView operations
enum ParaWebViewError: Error, CustomStringConvertible {
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
            return "WebView is not ready to accept requests."
        case .invalidArguments(let msg):
            return "Invalid arguments: \(msg)"
        case .requestTimeout:
            return "The request timed out."
        case .bridgeError(let msg):
            return "Bridge error: \(msg)"
        }
    }
}

/// A helper class to avoid retain cycles in script message handling
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler?) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// A wrapper for any encodable type
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        encodeFunc = { encoder in
            try value.encode(to: encoder)
        }
    }
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
