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

    func testCredentialSetupCreatesThePasskeyNatively() {
        let state = snapshot(info: [
            "isCredentialSetup": true,
            "passkeyId": "bio-1",
            "passkeyUrl": "https://portal/createAuth?flowId=f1",
            "passwordUrl": "https://portal/createPassword?flowId=f1",
        ])

        XCTAssertEqual(state.credentialSetupStep, .nativePasskey(biometricsId: "bio-1"))
    }

    func testCredentialSetupWithOnlyAPendingPasskeyEndsTheWait() {
        let state = snapshot(authPhase: "waiting_for_session", info: ["isCredentialSetup": true, "passkeyId": "bio-1"])

        XCTAssertNotNil(state.credentialSetupStep)
    }

    func testCredentialSetupOpensThePasswordCreatePageWithoutAPendingPasskey() {
        let state = snapshot(info: [
            "isCredentialSetup": true,
            "passkeyId": NSNull(),
            "passwordUrl": "https://portal/createPassword?flowId=f1",
            "pinUrl": "https://portal/createPIN?flowId=f1",
        ])

        XCTAssertEqual(
            state.credentialSetupStep,
            .portal(url: "https://portal/createPassword?flowId=f1", context: "password setup")
        )
    }

    func testCredentialSetupFallsBackToThePinCreatePage() {
        let state = snapshot(info: ["isCredentialSetup": true, "pinUrl": "https://portal/createPIN?flowId=f1"])

        XCTAssertEqual(state.credentialSetupStep, .portal(url: "https://portal/createPIN?flowId=f1", context: "PIN setup"))
    }

    func testCredentialSetupUsesThePortalPasskeyPageOnlyAsALastResort() {
        let state = snapshot(info: ["isCredentialSetup": true, "passkeyUrl": "https://portal/createAuth?flowId=f1"])

        XCTAssertEqual(
            state.credentialSetupStep,
            .portal(url: "https://portal/createAuth?flowId=f1", context: "passkey setup")
        )
    }

    func testNoCredentialSetupOutsideTheSetupProjection() {
        let state = snapshot(info: [
            "isCredentialSetup": false,
            "passkeyId": "bio-1",
            "passkeyUrl": "https://portal/loginAuth?flowId=f1",
        ])

        XCTAssertNil(state.credentialSetupStep)
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

    // MARK: OAuth and external wallet on auth v2

    func testNewAuthenticateMethodsAndTheExistingOnesKeepTheirSignatures() {
        let contract: (ParaManager, AuthorizationController) async throws -> Void = { manager, controller in
            let _: AuthenticationResult = try await manager.authenticateWithOAuth(
                provider: .google,
                authorizationController: controller
            )
            let _: AuthenticationResult = try await manager.authenticateWithExternalWallet(
                address: "0xabc",
                type: .evm,
                provider: "metamask",
                chainId: "1"
            ) { message in message }
            try await manager.handleOAuth(provider: .apple, authorizationController: controller)
            try await manager.loginExternalWallet(wallet: ExternalWalletInfo(address: "0xabc", type: .evm))
            try await manager.loginWithPasskey(authorizationController: controller, email: "a@b.co")
        }

        XCTAssertNotNil(contract as Any)
    }

    func testOAuthSnapshotPrefersTheFullPortalUrl() {
        let state = snapshot(info: [
            "oauthUrl": "https://short/abc",
            "oauthFullUrl": "https://portal/v2/login/google?flowId=f1",
            "userId": "u1",
        ])

        XCTAssertEqual(state.oauthUrl, "https://portal/v2/login/google?flowId=f1")
        XCTAssertEqual(state.userId, "u1")
        XCTAssertEqual(snapshot(info: ["oauthUrl": "https://short/abc"]).oauthUrl, "https://short/abc")
        XCTAssertNil(snapshot(info: ["oauthUrl": NSNull()]).oauthUrl)
    }

    func testPortalHandsAPasskeyParkBackToTheApp() {
        XCTAssertEqual(
            AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=PASSKEY_REQUIRED&userId=u1")),
            .nativePasskey(userId: "u1")
        )
        XCTAssertEqual(
            AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=PASSKEY_REQUIRED")),
            .nativePasskey(userId: nil)
        )
    }

    func testOrdinaryPortalReturnsAreNotHandBacks() {
        XCTAssertNil(AuthV2PortalHandBack.resolve(nil))
        XCTAssertNil(AuthV2PortalHandBack.resolve(URL(string: "myapp://")))
        XCTAssertNil(AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=COMPLETE")))
        XCTAssertNil(AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=NEW_USER")))
    }

    func testExternalWalletResult() {
        XCTAssertEqual(
            ExternalWalletV2Result.resolve(["status": "authenticated", "isNewUser": true]),
            ExternalWalletV2Result(isNewUser: true)
        )
        XCTAssertEqual(
            ExternalWalletV2Result.resolve(["status": "authenticated"]),
            ExternalWalletV2Result(isNewUser: false)
        )
    }

    func testExternalWalletResultsOtherThanASessionAreRejected() {
        XCTAssertNil(ExternalWalletV2Result.resolve(nil))
        XCTAssertNil(ExternalWalletV2Result.resolve(["isNewUser": true]))
        XCTAssertNil(ExternalWalletV2Result.resolve(["status": "passkey_required", "userId": "u1"]))
        XCTAssertNil(ExternalWalletV2Result.resolve(["status": "portal_required", "url": "https://short/w"]))
        XCTAssertNil(ExternalWalletV2Result.resolve(["status": "needs_second_factor"]))
    }

    func testCapabilitiesDefaultToLegacy() {
        XCTAssertEqual(NativeAuthV2Capabilities(nil), .none)
        XCTAssertEqual(NativeAuthV2Capabilities(["oauth": true]), NativeAuthV2Capabilities(oauth: true, externalWallet: false))
        XCTAssertEqual(
            NativeAuthV2Capabilities(["oauth": true, "externalWallet": true]),
            NativeAuthV2Capabilities(oauth: true, externalWallet: true)
        )
    }
}
