@testable import ParaSwift
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
        XCTAssertTrue(script.contains("querySelectorAll('script[type=\"module\"][src]')"))
        XCTAssertTrue(script.contains("Promise.all"))
        XCTAssertFalse(script.contains("querySelector('script[type=\"module\"][src]')"))
    }
}
