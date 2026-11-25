import AuthenticationServices
import Foundation
import os
import SwiftUI
import UIKit

// MARK: - Portal Presentation Seam

@MainActor
protocol OnRampPortalPresenting: AnyObject {
    func present(url: URL, callbackURLScheme: String) async throws -> URL
}

private final class SingleResumeContinuationBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}

private final class SessionCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var session: ASWebAuthenticationSession?

    func store(_ session: ASWebAuthenticationSession) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func cancelAndClear() {
        lock.lock()
        let current = session
        session = nil
        lock.unlock()
        current?.cancel()
    }

    func clear() {
        lock.lock()
        session = nil
        lock.unlock()
    }
}

private final class PortalPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let resolve: @MainActor () -> ASPresentationAnchor = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
                return keyWindow
            }
            if let firstWindow = scenes.flatMap(\.windows).first {
                return firstWindow
            }
            if let firstScene = scenes.first {
                return UIWindow(windowScene: firstScene)
            }
            return ASPresentationAnchor()
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated(resolve)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(resolve)
        }
    }
}

@MainActor
private final class ASWebAuthenticationPortalPresenter: OnRampPortalPresenting {
    func present(url: URL, callbackURLScheme: String) async throws -> URL {
        try Task.checkCancellation()

        let sessionBox = SessionCancellationBox()
        let continuationHolder = LockProtectedContinuationBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let contBox = SingleResumeContinuationBox<URL>(continuation)
                continuationHolder.store(contBox)

                if Task.isCancelled {
                    sessionBox.cancelAndClear()
                    contBox.resume(throwing: CancellationError())
                    return
                }

                let contextProvider = PortalPresentationContextProvider()
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackURLScheme
                ) { callbackURL, error in
                    sessionBox.clear()
                    _ = contextProvider
                    if let error {
                        contBox.resume(throwing: error)
                    } else if let callbackURL {
                        contBox.resume(returning: callbackURL)
                    } else {
                        contBox.resume(throwing: ParaError.error("On-ramp portal completed without a callback URL"))
                    }
                }
                session.presentationContextProvider = contextProvider
                sessionBox.store(session)

                if Task.isCancelled {
                    sessionBox.cancelAndClear()
                    contBox.resume(throwing: CancellationError())
                    return
                }

                if !session.start() {
                    sessionBox.clear()
                    contBox.resume(throwing: ParaError.error("Failed to start ASWebAuthenticationSession"))
                }
            }
        } onCancel: {
            continuationHolder.resumeCancellation()
            Task { @MainActor in
                sessionBox.cancelAndClear()
            }
        }
    }
}

private final class LockProtectedContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var box: SingleResumeContinuationBox<URL>?

    func store(_ box: SingleResumeContinuationBox<URL>) {
        lock.lock()
        self.box = box
        lock.unlock()
    }

    func resumeCancellation() {
        lock.lock()
        let current = box
        box = nil
        lock.unlock()
        current?.resume(throwing: CancellationError())
    }
}

// MARK: - Bridge Wire Payloads

private struct GetOnRampConfigArgs: Encodable {
    let walletTypes: [String]?
}

private struct GetOnRampCatalogArgs: Encodable {
    let search: String?
    let networkId: String?
    let limit: Int?
    let offset: Int?
    let testMode: Bool?
}

private struct CreateOnRampOrderNestedParams: Encodable {
    let type: ParaOnRampPurchaseType
    let walletType: String?
    let provider: ParaOnRampProvider
    let address: String?
    let assetImplementationId: String?
    let assetSelector: ParaOnRampAssetSelector?
    let asset: String?
    let network: String?
    let fiat: String?
    let fiatQuantity: String?
    let assetQuantity: String?
    let paymentMethod: ParaOnRampPaymentMethod?
    let returnUrl: String?
    let purchaseId: String?
    let testMode: Bool?
}

private struct CreateOnRampOrderBridgeArgs: Encodable {
    let walletId: String?
    let externalWalletAddress: String?
    let nativeCallbackUrl: String?
    let params: CreateOnRampOrderNestedParams
}

