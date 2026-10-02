import AuthenticationServices
import Foundation
import SwiftUI

// MARK: - Decisions

/// The v2 sign-in methods, beyond email/phone, that the loaded bridge can drive for a native app.
struct NativeAuthV2Capabilities: Equatable {
    let oauth: Bool
    let externalWallet: Bool

    static let none = NativeAuthV2Capabilities(oauth: false, externalWallet: false)

    init(oauth: Bool, externalWallet: Bool) {
        self.oauth = oauth
        self.externalWallet = externalWallet
    }

    init(_ result: Any?) {
        let dict = result as? [String: Any] ?? [:]
        oauth = dict["oauth"] as? Bool ?? false
        externalWallet = dict["externalWallet"] as? Bool ?? false
    }
}

/// Why a portal page closed on the app's deep link instead of finishing the step itself.
enum AuthV2PortalHandBack: Equatable {
    /// The login is parked on the account's passkey, which only the app can use. Carries the account the flow
    /// resolved to, when the portal passed it.
    case nativePasskey(userId: String?)

    static func resolve(_ callbackURL: URL?) -> AuthV2PortalHandBack? {
        guard let callbackURL,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("status") == "PASSKEY_REQUIRED" else { return nil }
        return .nativePasskey(userId: value("userId").flatMap { $0.isEmpty ? nil : $0 })
    }
}

// MARK: - Authentication

public extension ParaManager {
    /// Signs a user up or in with an OAuth provider, running the whole flow to an authenticated session.
    ///
    /// Works on both Para auth flows. Where Para auth v2 is enabled, the provider sign-in runs through the Para
    /// portal: a new user then creates their first credential (natively when it's a passkey), and a returning user
    /// whose account is protected by a passkey signs in with their native passkey. Everywhere else this runs the
    /// same legacy flow as ``handleOAuth(provider:webAuthenticationSession:authorizationController:)``.
    ///
    /// - Parameters:
    ///   - provider: The OAuth provider.
    ///   - authorizationController: Runs native passkey creation and sign-in.
    ///   - webAuthenticationSession: Presents the provider and Para's hosted pages. Falls back to the default session.
    /// - Returns: The authenticated user.
    @MainActor
    func authenticateWithOAuth(
        provider: OAuthProvider,
        authorizationController: AuthorizationController,
        webAuthenticationSession overrideSession: WebAuthenticationSession? = nil
    ) async throws -> AuthenticationResult {
        try await ensureWebViewReady()

        guard let session = overrideSession ?? defaultWebAuthenticationSession else {
            throw ParaError.error("Missing WebAuthenticationSession. Call setDefaultWebAuthenticationSession(_:) or pass one in.")
        }

        if try await isAuthV2Enabled(), await nativeAuthV2Capabilities().oauth {
            return try await authenticateWithOAuthV2(
                provider: provider,
                authorizationController: authorizationController,
                session: session
            )
        }

        let isNewUser = try await runLegacyOAuth(
            provider: provider,
            session: session,
            authorizationController: authorizationController
        )
        return try await authenticationResult(isNewUser: isNewUser)
    }

