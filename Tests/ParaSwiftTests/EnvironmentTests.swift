@testable import ParaSwift
import WebKit
import XCTest

final class EnvironmentTests: XCTestCase {
    func testDevEnvironmentDefaultsAndOverrides() {
        let defaultDev = ParaEnvironment.dev(relyingPartyId: "localhost", jsBridgeUrl: nil)
        XCTAssertEqual(defaultDev.name, "DEV")
        XCTAssertEqual(defaultDev.relyingPartyId, "localhost")
        XCTAssertEqual(defaultDev.jsBridgeUrl.absoluteString, "http://localhost:5173")

        let customBridge = URL(string: "http://127.0.0.1:5173")!
        let customDev = ParaEnvironment.dev(relyingPartyId: "127.0.0.1", jsBridgeUrl: customBridge)
        XCTAssertEqual(customDev.name, "DEV")
        XCTAssertEqual(customDev.relyingPartyId, "127.0.0.1")
        XCTAssertEqual(customDev.jsBridgeUrl, customBridge)
    }

    func testBuildInitScriptAwaitsAllModuleScripts() {
        let script = ParaWebView.buildInitScript(argumentsJSON: "{}")
        XCTAssertTrue(script.contains("void (async"))
        XCTAssertTrue(script.contains("querySelectorAll('script[type=\"module\"][src]')"))
        XCTAssertTrue(script.contains("Promise.all"))
        XCTAssertFalse(script.contains("querySelector('script[type=\"module\"][src]')"))
    }

    @MainActor
    func testBuildInitScriptDeliversParaInitAfterSlowerAndFailingModuleScripts() async throws {
        let schemeHandler = MultiModuleBridgeSchemeHandler()
        let contentController = WKUserContentController()
        let messageDelegate = TestBridgeMessageDelegate()
        contentController.add(messageDelegate, name: "testBridge")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "paratest")

        let webView = WKWebView(frame: .zero, configuration: config)
        let navDelegate = TestNavigationDelegate()
        webView.navigationDelegate = navDelegate

        webView.load(URLRequest(url: URL(string: "paratest://bridge/index.html")!))
        try await navDelegate.waitForFinish()

        let script = ParaWebView.buildInitScript(argumentsJSON: #"{"environment":"DEV"}"#)
        let evalError: Error? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { _, error in
                continuation.resume(returning: error)
            }
        }
        XCTAssertNil(evalError, "Expected void async IIFE to evaluate without serialization error")

        let payload = try await messageDelegate.waitForInitPayload()
        XCTAssertEqual(payload["messageType"] as? String, "Para#init")
        let args = payload["arguments"] as? [String: Any]
        XCTAssertEqual(args?["environment"] as? String, "DEV")
    }
}

private final class MultiModuleBridgeSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var cancelledTasks = Set<ObjectIdentifier>()

    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        let path = urlSchemeTask.request.url?.path ?? ""

        if path == "/broken-module.js" {
            let response = HTTPURLResponse(
                url: urlSchemeTask.request.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/javascript; charset=utf-8",
                    "Access-Control-Allow-Origin": "*",
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data("throw new Error('broken');".utf8))
            urlSchemeTask.didFinish()
            return
        }

        let mimeType = path.hasSuffix(".js") ? "text/javascript; charset=utf-8" : "text/html; charset=utf-8"
        let body: String
        let delay: TimeInterval

        switch path {
        case "/index.html":
            delay = 0
            body = """
            <!doctype html>
            <html>
              <head>
                <script type="module" src="/broken-module.js"></script>
                <script type="module" src="/vite-client.js"></script>
              </head>
              <body>
                <script type="module" src="/bridge.js"></script>
              </body>
            </html>
            """
        case "/vite-client.js":
            delay = 0
            body = "window.__viteClientLoaded = true;"
        case "/bridge.js":
            delay = 0.08
            body = """
            window.addEventListener('message', (event) => {
              if (event.data && event.data.messageType === 'Para#init') {
                window.webkit.messageHandlers.testBridge.postMessage(event.data);
              }
            });
            """
        default:
            delay = 0
            body = ""
        }

        let finishResponse = {
            self.lock.lock()
            let isCancelled = self.cancelledTasks.contains(taskId)
            self.lock.unlock()
            guard !isCancelled else { return }

            let response = HTTPURLResponse(
                url: urlSchemeTask.request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mimeType,
                    "Access-Control-Allow-Origin": "*",
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data(body.utf8))
            urlSchemeTask.didFinish()
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: finishResponse)
        } else {
            finishResponse()
        }
    }

    func webView(_: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        cancelledTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }
}

@MainActor
private final class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private final class TestBridgeMessageDelegate: NSObject, WKScriptMessageHandler {
    private var payload: [String: Any]?
    private var continuation: CheckedContinuation<[String: Any], Error>?

    func waitForInitPayload() async throws -> [String: Any] {
        if let payload {
            return payload
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        payload = body
        continuation?.resume(returning: body)
        continuation = nil
    }
}
