import AuthenticationServices
import Foundation
import LocalAuthentication
import SwiftUI

// MARK: - Auth v2 state

/// A snapshot of the bridge's core state (`getCurrentState`), reduced to what the v2 email/phone flow reads.
///
/// Auth v2 publishes its portal hand-off URLs into core state while `authenticateWithEmailOrPhone` is still
/// pending — the bridge only answers each request once — so the native side polls this alongside the call.
struct AuthV2Snapshot {
    let corePhase: String?
    let authPhase: String?
    let error: String?
    let isNewUser: Bool
    let hasPasskey: Bool
    let isCredentialSetup: Bool
    let passkeyUrl: String?
    /// The pending passkey row core minted for a new user's credential setup; native creation completes it.
    let passkeyId: String?
    let passwordUrl: String?
    let pinUrl: String?
    let verificationUrl: String?
    /// The portal page that starts an OAuth provider round-trip.
    let oauthUrl: String?
    /// The account the flow resolved to, once known.
    let userId: String?

    init(_ dict: [String: Any]) {
        let info = dict["authStateInfo"] as? [String: Any] ?? [:]
        corePhase = dict["corePhase"] as? String
        authPhase = dict["authPhase"] as? String
        error = dict["error"] as? String
        isNewUser = info["isNewUser"] as? Bool ?? false
        hasPasskey = info["hasPasskey"] as? Bool ?? false
        isCredentialSetup = info["isCredentialSetup"] as? Bool ?? false
        passkeyUrl = info["passkeyUrl"] as? String
        passkeyId = info["passkeyId"] as? String
        passwordUrl = info["passwordUrl"] as? String
        pinUrl = info["pinUrl"] as? String
        verificationUrl = info["verificationUrl"] as? String
        // The full URL never needs the shortener round-trip; the short one is only a fallback.
        oauthUrl = info["oauthFullUrl"] as? String ?? info["oauthUrl"] as? String
        userId = info["userId"] as? String
    }

    /// The whole flow — session and wallets — is done.
    var isAuthenticated: Bool {
        corePhase == "authenticated"
    }

    /// The flow has started and its portal hand-off URLs are published. Core passes through
    /// `awaiting_session_start` straight into polling for the session (`waiting_for_session`), so a poll
    /// usually lands on the second; the URLs stay projected through both.
    var isAwaitingPortal: Bool {
        authPhase == "awaiting_session_start" || authPhase == "waiting_for_session"
    }

    /// Core's error message when the flow has failed.
    var failure: String? {
        guard authPhase == "error" || corePhase == "error" else { return nil }
        return error ?? "Authentication failed"
    }

    /// How a new user creates their first credential, once the session is minted.
    var credentialSetupStep: AuthV2CredentialSetupStep? {
        AuthV2CredentialSetupStep.resolve(self)
    }

    /// The portal finished its verification step: the session is live, or a credential setup became owed.
    var isPastVerification: Bool {
        isAuthenticated || credentialSetupStep != nil
    }

    /// The portal finished the credential-setup step: signed in, or no longer owing a credential while the flow is
    /// still live. Setup is already owed before that page opens, so owing it proves nothing.
    var isPastCredentialSetup: Bool {
        isAuthenticated || (credentialSetupStep == nil && authPhase != "unauthenticated" && authPhase != "error")
    }
}

/// How a new user creates the first credential their account owes.
enum AuthV2CredentialSetupStep: Equatable {
    /// Create the passkey natively against the pending row core minted, as the legacy native signup does.
    /// The portal's create page can't run WebAuthn inside a web authentication session.
    case nativePasskey(biometricsId: String)
    /// Open this portal create page.
    case portal(url: String, context: String)

    /// Passkey first, matching the legacy signup preference; then password, then PIN for partners that only
    /// offer PIN. The portal passkey page is a last resort for a projection without a pending passkey row.
    static func resolve(_ snapshot: AuthV2Snapshot) -> AuthV2CredentialSetupStep? {
        guard snapshot.isCredentialSetup else { return nil }
        if let id = snapshot.passkeyId {
            return .nativePasskey(biometricsId: id)
        }
        if let url = snapshot.passwordUrl {
            return .portal(url: url, context: "password setup")
        }
        if let url = snapshot.pinUrl {
            return .portal(url: url, context: "PIN setup")
        }
        if let url = snapshot.passkeyUrl {
            return .portal(url: url, context: "passkey setup")
        }
        return nil
    }
}

