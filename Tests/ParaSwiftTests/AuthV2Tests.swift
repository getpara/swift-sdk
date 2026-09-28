import AuthenticationServices
@testable import ParaSwift
import SwiftUI
import XCTest

final class AuthV2Tests: XCTestCase {
    private func snapshot(
        corePhase: String = "auth_flow",
        authPhase: String = "awaiting_session_start",
        error: String? = nil,
        info: [String: Any]
    ) -> AuthV2Snapshot {
        var dict: [String: Any] = ["corePhase": corePhase, "authPhase": authPhase, "authStateInfo": info]
        if let error { dict["error"] = error }
        return AuthV2Snapshot(dict)
    }

    func testExistingStageMethodsKeepTheirSignatures() {
        let contract: (ParaManager, Auth, AuthState, AuthorizationController) async throws -> Void = { manager, auth, state, controller in
            _ = try await manager.initiateAuthFlow(auth: auth)
            _ = try await manager.handleVerificationCode(verificationCode: "123456")
            try await manager.handleLogin(authState: state, authorizationController: controller)
            try await manager.handleSignup(authState: state, method: .passkey, authorizationController: controller)
        }

        XCTAssertNotNil(contract as Any)
    }

    func testReturningPasskeyUserSignsInWithTheNativePasskey() {
        let state = snapshot(info: [
            "isNewUser": false,
            "hasPasskey": true,
            "passkeyUrl": "https://portal/loginAuth?flowId=f1",
            "verificationUrl": NSNull(),
        ])

        XCTAssertEqual(AuthV2FirstStep.resolve(state, nativePasskeySupported: true), .nativePasskey)
    }

    func testReturningPasskeyUserFallsBackToThePortalWithoutNativePasskeys() {
        let state = snapshot(info: [
            "isNewUser": false,
            "hasPasskey": true,
            "passkeyUrl": "https://portal/loginAuth?flowId=f1",
        ])

        XCTAssertEqual(
            AuthV2FirstStep.resolve(state, nativePasskeySupported: false),
            .portal(url: "https://portal/loginAuth?flowId=f1", context: "passkey")
        )
    }

    func testNewUserVerifiesInThePortal() {
        let state = snapshot(info: [
            "isNewUser": true,
            "hasPasskey": false,
            "verificationUrl": "https://portal/v2/login/otp?flowId=f1",
        ])

        XCTAssertEqual(
            AuthV2FirstStep.resolve(state, nativePasskeySupported: true),
            .portal(url: "https://portal/v2/login/otp?flowId=f1", context: "verification")
        )
    }

    func testReturningPasswordUserUnlocksInThePortal() {
        let state = snapshot(info: [
            "isNewUser": false,
            "hasPassword": true,
            "passwordUrl": "https://portal/loginPassword?flowId=f1",
        ])

        XCTAssertEqual(
            AuthV2FirstStep.resolve(state, nativePasskeySupported: true),
            .portal(url: "https://portal/loginPassword?flowId=f1", context: "password")
        )
    }

    func testNoStepWithoutAnyUrl() {
        XCTAssertNil(AuthV2FirstStep.resolve(snapshot(info: ["isNewUser": true]), nativePasskeySupported: true))
    }

    func testCredentialSetupPrefersThePasskeyCreatePage() {
        let state = snapshot(info: [
            "isCredentialSetup": true,
            "passkeyUrl": "https://portal/createAuth?flowId=f1",
            "passwordUrl": "https://portal/createPassword?flowId=f1",
        ])

        XCTAssertEqual(state.credentialSetupUrl, "https://portal/createAuth?flowId=f1")
    }

    func testCredentialSetupFallsBackToThePinCreatePage() {
        let state = snapshot(info: ["isCredentialSetup": true, "pinUrl": "https://portal/createPIN?flowId=f1"])

        XCTAssertEqual(state.credentialSetupUrl, "https://portal/createPIN?flowId=f1")
    }

    func testNoCredentialSetupOutsideTheSetupProjection() {
        let state = snapshot(info: ["isCredentialSetup": false, "passkeyUrl": "https://portal/loginAuth?flowId=f1"])

        XCTAssertNil(state.credentialSetupUrl)
    }

    func testPhasesAndFailures() {
        XCTAssertTrue(snapshot(corePhase: "authenticated", authPhase: "authenticated", info: [:]).isAuthenticated)
        XCTAssertTrue(snapshot(info: [:]).isAwaitingPortal)
        // Core moves straight on to polling for the session; the portal URLs are still projected there.
        XCTAssertTrue(snapshot(authPhase: "waiting_for_session", info: [:]).isAwaitingPortal)
        XCTAssertFalse(snapshot(authPhase: "authenticating_v2", info: [:]).isAwaitingPortal)
        XCTAssertNil(snapshot(info: [:]).failure)
        XCTAssertEqual(snapshot(authPhase: "error", error: "Flow expired", info: [:]).failure, "Flow expired")
        XCTAssertEqual(snapshot(corePhase: "error", info: [:]).failure, "Authentication failed")
    }
}
