@testable import ParaSwift
import WebKit
import XCTest

/// The bridge web view stays on the bridge origin and only takes responses from the bridge page itself.
@MainActor
final class BridgeWebViewOriginTests: XCTestCase {
    private let bridgeUrl = URL(string: "https://bridge.para-test.invalid/")!

    private func makeBridgeWebView() -> ParaWebView {
        ParaWebView(environment: .dev(relyingPartyId: "test", jsBridgeUrl: bridgeUrl), apiKey: "test")
    }

    // MARK: - Navigation

    /// Loads `html` on the bridge origin in a scratch web view whose navigation decisions are made by `bridge`,
    /// and returns the decision for the first navigation to a URL containing `marker`.
    private func decision(by bridge: ParaWebView, html: String, marker: String) async throws -> NavigationRecorder.Decision {
        let recorder = NavigationRecorder(target: bridge)
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = recorder
        webView.loadHTMLString(html, baseURL: bridgeUrl)

        for _ in 0 ..< 400 where recorder.decision(for: marker) == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        withExtendedLifetime(webView) {}
        return try XCTUnwrap(recorder.decision(for: marker), "No navigation to \(marker) was attempted")
    }

    func testMainFrameCannotLeaveTheBridgeOrigin() async throws {
        let bridge = makeBridgeWebView()

        for foreign in ["https://other.example/leave", "http://bridge.para-test.invalid/leave", "https://bridge.para-test.invalid:8443/leave"] {
            let decision = try await decision(by: bridge, html: "<script>location.href = '\(foreign)';</script>", marker: foreign)
            XCTAssertTrue(decision.isMainFrame, foreign)
            XCTAssertEqual(decision.policy, .cancel, foreign)
        }
    }

    func testMainFrameCanNavigateWithinTheBridgeOrigin() async throws {
        let bridge = makeBridgeWebView()

        let decision = try await decision(
            by: bridge,
            html: "<script>location.href = 'https://bridge.para-test.invalid/next';</script>",
            marker: "/next"
        )
        XCTAssertTrue(decision.isMainFrame)
        XCTAssertEqual(decision.policy, .allow)
    }

    func testSubframeNavigationIsNotBlocked() async throws {
        let bridge = makeBridgeWebView()

        let decision = try await decision(
            by: bridge,
            html: "<iframe src=\"https://other.example/widget\"></iframe>",
            marker: "/widget"
        )
        XCTAssertFalse(decision.isMainFrame)
        XCTAssertEqual(decision.policy, .allow)
    }

    // MARK: - Callbacks

    /// Loads `html` at `baseUrl` in a scratch web view and forwards its `callback` messages to `bridge`, the same
    /// way the bridge's own web view does. Returns once the page has sent `expected` messages.
    private func deliverCallbacks(to bridge: ParaWebView, html: String, baseUrl: URL, expected: Int = 1) async throws {
        let forwarder = Forwarder(target: bridge, expected: expected)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(forwarder, name: "callback")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(html, baseURL: baseUrl)

        for _ in 0 ..< 400 where forwarder.received < expected {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(forwarder.received, expected, "The test page did not send its callback")
        withExtendedLifetime(webView) {}
    }

    private let initCallback = "window.webkit.messageHandlers.callback.postMessage({ method: 'Para#init' });"

    func testCallbackFromAnotherOriginDoesNotMarkTheBridgeReady() async throws {
        let bridge = makeBridgeWebView()

        try await deliverCallbacks(
            to: bridge,
            html: "<script>\(initCallback)</script>",
            baseUrl: URL(string: "https://other.example/")!
        )
        XCTAssertFalse(bridge.isReady)
    }

    func testCallbackFromASubframeDoesNotMarkTheBridgeReady() async throws {
        let bridge = makeBridgeWebView()

        // A `srcdoc` frame has the page's origin, so only the main-frame check can tell it apart.
        try await deliverCallbacks(
            to: bridge,
            html: "<iframe srcdoc=\"<script>\(initCallback)</script>\"></iframe>",
            baseUrl: bridgeUrl
        )
        XCTAssertFalse(bridge.isReady)
    }

    func testCallbackFromTheBridgePageMarksTheBridgeReady() async throws {
        let bridge = makeBridgeWebView()

        try await deliverCallbacks(to: bridge, html: "<script>\(initCallback)</script>", baseUrl: bridgeUrl)
        XCTAssertTrue(bridge.isReady)
    }

    func testANewBridgeDocumentIsNotReadyUntilItInitializes() async throws {
        let bridge = makeBridgeWebView()
        try await deliverCallbacks(to: bridge, html: "<script>\(initCallback)</script>", baseUrl: bridgeUrl)
        XCTAssertTrue(bridge.isReady)

        bridge.webView(WKWebView(), didCommit: nil)
        XCTAssertFalse(bridge.isReady, "A newly committed document has not initialized the bridge yet")
    }
}

private final class Forwarder: NSObject, WKScriptMessageHandler {
    private let target: ParaWebView
    private let expected: Int
    private(set) var received = 0

    init(target: ParaWebView, expected: Int) {
        self.target = target
        self.expected = expected
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target.userContentController(controller, didReceive: message)
        received += 1
    }
}

private final class NavigationRecorder: NSObject, WKNavigationDelegate {
    struct Decision {
        let url: String
        let isMainFrame: Bool
        let policy: WKNavigationActionPolicy
    }

    private let target: ParaWebView
    private var decisions: [Decision] = []

    init(target: ParaWebView) {
        self.target = target
    }

    func decision(for marker: String) -> Decision? {
        decisions.first { $0.url.contains(marker) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url?.absoluteString ?? ""
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        target.webView(webView, decidePolicyFor: action) { [weak self] policy in
            self?.decisions.append(Decision(url: url, isMainFrame: isMainFrame, policy: policy))
            decisionHandler(policy)
        }
    }
}