/// What the v2 email/phone flow does once the flow has started.
enum AuthV2FirstStep: Equatable {
    /// Returning passkey user: run the native passkey login. Native passkeys stay on the legacy biometrics
    /// routes until they become a v2 login factor.
    case nativePasskey
    /// Open this portal page (OTP, or a returning user's credential unlock).
    case portal(url: String, context: String)

    static func resolve(_ snapshot: AuthV2Snapshot, nativePasskeySupported: Bool) -> AuthV2FirstStep? {
        if !snapshot.isNewUser, snapshot.hasPasskey, nativePasskeySupported {
            return .nativePasskey
        }
        // Core leaves the OTP URL null for a returning user who unlocks with a credential instead.
        if let url = snapshot.verificationUrl {
            return .portal(url: url, context: "verification")
        }
        if let url = snapshot.passwordUrl {
            return .portal(url: url, context: "password")
        }
        if let url = snapshot.passkeyUrl {
            return .portal(url: url, context: "passkey")
        }
        return nil
    }
}

/// The outcome of `authenticateWithEmailOrPhone`.
public struct AuthenticationResult {
    /// The authenticated Para user id.
    public let userId: String
    /// Whether this sign-in created the account.
    public let isNewUser: Bool
}

// MARK: - Authentication

public extension ParaManager {
    /// Signs a user up or in with their email or phone, running the whole flow to an authenticated session.
    ///
    /// Works on both Para auth flows. Where Para auth v2 is enabled, the user verifies in the Para portal (so a
    /// `WebAuthenticationSession` is required). A new user creates their first credential natively when it's a
    /// passkey, and in the portal otherwise; returning passkey users still sign in with their native passkey. Everywhere else this runs the legacy flow, asking
    /// `verificationCodeProvider` for the code the user was sent.
    ///
    /// - Parameters:
    ///   - auth: The user's email or phone.
    ///   - authorizationController: Runs native passkey creation and sign-in.
    ///   - webAuthenticationSession: Presents Para's hosted pages. Falls back to the default session.
    ///   - verificationCodeProvider: Collects the one-time code on the legacy flow. It's called again with the
    ///     error when a code is rejected, so the app can show it and ask for another. Throw to cancel.
    /// - Returns: The authenticated user.
    @MainActor
    func authenticateWithEmailOrPhone(
        auth: Auth,
        authorizationController: AuthorizationController,
        webAuthenticationSession overrideSession: WebAuthenticationSession? = nil,
        verificationCodeProvider: @escaping @MainActor (_ previousError: Error?) async throws -> String
    ) async throws -> AuthenticationResult {
        try await ensureWebViewReady()

        if try await isAuthV2Enabled() {
            return try await authenticateWithEmailOrPhoneV2(
                auth: auth,
                authorizationController: authorizationController,
                webAuthenticationSession: overrideSession
            )
        }

        return try await authenticateWithEmailOrPhoneLegacy(
            auth: auth,
            authorizationController: authorizationController,
            webAuthenticationSession: overrideSession,
            verificationCodeProvider: verificationCodeProvider
        )
    }
}

// MARK: - Flows

private struct AuthV2Payload: Encodable {
    let auth: [String: String]

    init(_ auth: Auth) {
        switch auth {
        case let .email(email): self.auth = ["email": email]
        case let .phone(phone): self.auth = ["phone": phone]
        }
    }
}

struct EmptyAuthV2Payload: Encodable {}

/// Tracks a pending long-running v2 bridge call (`authenticateWithEmailOrPhone`, `authenticateWithOAuth`).
/// Completion is read from core state; the call's own result only matters when it fails.
@MainActor
final class PendingAuthCall {
    var failure: Error?
}

/// Upper bound for the long-running v2 bridge call. Core rejects it on its own well before this, so the native
/// request timeout never fires mid sign-in.
let authV2CallTimeout: TimeInterval = 900

