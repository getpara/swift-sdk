@testable import ParaSwift
import XCTest

final class BridgeOriginMatchingTests: XCTestCase {
    private let bridge = URL(string: "https://alpha-js-bridge.prod.getpara.com/")!

    func testMatchesTheSameSchemeHostAndPort() {
        XCTAssertTrue(ParaWebView.isBridgeOrigin(URL(string: "https://alpha-js-bridge.prod.getpara.com/a/b?c#d"), bridgeUrl: bridge))
        XCTAssertTrue(ParaWebView.isBridgeOrigin(URL(string: "https://ALPHA-js-bridge.prod.getpara.com:443/"), bridgeUrl: bridge))
        XCTAssertTrue(ParaWebView.isBridgeOrigin(scheme: "https", host: "alpha-js-bridge.prod.getpara.com", port: 0, bridgeUrl: bridge))
    }

    func testRejectsEverythingElse() {
        for other in [
            "http://alpha-js-bridge.prod.getpara.com/",
            "https://alpha-js-bridge.prod.getpara.com:8443/",
            "https://alpha-js-bridge.prod.getpara.com.other.example/",
            "https://prod.getpara.com/",
            "https://user@other.example/alpha-js-bridge.prod.getpara.com",
            "about:blank",
            "file:///index.html",
        ] {
            XCTAssertFalse(ParaWebView.isBridgeOrigin(URL(string: other), bridgeUrl: bridge), other)
        }
        XCTAssertFalse(ParaWebView.isBridgeOrigin(nil, bridgeUrl: bridge))
        XCTAssertFalse(ParaWebView.isBridgeOrigin(scheme: "", host: "", port: 0, bridgeUrl: bridge))
    }

    func testLocalDevelopmentBridgeKeepsItsPort() {
        let local = URL(string: "http://localhost:5173")!
        XCTAssertTrue(ParaWebView.isBridgeOrigin(scheme: "http", host: "localhost", port: 5173, bridgeUrl: local))
        XCTAssertFalse(ParaWebView.isBridgeOrigin(scheme: "http", host: "localhost", port: 3000, bridgeUrl: local))
    }
}