private struct GetOnRampOrderArgs: Encodable {
    let purchaseId: String
    let walletId: String?
    let externalWalletAddress: String?
    let walletType: String?
    let address: String?
}

private struct SendOffRampDepositPurchaseArgs: Encodable {
    let id: String
    let walletId: String?
    let externalWalletAddress: String?
    let walletType: String?
    let provider: ParaOnRampProvider?
    let address: String?
    let testMode: Bool?
}

private struct SendOffRampDepositRequestArgs: Encodable {
    let destinationAddress: String
    let assetQuantity: String
    let chainId: String?
    let contractAddress: String?
    let asset: String?
    let network: String?
    let fiat: String?
    let fiatQuantity: String?
    let providerOrderId: String?
}

private struct SendOffRampDepositBridgeArgs: Encodable {
    let onRampPurchase: SendOffRampDepositPurchaseArgs
    let depositRequest: SendOffRampDepositRequestArgs
}

private struct LinkBraleAchBankArgs: Encodable {
    let checkoutId: String
    let publicToken: String
}

private struct GetBraleAchAuthorizationArgs: Encodable {
    let amountLabel: String
    let bankLabel: String?
}

private struct SubmitBraleAchDepositArgs: Encodable {
    let checkoutId: String
    let authorizationTextVersion: String?
}

private struct GetBraleAchCheckoutArgs: Encodable {
    let checkoutId: String
}

private struct SettleCoinbaseOnrampPurchaseArgs: Encodable {
    let purchaseId: String
    let walletId: String?
    let externalWalletAddress: String?
}

// MARK: - On-Ramp & Off-Ramp Operations

public extension ParaManager {
    /// Stream of unsolicited on-ramp events (`ONRAMP_LAUNCHED`, `ONRAMP_TRANSACTION_COMPLETE_V2`).
    nonisolated var onRampEvents: AsyncStream<ParaOnRampEvent> {
        onRampEventBroadcaster.makeStream()
    }