    /// Signs a user in with an external wallet they control, proving ownership with a signature where Para auth v2
    /// is enabled.
    ///
    /// On auth v2 this signs a Sign-In With Ethereum style message with `signMessage` and verifies it, without
    /// creating an embedded Para wallet. Everywhere else it runs the legacy external wallet login
    /// (``loginExternalWallet(wallet:)`` with `isConnectionOnly: false`), which doesn't ask for a signature.
    ///
    /// A connection-only session from an earlier connect (for example ``MetaMaskConnector/connect()``) is replaced.
    ///
    /// - Parameters:
    ///   - address: The wallet address.
    ///   - type: The wallet's chain type.
    ///   - provider: The wallet provider, e.g. `"metamask"`.
    ///   - chainId: The chain id the message names (e.g. `"1"`). Optional.
    ///   - uri: The URI the sign-in message names. Defaults to the Para bridge origin.
    ///   - signMessage: Signs the message with the wallet (for MetaMask, ``MetaMaskConnector/signMessage(_:account:)``)
    ///     and returns the signature. Throw to cancel.
    /// - Returns: The authenticated user.
    @MainActor
    func authenticateWithExternalWallet(
        address: String,
        type: ExternalWalletType,
        provider: String? = nil,
        chainId: String? = nil,
        uri: String? = nil,
        signMessage: @escaping @MainActor (_ message: String) async throws -> String
    ) async throws -> AuthenticationResult {
        try await ensureWebViewReady()

        if try await isAuthV2Enabled(), await nativeAuthV2Capabilities().externalWallet {
            return try await authenticateWithExternalWalletV2(
                wallet: ExternalWalletInfo(address: address, type: type, provider: provider, isConnectionOnly: false),
                chainId: chainId,
                uri: uri,
                signMessage: signMessage
            )
        }

        let state = try await performLoginExternalWallet(
            wallet: ExternalWalletInfo(address: address, type: type, provider: provider, isConnectionOnly: false)
        )
        return try await authenticationResult(
            isNewUser: state.map { $0.stage == .verify || $0.stage == .signup } ?? false,
            fallbackUserId: state?.userId
        )
    }
}

// MARK: - Flows

private struct OAuthV2Payload: Encodable {
    let method: String
    let appScheme: String
}

private struct StartExternalWalletV2Payload: Encodable {
    struct Wallet: Encodable {
        let address: String
        let type: ExternalWalletType
        let provider: String?
    }

    let externalWallet: Wallet
    let chainId: String?
    let uri: String?
}

private struct CompleteExternalWalletV2Payload: Encodable {
    let signature: String
}

/// Core's user id for a connection-only external wallet session, which is not a Para account.
private let connectionOnlyUserId = "EXTERNAL_WALLET_CONNECTION_ONLY"

extension ParaManager {
    /// What the bridge can drive beyond email/phone. None on a bridge that predates the accessor, which keeps
    /// those methods on legacy.
    func nativeAuthV2Capabilities() async -> NativeAuthV2Capabilities {
        do {
            return try await NativeAuthV2Capabilities(
                postMessage(method: "getNativeAuthV2Capabilities", payload: EmptyAuthV2Payload())
            )
        } catch {
            logger.warning("Native auth v2 capabilities unavailable on this bridge: \(error.localizedDescription)")
            return .none
        }
    }

    @MainActor
    private func authenticateWithOAuthV2(
        provider: OAuthProvider,
        authorizationController: AuthorizationController,
        session: WebAuthenticationSession
    ) async throws -> AuthenticationResult {
        try await resetAuthFlowForNewSignIn()

        transmissionKeysharesLoaded = false

        // Core opens the flow, publishes the portal URL, then polls for the session the portal mints. The app
        // scheme puts the app's deep link on the page the provider returns to, so the portal can close the sheet.
        let pending = PendingAuthCall()
        let authCall = Task { @MainActor in
            do {
                _ = try await self.postMessage(
                    method: "authenticateWithOAuth",
                    payload: OAuthV2Payload(method: provider.rawValue, appScheme: self.appScheme),
                    timeout: authV2CallTimeout
                )
            } catch {
                pending.failure = error
            }
        }

        let started: AuthV2Snapshot
        var signedInWithNativePasskey = false
        do {
            started = try await waitForAuthV2State(pending, failOnCoreError: false) {
                $0.isAuthenticated || ($0.isAwaitingPortal && $0.oauthUrl != nil)
            }

            if !started.isAuthenticated {
                guard let url = started.oauthUrl else {
                    throw ParaError.error("The OAuth sign-in page is unavailable.")
                }
                let callbackURL = try await presentAuthV2Portal(url, context: "OAuth", session: session, pending: pending)

                if case let .nativePasskey(userId) = AuthV2PortalHandBack.resolve(callbackURL) {
                    // A returning account protected by its passkey. Native passkeys stay on the legacy biometrics
                    // routes (and keep device custody), so drop the v2 flow and sign in with the passkey, holding
                    // it to the account the provider resolved.
                    try await cancelAuthV2Flow()
                    authCall.cancel()
                    try await loginWithPasskey(
                        authorizationController: authorizationController,
                        email: nil,
                        phone: nil,
                        expectedUserId: userId
                    )
                    signedInWithNativePasskey = true
                } else {
                    try await completeAuthV2AfterPortal(
                        pending: pending,
                        session: session,
                        authorizationController: authorizationController
                    ) {
                        try await self.passkeyIdentifierForCurrentSession()
                    }
                }
            }
        } catch {
            try? await cancelAuthV2Flow()
            throw error
        }

        if signedInWithNativePasskey {
            return try await authenticationResult(isNewUser: false)
        }
        let finished = try? await fetchAuthV2Snapshot()
        return try await finishAuthV2(
            isNewUser: finished?.isNewUser ?? started.isNewUser,
            reason: "authenticateWithOAuth-v2"
        )
    }