/// Core's limit on retrying a rejected verification code before it fails the flow.
private let maxVerificationRetries = 3

extension ParaManager {
    /// Whether the bridge will run `authenticateWithEmailOrPhone` on auth v2. False on a bridge that predates
    /// the accessor.
    func isAuthV2Enabled() async throws -> Bool {
        do {
            return try await postMessage(method: "isAuthV2Enabled", payload: EmptyAuthV2Payload()) as? Bool ?? false
        } catch {
            logger.warning("isAuthV2Enabled unavailable on this bridge, using the legacy flow: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private func authenticateWithEmailOrPhoneLegacy(
        auth: Auth,
        authorizationController: AuthorizationController,
        webAuthenticationSession overrideSession: WebAuthenticationSession?,
        verificationCodeProvider: @MainActor (_ previousError: Error?) async throws -> String
    ) async throws -> AuthenticationResult {
        try await resetAuthFlowForNewSignIn()

        let isNewUser: Bool
        do {
            let initial = try await signUpOrLogIn(auth: auth)
            // Read before the hosted one-click path rewrites the stage to `.done`.
            isNewUser = initial.stage == .verify || initial.stage == .signup

            if initial.loginUrl != nil, initial.stage != .done, (overrideSession ?? defaultWebAuthenticationSession) == nil {
                throw ParaError.error("Missing WebAuthenticationSession. Call setDefaultWebAuthenticationSession(_:) or pass one in.")
            }

            var state = try await completeHostedAuthIfNeeded(initial, webAuthenticationSession: overrideSession)

            if state.stage == .verify {
                // Core keeps the flow open after a rejected code (up to its retry limit), so ask again while it can
                // still accept one. Anything else — the limit, an expired flow, a network failure — ends the call.
                var previousError: Error?
                var retries = 0
                while true {
                    let code = try await verificationCodeProvider(previousError)
                    do {
                        state = try await handleVerificationCode(verificationCode: code)
                        break
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        guard retries < maxVerificationRetries, try await canRetryVerificationCode() else { throw error }
                        retries += 1
                        previousError = error
                    }
                }
            }

            switch state.stage {
            case .done:
                break
            case .login:
                try await handleLogin(
                    authState: state,
                    authorizationController: authorizationController,
                    webAuthenticationSession: overrideSession
                )
            case .signup:
                guard let method = determinePreferredSignupMethod(authState: state) else {
                    throw ParaError.error("No signup methods available for this account.")
                }
                try await handleSignup(
                    authState: state,
                    method: method,
                    authorizationController: authorizationController,
                    webAuthenticationSession: overrideSession
                )
            case .verify:
                throw ParaError.error("Verification did not complete.")
            }
        } catch {
            // Leave core ready for the next attempt instead of parked on this one.
            try? await cancelAuthV2Flow()
            throw error
        }

        return try await authenticationResult(isNewUser: isNewUser)
    }

    @MainActor
    private func authenticateWithEmailOrPhoneV2(
        auth: Auth,
        authorizationController: AuthorizationController,
        webAuthenticationSession overrideSession: WebAuthenticationSession?
    ) async throws -> AuthenticationResult {
        guard let session = overrideSession ?? defaultWebAuthenticationSession else {
            throw ParaError.error("Missing WebAuthenticationSession. Call setDefaultWebAuthenticationSession(_:) or pass one in.")
        }

        // Also clears a flow an earlier attempt abandoned (e.g. the app was killed mid-portal), so the first
        // poll can't pick up its stale portal URLs.
        try await resetAuthFlowForNewSignIn()

        transmissionKeysharesLoaded = false

        let pending = PendingAuthCall()
        let authCall = Task { @MainActor in
            do {
                _ = try await self.postMessage(
                    method: "authenticateWithEmailOrPhone",
                    payload: AuthV2Payload(auth),
                    timeout: authV2CallTimeout
                )
            } catch {
                pending.failure = error
            }
        }

        let started: AuthV2Snapshot
        var signedInWithNativePasskey = false
        do {
            // cancelAuthFlow leaves an earlier attempt's `error` phase in place until this call's start lands,
            // so this wait trusts the call's own rejection rather than core's error field.
            started = try await waitForAuthV2State(pending, failOnCoreError: false) {
                $0.isAuthenticated || $0.isAwaitingPortal
            }

            if !started.isAuthenticated {
                // Like the legacy flow, returning passkey users sign in natively, but only where this device can run
                // a native passkey; otherwise they unlock on the portal (e.g. with their password).
                guard let step = AuthV2FirstStep.resolve(started, nativePasskeySupported: nativePasskeyAvailable()) else {
                    throw ParaError.error("No sign-in method is available for this account.")
                }

                switch step {
                case .nativePasskey:
                    try await cancelAuthV2Flow()
                    authCall.cancel()
                    try await loginWithPasskey(
                        authorizationController: authorizationController,
                        email: auth.email,
                        phone: auth.phone
                    )
                    signedInWithNativePasskey = true

                case let .portal(url, context):
                    try await presentAuthV2Portal(url, context: context, session: session, pending: pending)
                }
            }

            if !started.isAuthenticated, !signedInWithNativePasskey {
                try await completeAuthV2AfterPortal(
                    pending: pending,
                    session: session,
                    authorizationController: authorizationController
                ) {
                    guard let identifier = auth.email ?? auth.phone else {
                        throw ParaError.error("Missing user identifier for passkey setup.")
                    }
                    return identifier
                }
            }
        } catch {
            // Leave core ready for the next attempt; the pending call rejects once the flow is cancelled.
            try? await cancelAuthV2Flow()
            throw error
        }

        // Outside the cancel-on-failure block: the session is live, so a local hiccup here must not discard it.
        if signedInWithNativePasskey {
            return try await authenticationResult(isNewUser: false)
        }
        // Core settles `isNewUser` once authenticated (the pre-verification value is provisional).
        let finished = try? await fetchAuthV2Snapshot()
        return try await finishAuthV2(isNewUser: finished?.isNewUser ?? started.isNewUser)
    }

    /// Presents a v2 portal page and returns the deep link it closed on. If the user dismisses the sheet after the
    /// portal already finished its step, the sign-in carries on (returning nil) instead of being cancelled.
    /// `stepFinished` says what proves that; the credential-setup page passes a stricter check than verification.
    @MainActor
    @discardableResult
    func presentAuthV2Portal(
        _ url: String,
        context: String,
        session: WebAuthenticationSession,
        pending _: PendingAuthCall,
        stepFinished: (AuthV2Snapshot) -> Bool = { $0.isPastVerification }
    ) async throws -> URL? {
        do {
            return try await presentAuthUrl(url, context: context, webAuthenticationSession: session)
        } catch {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if let snapshot = try? await fetchAuthV2Snapshot(), stepFinished(snapshot) {
                return nil
            }
            throw error
        }
    }

    /// Whether this device can run a native passkey: passkeys need a device passcode.
    func nativePasskeyAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// The shared tail of every portal-verified v2 sign-in. After the portal closes the session is live, or a new
    /// user still owes their first credential: a passkey is created natively against the pending row core minted,
    /// anything else in the portal. Waits until core reports the whole flow (wallets included) authenticated.
    @MainActor
    func completeAuthV2AfterPortal(
        pending: PendingAuthCall,
        session: WebAuthenticationSession,
        authorizationController: AuthorizationController,
        passkeyIdentifier: @MainActor () async throws -> String
    ) async throws {
        // Allow for wallet creation, which runs before core reports authenticated.
        let afterPortal = try await waitForAuthV2State(pending, timeout: 180) {
            $0.isAuthenticated || $0.credentialSetupStep != nil
        }
        guard !afterPortal.isAuthenticated, let setupStep = afterPortal.credentialSetupStep else { return }

        switch setupStep {
        case let .nativePasskey(biometricsId):
            // Completing the pending row binds the passkey to this session, so core's session poll finishes the
            // flow. The passkey keeps device custody of the wallet key.
            try await generatePasskey(
                identifier: passkeyIdentifier(),
                biometricsId: biometricsId,
                authorizationController: authorizationController
            )
        case let .portal(url, context):
            try await presentAuthV2Portal(
                url,
                context: context,
                session: session,
                pending: pending,
                stepFinished: { $0.isPastCredentialSetup }
            )
        }
        // Core creates the wallets once the credential is in place.
        _ = try await waitForAuthV2State(pending, timeout: 180) { $0.isAuthenticated }
    }

    /// Returns core to a clean state before a new sign-in: cancels any flow still in progress and refuses to
    /// start over a live session. Best effort on a bridge that predates `getCurrentState`.
    @MainActor
    func resetAuthFlowForNewSignIn() async throws {
        guard let snapshot = try? await fetchAuthV2Snapshot() else { return }
        // `authPhase` reaches authenticated before wallet setup finishes and `corePhase` follows.
        if snapshot.isAuthenticated || snapshot.authPhase == "authenticated" {
            throw ParaError.error("A user is already signed in. Call logout() before signing in again.")
        }
        // cancelAuthFlow is a no-op from these phases, and waits out its timeout from guest mode.
        let idlePhases: Set<String?> = ["unauthenticated", "error"]
        if idlePhases.contains(snapshot.authPhase) || snapshot.corePhase == "guest_mode" {
            return
        }
        try? await cancelAuthV2Flow()
    }

    /// Whether core can still take another code for this verification. On a bridge that predates
    /// `getCurrentState`, only the retry cap applies.
    private func canRetryVerificationCode() async throws -> Bool {
        guard let snapshot = try? await fetchAuthV2Snapshot() else { return true }
        return snapshot.authPhase == "awaiting_account_verification"
    }

    func fetchAuthV2Snapshot() async throws -> AuthV2Snapshot {
        let result = try await postMessage(method: "getCurrentState", payload: EmptyAuthV2Payload())
        return AuthV2Snapshot(result as? [String: Any] ?? [:])
    }

    /// Polls core state until `isDone`, failing on a core error or a failed bridge call.
    @MainActor
    func waitForAuthV2State(
        _ pending: PendingAuthCall,
        timeout: TimeInterval = 60,
        failOnCoreError: Bool = true,
        until isDone: (AuthV2Snapshot) -> Bool
    ) async throws -> AuthV2Snapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let snapshot = try await fetchAuthV2Snapshot()

            if isDone(snapshot) {
                return snapshot
            }
            if failOnCoreError, let failure = snapshot.failure {
                throw ParaError.bridgeError(failure)
            }
            if let failure = pending.failure {
                throw failure
            }
            if Date() > deadline {
                throw ParaError.error("Timed out waiting for authentication to complete.")
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    func cancelAuthV2Flow() async throws {
        _ = try await postMessage(method: "cancelAuthFlow", payload: EmptyAuthV2Payload())
    }

    /// Core has already created any wallets a new user needs, so this only syncs local state.
    @MainActor
    func finishAuthV2(isNewUser: Bool, reason: String = "authenticateWithEmailOrPhone-v2") async throws -> AuthenticationResult {
        // Core's wallet setup already loaded and decrypted the transmitted shares, then discarded the login
        // key pair; loading them again here would fail on the missing key.
        transmissionKeysharesLoaded = true
        do {
            wallets = try await fetchWallets()
        } catch {
            logger.warning("Failed to refresh wallets after auth v2: \(error.localizedDescription)")
        }
        sessionState = .activeLoggedIn
        await persistCurrentSession(reason: reason)
        return try await authenticationResult(isNewUser: isNewUser)
    }

    func authenticationResult(isNewUser: Bool, fallbackUserId: String? = nil) async throws -> AuthenticationResult {
        guard let userId = try await getCurrentUserAuthDetails()?.userId ?? fallbackUserId else {
            throw ParaError.error("Authentication finished without an active session.")
        }
        return AuthenticationResult(userId: userId, isNewUser: isNewUser)
    }
}

private extension Auth {
    var email: String? {
        if case let .email(email) = self {
            return email
        }
        return nil
    }

    var phone: String? {
        if case let .phone(phone) = self {
            return phone
        }
        return nil
    }
}