    /// Fetches partner-level on-ramp configuration flags and defaults.
    func getOnRampConfig(walletTypes: [String]? = nil) async throws -> ParaOnRampConfig {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "getOnRampConfig",
            payload: GetOnRampConfigArgs(walletTypes: walletTypes)
        )
        return try decodeOnRampDecodable(result, as: ParaOnRampConfig.self, method: "getOnRampConfig")
    }

    /// Searches and paginates the partner's configured on-ramp asset catalog.
    func getOnRampCatalog(
        search: String? = nil,
        networkId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        testMode: Bool? = nil
    ) async throws -> ParaOnRampCatalogResponse {
        try await ensureWebViewReady()
        let args = GetOnRampCatalogArgs(
            search: search,
            networkId: networkId,
            limit: limit,
            offset: offset,
            testMode: testMode
        )
        let result = try await postMessage(method: "getOnRampCatalog", payload: args)
        return try decodeOnRampDecodable(result, as: ParaOnRampCatalogResponse.self, method: "getOnRampCatalog")
    }

    /// Creates a hosted portal on-ramp or off-ramp order and returns the purchase plus its portal launch URL.
    func createHostedOnRampOrder(_ params: ParaCreateHostedOnRampOrderParams) async throws -> ParaCreateHostedOnRampOrderResult {
        try await ensureWebViewReady()
        let wirePayload = CreateOnRampOrderBridgeArgs(
            walletId: params.walletId,
            externalWalletAddress: params.externalWalletAddress,
            nativeCallbackUrl: params.nativeCallbackUrl,
            params: CreateOnRampOrderNestedParams(
                type: params.type,
                walletType: params.walletType,
                provider: params.provider,
                address: params.address,
                assetImplementationId: params.assetImplementationId,
                assetSelector: params.assetSelector,
                asset: params.asset,
                network: params.network,
                fiat: params.fiat,
                fiatQuantity: params.fiatQuantity,
                assetQuantity: params.assetQuantity,
                paymentMethod: params.paymentMethod,
                returnUrl: params.returnUrl,
                purchaseId: params.purchaseId,
                testMode: params.testMode
            )
        )
        let result = try await postMessage(method: "createHostedOnRampOrder", payload: wirePayload)
        return try decodeOnRampDecodable(result, as: ParaCreateHostedOnRampOrderResult.self, method: "createHostedOnRampOrder")
    }

    /// Launches the hosted on-ramp portal URL in an authentication browser session and returns the callback URL, or `nil` if cancelled.
    func launchOnRampPortal(
        portalUrl: URL,
        callbackURLScheme: String? = nil,
        webAuthenticationSession overrideSession: WebAuthenticationSession? = nil
    ) async throws -> URL? {
        try Task.checkCancellation()
        let launch = try Self.buildOnRampPortalLaunchURL(
            portalUrl: portalUrl,
            callbackURLScheme: callbackURLScheme,
            fallbackAppScheme: appScheme
        )

        if let host = launch.url.host {
            logger.debug("Launching on-ramp portal host=\(host, privacy: .public) path=\(launch.url.path, privacy: .public)")
        }

        do {
            let callbackURL: URL
            if let session = overrideSession ?? defaultWebAuthenticationSession {
                callbackURL = try await session.authenticate(
                    using: launch.url,
                    callbackURLScheme: launch.callbackScheme
                )
            } else {
                let presenter = onRampPortalPresenter ?? ASWebAuthenticationPortalPresenter()
                callbackURL = try await presenter.present(
                    url: launch.url,
                    callbackURLScheme: launch.callbackScheme
                )
            }

            let parsed = Self.parseOnRampPortalCallback(callbackURL)
            logger.debug(
                "On-ramp portal callback received purchaseId=\(parsed.purchaseId ?? "none", privacy: .public) status=\(parsed.rawStatus ?? "none", privacy: .public)"
            )
            return callbackURL
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            {
                logger.info("On-ramp portal session cancelled by user")
                return nil
            }
            logger.error("On-ramp portal failed: \(ParaWebView.redactLogMessage(error.localizedDescription))")
            throw error
        }
    }

    /// Fetches the current status of a ramp purchase and any pending off-ramp deposit request.
    func getOnRampOrder(
        walletId: String? = nil,
        purchaseId: String,
        externalWalletAddress: String? = nil,
        walletType: String? = nil,
        address: String? = nil
    ) async throws -> ParaOnRampOrder {
        let normalizedWalletId = nonEmptyTrimmed(walletId)
        let normalizedExternalWalletAddress = nonEmptyTrimmed(externalWalletAddress)
        let normalizedAddress = nonEmptyTrimmed(address)
        let normalizedWalletType = nonEmptyTrimmed(walletType)
        let resolvedExternalAddress = normalizedExternalWalletAddress ?? normalizedAddress
        guard normalizedWalletId != nil || resolvedExternalAddress != nil else {
            throw ParaError.error("Either walletId or externalWalletAddress is required to fetch an on-ramp order.")
        }

        try await ensureWebViewReady()
        let args = GetOnRampOrderArgs(
            purchaseId: purchaseId,
            walletId: normalizedWalletId,
            externalWalletAddress: normalizedExternalWalletAddress,
            walletType: normalizedWalletType,
            address: normalizedAddress
        )
        let result = try await postMessage(method: "getOnRampOrder", payload: args)
        return try decodeOnRampDecodable(result, as: ParaOnRampOrder.self, method: "getOnRampOrder")
    }

    /// Signs and submits the on-chain deposit transaction for an off-ramp order.
    func sendOffRampDeposit(_ params: ParaSendOffRampDepositParams) async throws -> ParaSendOffRampDepositResult {
        try await ensureWebViewReady()
        let wirePayload = SendOffRampDepositBridgeArgs(
            onRampPurchase: SendOffRampDepositPurchaseArgs(
                id: params.purchaseId,
                walletId: params.walletId,
                externalWalletAddress: params.externalWalletAddress,
                walletType: params.walletType,
                provider: params.provider,
                address: params.address,
                testMode: params.testMode
            ),
            depositRequest: SendOffRampDepositRequestArgs(
                destinationAddress: params.destinationAddress,
                assetQuantity: params.assetQuantity,
                chainId: params.chainId,
                contractAddress: params.contractAddress,
                asset: params.asset,
                network: params.network,
                fiat: params.fiat,
                fiatQuantity: params.fiatQuantity,
                providerOrderId: params.providerOrderId
            )
        )
        let result = try await postMessage(method: "sendOffRampDeposit", payload: wirePayload)
        return try decodeOnRampDecodable(result, as: ParaSendOffRampDepositResult.self, method: "sendOffRampDeposit")
    }

    // MARK: - Brale ACH

    /// Starts a Brale ACH checkout, defaulting `platform` to `"ios"` when not supplied.
    func createBraleAchCheckout(_ params: ParaCreateBraleAchCheckoutParams) async throws -> ParaBraleAchCheckout {
        try await ensureWebViewReady()
        let trimmedPlatform = params.platform?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = (trimmedPlatform?.isEmpty == false) ? params : params.withPlatform("ios")
        let result = try await postMessage(method: "createBraleAchCheckout", payload: payload)
        return try decodeOnRampDecodable(result, as: ParaBraleAchCheckout.self, method: "createBraleAchCheckout")
    }

    /// Registers a Plaid public token with an open Brale ACH checkout.
    func linkBraleAchBank(checkoutId: String, publicToken: String) async throws -> ParaBraleAchCheckout {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "linkBraleAchBank",
            payload: LinkBraleAchBankArgs(checkoutId: checkoutId, publicToken: publicToken)
        )
        return try decodeOnRampDecodable(result, as: ParaBraleAchCheckout.self, method: "linkBraleAchBank")
    }

    /// Fetches the current Brale ACH debit authorization text and version to display before submission.
    func getBraleAchAuthorization(amountLabel: String, bankLabel: String? = nil) async throws -> ParaBraleAchAuthorization {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "getBraleAchAuthorization",
            payload: GetBraleAchAuthorizationArgs(amountLabel: amountLabel, bankLabel: bankLabel)
        )
        return try decodeOnRampDecodable(result, as: ParaBraleAchAuthorization.self, method: "getBraleAchAuthorization")
    }

    /// Submits the Brale ACH debit for a linked checkout.
    func submitBraleAchDeposit(
        checkoutId: String,
        authorizationTextVersion: String? = nil
    ) async throws -> ParaBraleAchCheckout {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "submitBraleAchDeposit",
            payload: SubmitBraleAchDepositArgs(
                checkoutId: checkoutId,
                authorizationTextVersion: authorizationTextVersion
            )
        )
        return try decodeOnRampDecodable(result, as: ParaBraleAchCheckout.self, method: "submitBraleAchDeposit")
    }

    /// Reads the current stage of a Brale ACH checkout.
    func getBraleAchCheckout(checkoutId: String) async throws -> ParaBraleAchCheckout {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "getBraleAchCheckout",
            payload: GetBraleAchCheckoutArgs(checkoutId: checkoutId)
        )
        return try decodeOnRampDecodable(result, as: ParaBraleAchCheckout.self, method: "getBraleAchCheckout")
    }

    /// Lists submitted Brale ACH transfers for the current user, newest first.
    func listBraleAchTransfers() async throws -> ParaBraleTransferListResponse {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "listBraleAchTransfers", payload: EmptyPayload())
        return try decodeOnRampDecodable(result, as: ParaBraleTransferListResponse.self, method: "listBraleAchTransfers")
    }

    // MARK: - Coinbase Headless

    /// Creates a Coinbase (CDP) headless on-ramp order or quote.
    func createCoinbaseOnrampOrder(_ params: ParaCoinbaseOrderParams) async throws -> ParaCoinbaseOrderResult {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "createCoinbaseOnrampOrder", payload: params)
        return try decodeOnRampDecodable(result, as: ParaCoinbaseOrderResult.self, method: "createCoinbaseOnrampOrder")
    }

    /// Checks the user's Coinbase guest-checkout limits and whether an identity upgrade can be requested.
    func checkCoinbaseOnrampLimits(_ params: ParaCoinbaseLimitsParams) async throws -> ParaCoinbaseLimitsResult {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "checkCoinbaseOnrampLimits", payload: params)
        return try decodeOnRampDecodable(result, as: ParaCoinbaseLimitsResult.self, method: "checkCoinbaseOnrampLimits")
    }

    /// Mints a single-use Coinbase embedded identity upgrade URL.
    func createCoinbaseOnrampLimitUpgrade(
        _ params: ParaCoinbaseLimitUpgradeParams
    ) async throws -> ParaCoinbaseLimitUpgradeResult {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "createCoinbaseOnrampLimitUpgrade", payload: params)
        return try decodeOnRampDecodable(
            result,
            as: ParaCoinbaseLimitUpgradeResult.self,
            method: "createCoinbaseOnrampLimitUpgrade"
        )
    }

    /// Reconciles a Coinbase on-ramp purchase server-side and returns its updated status string.
    func settleCoinbaseOnrampPurchase(
        purchaseId: String,
        walletId: String? = nil,
        externalWalletAddress: String? = nil
    ) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(
            method: "settleCoinbaseOnrampPurchase",
            payload: SettleCoinbaseOnrampPurchaseArgs(
                purchaseId: purchaseId,
                walletId: walletId,
                externalWalletAddress: externalWalletAddress
            )
        )
        if let status = result as? String {
            return status
        }
        if let dict = result as? [String: Any], let status = dict["status"] as? String {
            return status
        }
        throw ParaError.bridgeError("KEY_ERROR<settleCoinbaseOnrampPurchase-status>: Missing or invalid status in response")
    }

    /// Parses a WKScriptMessage JSON payload from a Coinbase headless Apple Pay payment page.
    nonisolated static func parseCoinbaseApplePayEvent(
        _ rawMessage: String,
        origin: String? = nil,
        allowedOrigins: [String]? = nil
    ) -> ParaCoinbaseApplePayEvent? {
        if let allowedOrigins {
            guard let callerOrigin = normalizedURLOrigin(from: origin),
                  allowedOrigins.contains(where: { normalizedURLOrigin(from: $0) == callerOrigin })
            else {
                return nil
            }
        }

        guard let data = rawMessage.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let candidateName = (dict["eventName"] as? String) ?? (dict["type"] as? String)
        guard let eventName = candidateName,
              eventName.hasPrefix(ParaCoinbaseApplePayEvent.eventPrefix)
        else {
            return nil
        }

        var detail: ParaCoinbaseApplePayEventErrorDetail?
        if let rawData = dict["data"] as? [String: Any] {
            let errorCode = rawData["errorCode"] as? String
            let errorMessage = rawData["errorMessage"] as? String
            if errorCode != nil || errorMessage != nil {
                detail = ParaCoinbaseApplePayEventErrorDetail(errorCode: errorCode, errorMessage: errorMessage)
            }
        }

        return ParaCoinbaseApplePayEvent(eventName: eventName, data: detail)
    }

    private nonisolated static func normalizedURLOrigin(from raw: String?) -> String? {
        guard let raw,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }
        let defaultPort = scheme == "https" ? 443 : 80
        let portSuffix = components.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(portSuffix)"
    }

    /// Parses status, purchaseId, and error query parameters from an on-ramp portal return deep link.
    nonisolated static func parseOnRampPortalCallback(_ url: URL) -> ParaOnRampPortalCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : raw
        }
        let rawStatus = value("status")
        let parsedStatus = rawStatus.flatMap { ParaOnRampPurchaseStatus(rawValue: $0.uppercased()) }
        return ParaOnRampPortalCallback(
            status: parsedStatus,
            rawStatus: rawStatus,
            purchaseId: value("purchaseId"),
            error: value("error")
        )
    }
}

