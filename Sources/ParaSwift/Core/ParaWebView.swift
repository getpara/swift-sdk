import SwiftUI
import WebKit
import os

#if os(iOS)
@available(iOS 16.4,*)
@MainActor
public class ParaWebView: NSObject, ObservableObject {
    
    @Published public private(set) var isReady: Bool = false
    @Published public var initializationError: Error?
    @Published public var lastError: Error?
    
    public var environment: ParaEnvironment
    public var apiKey: String
    public static let packageVersion = "0.0.3"
    
    private let webView: WKWebView
    private let requestTimeout: TimeInterval
    
    private var pendingRequests: [String: (continuation: CheckedContinuation<Any?, Error>, timeoutTask: Task<Void, Never>?)] = [:]
    private var isParaInitialized = false
    
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaWebView")
    
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
        self.webView.navigationDelegate = self
        
        loadBridge()
    }
    
    @discardableResult
    public func postMessage(method: String, arguments: [Encodable]) async throws -> Any? {
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
            
            let encodedArgs: Any
            do {
                let data = try JSONEncoder().encode(arguments.map { AnyEncodable($0) })
                encodedArgs = try JSONSerialization.jsonObject(with: data, options: [])
            } catch {
                logger.error("Failed to encode arguments: \(error.localizedDescription)")
                continuation.resume(throwing: ParaWebViewError.invalidArguments("Failed to encode arguments: \(error)"))
                return
            }
            
            let message: [String: Any] = [
                "messageType": "Capsule#invokeMethod",
                "methodName": method,
                "arguments": encodedArgs,
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
    
    private func loadBridge() {
        let request = URLRequest(url: environment.jsBridgeUrl)
        webView.load(request)
    }
    
    private func initPara() {
        let args: [String: String] = [
            "environment": environment.name,
            "apiKey": apiKey,
            "platform": "iOS",
            "package": Self.packageVersion
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: args, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            lastError = ParaWebViewError.invalidArguments("Failed to encode init arguments")
            return
        }
        
        let script = """
        window.postMessage({
          messageType: 'Capsule#init',
          arguments: \(jsonString)
        });
        """
        
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                self?.lastError = error
            }
        }
    }
    
    private func handleCallback(response: [String: Any]) {
        guard let method = response["method"] as? String else {
            logger.error("Invalid response: missing method")
            lastError = ParaWebViewError.bridgeError("Invalid response: missing 'method'")
            return
        }
        
        if method == "Capsule#init" && response["requestId"] == nil {
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

@available(iOS 16.4,*)
extension ParaWebView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initPara()
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        initializationError = error
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        initializationError = error
    }
}

@available(iOS 16.4,*)
extension ParaWebView: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "callback" else { return }
        guard let resp = message.body as? [String: Any] else {
            lastError = ParaWebViewError.bridgeError("Invalid JS callback payload")
            return
        }
        handleCallback(response: resp)
    }
}

@available(iOS 16.4,*)
enum ParaWebViewError: Error, CustomStringConvertible {
    case webViewNotReady
    case invalidArguments(String)
    case requestTimeout
    case bridgeError(String)
    
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

@available(iOS 16.4,*)
private class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler?) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@available(iOS 16.4,*)
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
#endif
