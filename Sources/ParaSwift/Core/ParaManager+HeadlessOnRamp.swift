import Foundation

/// Bridge surface required by `ParaHeadlessOnRampCheckout`.
@MainActor
public protocol ParaHeadlessOnRampClient: AnyObject {
    var environment: ParaEnvironment { get }

    func getHeadlessOnRampQuote(_ params: ParaHeadlessOnRampQuoteParams) async throws -> ParaHeadlessOnRampQuoteResult
    func getHeadlessOnRampRequirements(_ params: ParaHeadlessOnRampRequirementsParams) async throws -> ParaHeadlessOnRampRequirementsResult
    func acceptHeadlessOnRampAgreements(_ params: ParaHeadlessOnRampAgreementsParams) async throws -> ParaHeadlessOnRampAgreementsResult
    func createHeadlessOnRampOrder(_ params: ParaHeadlessOnRampOrderParams) async throws -> ParaHeadlessOnRampOrderResult
    func getOnRampOrder(
        walletId: String?,
        purchaseId: String,
        externalWalletAddress: String?,
        walletType: String?,
        address: String?
    ) async throws -> ParaOnRampOrder
    func getKycStatus() async throws -> ParaKycStatusResult
    func createKycSession() async throws -> ParaKycSessionResult
    func shareKyc(_ params: ParaShareKycParams) async throws -> ParaShareKycResult
}

public extension ParaHeadlessOnRampClient {
    func getOnRampOrder(
        walletId: String? = nil,
        purchaseId: String,
        externalWalletAddress: String? = nil,
        walletType: String? = nil,
        address: String? = nil
    ) async throws -> ParaOnRampOrder {
        try await getOnRampOrder(
            walletId: walletId,
            purchaseId: purchaseId,
            externalWalletAddress: externalWalletAddress,
            walletType: walletType,
            address: address
        )
    }
}

private struct EmptyHeadlessBridgePayload: Encodable {}

// MARK: - Headless On-Ramp & Reusable KYC Operations

extension ParaManager: ParaHeadlessOnRampClient {
    /// Fetches a routed headless on-ramp quote (card, Apple Pay, or Google Pay).
    public func getHeadlessOnRampQuote(
        _ params: ParaHeadlessOnRampQuoteParams
    ) async throws -> ParaHeadlessOnRampQuoteResult {
        try await invokeHeadlessBridge(method: "getHeadlessOnRampQuote", payload: params, as: ParaHeadlessOnRampQuoteResult.self)
    }

    /// Checks verification, contact, and legal-agreement prerequisites for a headless on-ramp order.
    public func getHeadlessOnRampRequirements(
        _ params: ParaHeadlessOnRampRequirementsParams
    ) async throws -> ParaHeadlessOnRampRequirementsResult {
        try await invokeHeadlessBridge(
            method: "getHeadlessOnRampRequirements",
            payload: params,
            as: ParaHeadlessOnRampRequirementsResult.self
        )
    }

    /// Records acceptance of provider/issuer agreements returned by `getHeadlessOnRampRequirements`.
    public func acceptHeadlessOnRampAgreements(
        _ params: ParaHeadlessOnRampAgreementsParams
    ) async throws -> ParaHeadlessOnRampAgreementsResult {
        try await invokeHeadlessBridge(
            method: "acceptHeadlessOnRampAgreements",
            payload: params,
            as: ParaHeadlessOnRampAgreementsResult.self
        )
    }

    /// Creates a routed headless on-ramp purchase and provider payment order.
    public func createHeadlessOnRampOrder(
        _ params: ParaHeadlessOnRampOrderParams
    ) async throws -> ParaHeadlessOnRampOrderResult {
        try await invokeHeadlessBridge(
            method: "createHeadlessOnRampOrder",
            payload: params,
            as: ParaHeadlessOnRampOrderResult.self
        )
    }

    /// Fetches the user's reusable KYC verification status and previously shared providers.
    public func getKycStatus() async throws -> ParaKycStatusResult {
        try await invokeHeadlessBridge(
            method: "getKycStatus",
            payload: EmptyHeadlessBridgePayload(),
            as: ParaKycStatusResult.self
        )
    }

    /// Creates a reusable KYC verification session token for Sumsub.
    public func createKycSession() async throws -> ParaKycSessionResult {
        try await invokeHeadlessBridge(
            method: "createKycSession",
            payload: EmptyHeadlessBridgePayload(),
            as: ParaKycSessionResult.self
        )
    }

    /// Shares approved reusable KYC credentials with an on-ramp provider.
    public func shareKyc(_ params: ParaShareKycParams) async throws -> ParaShareKycResult {
        try await invokeHeadlessBridge(
            method: "shareKyc",
            payload: params,
            as: ParaShareKycResult.self
        )
    }

    private func invokeHeadlessBridge<P: Encodable, R: Decodable>(
        method: String,
        payload: P,
        as type: R.Type
    ) async throws -> R {
        try await ensureWebViewReady()
        let result = try await postMessage(method: method, payload: payload)
        return try decodeOnRampDecodable(result, as: type, method: method)
    }
}