// MARK: - Helpers

extension ParaManager {
    private nonisolated static func validateCallbackSchemeInput(_ raw: String) throws -> (callbackValue: String, scheme: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParaError.error("Invalid callback URL scheme")
        }

        let callbackValue: String
        let rawScheme: String
        if let range = trimmed.range(of: "://") {
            rawScheme = String(trimmed[..<range.lowerBound])
            callbackValue = trimmed
        } else if trimmed.hasSuffix(":") {
            rawScheme = String(trimmed.dropLast())
            callbackValue = "\(rawScheme)://"
        } else {
            rawScheme = trimmed
            callbackValue = "\(trimmed)://"
        }

        guard !rawScheme.isEmpty,
              let schemeRange = rawScheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression),
              schemeRange == rawScheme.startIndex ..< rawScheme.endIndex
        else {
            throw ParaError.error("Invalid callback URL scheme")
        }

        return (callbackValue, rawScheme)
    }

    nonisolated static func buildOnRampPortalLaunchURL(
        portalUrl: URL,
        callbackURLScheme: String?,
        fallbackAppScheme: String
    ) throws -> (url: URL, callbackScheme: String) {
        guard let portalScheme = portalUrl.scheme?.lowercased(),
              portalScheme == "http" || portalScheme == "https",
              let portalHost = portalUrl.host,
              !portalHost.isEmpty
        else {
            throw ParaError.error("Invalid on-ramp portal URL")
        }

        let resolved: (callbackValue: String, scheme: String) = if let callbackURLScheme {
            try validateCallbackSchemeInput(callbackURLScheme)
        } else {
            try validateCallbackSchemeInput(fallbackAppScheme)
        }

        guard var components = URLComponents(url: portalUrl, resolvingAgainstBaseURL: false) else {
            throw ParaError.error("Invalid on-ramp portal URL")
        }

        let strictAllowed: CharacterSet = {
            var cs = CharacterSet.urlQueryAllowed
            cs.remove(charactersIn: "+&=/:?")
            return cs
        }()
        let encodedName = "nativeCallbackUrl"
        let encodedValue = resolved.callbackValue.addingPercentEncoding(withAllowedCharacters: strictAllowed) ?? resolved.callbackValue

        var pairs = (components.percentEncodedQuery ?? "")
            .split(separator: "&", omittingEmptySubsequences: true)
            .map(String.init)

        if let index = pairs.firstIndex(where: { $0 == encodedName || $0.hasPrefix("\(encodedName)=") }) {
            pairs[index] = "\(encodedName)=\(encodedValue)"
        } else {
            pairs.append("\(encodedName)=\(encodedValue)")
        }
        components.percentEncodedQuery = pairs.joined(separator: "&")

        guard let finalUrl = components.url else {
            throw ParaError.error("Failed to construct on-ramp portal URL")
        }
        return (finalUrl, resolved.scheme)
    }

    private nonisolated func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func decodeOnRampDecodable<T: Decodable>(_ result: Any?, as type: T.Type, method: String) throws -> T {
        guard let result, !(result is NSNull) else {
            throw ParaError.bridgeError("METHOD_ERROR<\(method)>: Empty response from bridge")
        }

        let data: Data
        if let rawData = result as? Data {
            data = rawData
        } else if let jsonString = result as? String, let stringData = jsonString.data(using: .utf8) {
            data = stringData
        } else if JSONSerialization.isValidJSONObject(result) {
            data = try JSONSerialization.data(withJSONObject: result, options: [])
        } else {
            throw ParaError.bridgeError(
                "METHOD_ERROR<\(method)>: Invalid result format expected \(T.self)"
            )
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ParaError.bridgeError(
                "DECODE_ERROR<\(method)>: Failed to decode \(T.self): \(ParaWebView.redactLogMessage(error.localizedDescription))"
            )
        }
    }
}
