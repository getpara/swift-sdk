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
        if let error {
            dict["error"] = error
        }
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

    @MainActor
    func testCompletedOAuthPasskeySessionDoesNotNeedAuthInfo() async throws {
        // A phone-only account handed back by OAuth has a verified session ID, but no email to backfill authInfo.
        let manager = AuthResultParaManager(sessionDetails: ["userId": "phone-user"])
        let result = try await manager.authenticationResult(isNewUser: false)

        XCTAssertEqual(result.userId, "phone-user")
        XCTAssertFalse(result.isNewUser)
    }

    @MainActor
    func testAuthenticationResultPrefersTheSessionIdToTheFallback() async throws {
        let manager = AuthResultParaManager(sessionDetails: ["userId": "session-user"])
        let result = try await manager.authenticationResult(isNewUser: true, fallbackUserId: "other-user")

        XCTAssertEqual(result.userId, "session-user")
        XCTAssertTrue(result.isNewUser)
    }

    @MainActor
    func testAuthenticationResultStillRequiresAUserId() async throws {
        let manager = AuthResultParaManager(sessionDetails: [:])
        do {
            _ = try await manager.authenticationResult(isNewUser: false)
            XCTFail("An unauthenticated session must not produce an authentication result")
        } catch let ParaError.error(message) {
            XCTAssertEqual(message, "Authentication finished without an active session.")
        }

        let fallback = try await manager.authenticationResult(isNewUser: false, fallbackUserId: "fallback-user")
        XCTAssertEqual(fallback.userId, "fallback-user")
    }

    func testOwingCredentialSetupProvesVerificationButNotSetup() {
        let owing = snapshot(authPhase: "waiting_for_session", info: [
            "isNewUser": true, "isCredentialSetup": true, "passwordUrl": "https://portal/setup",
        ])

        // Closing the verification page once setup is owed carries on to setup...
        XCTAssertTrue(owing.isPastVerification)
        // ...but closing the setup page while it is still owed is a cancellation.
        XCTAssertFalse(owing.isPastCredentialSetup)
    }

    func testCredentialSetupIsDoneOnceNoLongerOwedOnALiveFlow() {
        let settled = snapshot(authPhase: "waiting_for_session", info: ["isNewUser": true])
        let signedIn = snapshot(corePhase: "authenticated", authPhase: "authenticated", info: [:])
        let cancelled = snapshot(authPhase: "unauthenticated", info: [:])

        XCTAssertTrue(settled.isPastCredentialSetup)
        XCTAssertTrue(signedIn.isPastCredentialSetup)
        XCTAssertFalse(cancelled.isPastCredentialSetup)
    }

    func testCosmosProofCarriesTheSignerAndPublicKey() throws {
        let payload = CompleteExternalWalletV2Payload(signature: "sig", cosmosSigner: "cosmos1abc", cosmosPublicKeyHex: "02ab")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String]
        XCTAssertEqual(json, ["signature": "sig", "cosmosSigner": "cosmos1abc", "cosmosPublicKeyHex": "02ab"])

        let evm = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CompleteExternalWalletV2Payload(signature: "sig")))
        XCTAssertEqual(evm as? [String: String], ["signature": "sig"])
    }

    func testSetupTakesAnOfferedFallbackWhenTheDeviceCannotCreateAPasskey() {
        let state = snapshot(authPhase: "waiting_for_session", info: [
            "isNewUser": true, "isCredentialSetup": true, "passkeyId": "bio-1", "passwordUrl": "https://portal/createPassword",
        ])

        XCTAssertEqual(
            AuthV2CredentialSetupStep.resolve(state, nativePasskeySupported: false),
            .portal(url: "https://portal/createPassword", context: "password setup")
        )
        XCTAssertEqual(AuthV2CredentialSetupStep.resolve(state, nativePasskeySupported: true), .nativePasskey(biometricsId: "bio-1"))
    }

    func testSetupStillTriesTheNativePasskeyWhenNothingElseIsOffered() {
        let state = snapshot(authPhase: "waiting_for_session", info: [
            "isNewUser": true, "isCredentialSetup": true, "passkeyId": "bio-1",
        ])

        XCTAssertEqual(AuthV2CredentialSetupStep.resolve(state, nativePasskeySupported: false), .nativePasskey(biometricsId: "bio-1"))
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
        // Without the account there is nothing to hold the passkey to, so the flow refuses it.
        XCTAssertEqual(AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=PASSKEY_REQUIRED")), .missingAccount)
        XCTAssertEqual(AuthV2PortalHandBack.resolve(URL(string: "myapp://?status=PASSKEY_REQUIRED&userId=")), .missingAccount)
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

@MainActor
private final class AuthResultParaManager: ParaManager {
    private let sessionDetails: [String: Any]

    init(sessionDetails: [String: Any]) {
        self.sessionDetails = sessionDetails
        super.init(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "test"
        )
        // This fixture answers bridge messages itself, so stop the real bridge's initialization task.
        paraWebView.initializationError = ParaWebViewError.webViewNotReady
    }

    override func ensureWebViewReady() async throws {}

    override func postMessage(method: String, payload _: Encodable, timeout _: TimeInterval?) async throws -> Any? {
        XCTAssertEqual(method, "getCurrentSessionDetails")
        return sessionDetails
    }
}