    @MainActor
    private func authenticateWithExternalWalletV2(
        wallet: ExternalWalletInfo,
        chainId: String?,
        uri: String?,
        signMessage: @MainActor (_ message: String) async throws -> String
    ) async throws -> AuthenticationResult {
        // A wallet connect (MetaMaskConnector.connect) leaves a connection-only session, which core reports as
        // signed in. It isn't a Para account, so replace it rather than refuse.
        if try await hasConnectionOnlySession() {
            try await logout()
        }
        try await resetAuthFlowForNewSignIn()

        let finished: [String: Any]
        do {
            let started = try await postMessage(
                method: "startNativeExternalWalletAuth",
                payload: StartExternalWalletV2Payload(
                    externalWallet: .init(address: wallet.address, type: wallet.type, provider: wallet.provider),
                    chainId: chainId,
                    uri: uri
                ),
                timeout: 60
            )
            guard let message = (started as? [String: Any])?["message"] as? String else {
                throw ParaError.bridgeError("Missing sign-in message for the external wallet.")
            }

            let signature = try await signMessage(message)

            // Verifies the signature and waits for the session; a verify-only login has no wallets to create.
            let result = try await postMessage(
                method: "completeNativeExternalWalletAuth",
                payload: CompleteExternalWalletV2Payload(signature: signature),
                timeout: 180
            )
            finished = result as? [String: Any] ?? [:]
        } catch {
            try? await cancelAuthV2Flow()
            throw error
        }

        // The wallet proved control of its address and nothing else: no Para wallet shares exist to load.
        transmissionKeysharesLoaded = true
        sessionState = .activeLoggedIn
        await persistCurrentSession(reason: "authenticateWithExternalWallet-v2")
        let snapshot = try? await fetchAuthV2Snapshot()
        return try await authenticationResult(
            isNewUser: finished["isNewUser"] as? Bool ?? false,
            fallbackUserId: snapshot?.userId
        )
    }

    /// Whether core is signed in without a Para account behind it: a connection-only external wallet.
    private func hasConnectionOnlySession() async throws -> Bool {
        guard let snapshot = try? await fetchAuthV2Snapshot(),
              snapshot.isAuthenticated || snapshot.authPhase == "authenticated"
        else { return false }
        let details = try await postMessage(method: "getCurrentSessionDetails", payload: EmptyAuthV2Payload())
        let userId = (details as? [String: Any])?["userId"] as? String
        return userId == nil || userId == connectionOnlyUserId
    }

    /// The name a new passkey is saved under: the account's email or phone when the session knows one (OAuth
    /// providers usually share an email), else its user id.
    private func passkeyIdentifierForCurrentSession() async throws -> String {
        let details = try? await getCurrentUserAuthDetails()
        if let identifier = details?.email ?? details?.phone ?? details?.userId {
            return identifier
        }
        if let userId = try? await fetchAuthV2Snapshot().userId {
            return userId
        }
        throw ParaError.error("Missing user identifier for passkey setup.")
    }
}
