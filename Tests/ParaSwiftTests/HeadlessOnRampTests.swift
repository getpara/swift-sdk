@testable import ParaSwift
import XCTest

final class HeadlessOnRampTests: XCTestCase {
    // MARK: - Model Codable & Large Integer Serialization

    func testHeadlessAndKycModelsRoundTripAndEncodeLargeOrderIntegers() throws {
        let quoteJSON = Data(#"""
        {
          "quote": {
            "provider": "BANXA",
            "paymentMethod": "APPLE_PAY",
            "sourceAmount": 103.5,
            "sourceCurrency": "USD",
            "destinationAmount": 99.25,
            "exchangeRate": 1.0428,
            "fees": {
              "network": 1.25,
              "transaction": 2.0,
              "partner": 0.25,
              "total": 3.5
            }
          }
        }
        """#.utf8)
        let quoteResult = try JSONDecoder().decode(ParaHeadlessOnRampQuoteResult.self, from: quoteJSON)
        XCTAssertEqual(quoteResult.quote.provider, .banxa)
        XCTAssertEqual(quoteResult.quote.paymentMethod, .applePay)
        XCTAssertEqual(quoteResult.quote.fees.total, 3.5)

        let reqJSON = Data(#"""
        {
          "eligible": false,
          "missingSteps": ["VERIFICATION", "AGREEMENT", "FUTURE_STEP"],
          "agreements": [
            {
              "code": "BANXA_TOS",
              "type": "TERMS_OF_SERVICE",
              "url": "https://banxa.com/terms",
              "issuer": "Banxa"
            }
          ]
        }
        """#.utf8)
        let req = try JSONDecoder().decode(ParaHeadlessOnRampRequirementsResult.self, from: reqJSON)
        XCTAssertFalse(req.eligible)
        XCTAssertEqual(req.missingSteps, [.verification, .agreement, .unknown("FUTURE_STEP")])
        XCTAssertEqual(req.agreements.first?.issuer, "Banxa")

        let orderJSON = Data(#"""
        {
          "purchaseId": "pur-headless-1",
          "order": {
            "id": "meld-ord-1",
            "paymentMethodType": "APPLE_PAY",
            "createdTimestampMs": 9007199254740993,
            "paymentMethodResponseDetails": {
              "sessionToken": "tok-session-123"
            }
          }
        }
        """#.utf8)
        let orderResult = try JSONDecoder().decode(ParaHeadlessOnRampOrderResult.self, from: orderJSON)
        XCTAssertEqual(orderResult.purchaseId, "pur-headless-1")
        XCTAssertEqual(orderResult.orderId, "meld-ord-1")
        XCTAssertEqual(orderResult.paymentMethodType, "APPLE_PAY")
        XCTAssertEqual(orderResult.providerSessionToken, "tok-session-123")

        // Uses UnvalidatedBridgeJSONValue so Meld order fields with >2^53 integers encode without throwing.
        let encodedOrderData = try orderResult.encodedOrderData()
        let encodedOrderDict = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedOrderData) as? [String: Any])
        XCTAssertEqual(encodedOrderDict["id"] as? String, "meld-ord-1")
        XCTAssertEqual(encodedOrderDict["createdTimestampMs"] as? Int64, 9_007_199_254_740_993)

        let roundTrippedOrderData = try JSONEncoder().encode(orderResult)
        let decodedOrder = try JSONDecoder().decode(ParaHeadlessOnRampOrderResult.self, from: roundTrippedOrderData)
        XCTAssertEqual(decodedOrder.orderId, "meld-ord-1")

        let kycStatusJSON = Data(#"""
        {
          "status": "approved",
          "canRetry": false,
          "levelName": "basic-kyc-level",
          "reviewedAt": "2026-11-24T00:00:00Z",
          "sharedProviders": ["BANXA", "TRANSAK"]
        }
        """#.utf8)
        let kycStatus = try JSONDecoder().decode(ParaKycStatusResult.self, from: kycStatusJSON)
        XCTAssertEqual(kycStatus.status, .approved)
        XCTAssertEqual(kycStatus.sharedProviders, [.banxa, .transak])

        let kycSessionJSON = Data(#"{"provider":"SUMSUB","accessToken":"sbx-tok"}"#.utf8)
        let kycSession = try JSONDecoder().decode(ParaKycSessionResult.self, from: kycSessionJSON)
        XCTAssertEqual(kycSession.provider, .sumsub)
        XCTAssertEqual(kycSession.accessToken, "sbx-tok")

        let shareResultJSON = Data(#"{"provider":"BANXA","status":"shared"}"#.utf8)
        let shareResult = try JSONDecoder().decode(ParaShareKycResult.self, from: shareResultJSON)
        XCTAssertEqual(shareResult.provider, .banxa)
        XCTAssertEqual(shareResult.status, .shared)
    }

    // MARK: - ParaManager+HeadlessOnRamp Bridge Calls

    @MainActor
    func testParaManagerHeadlessOnRampAndKycBridgeCalls() async throws {
        let manager = MockHeadlessBridgeParaManager()

        manager.stub("getHeadlessOnRampQuote") { _ in
            [
                "quote": [
                    "provider": "BANXA",
                    "paymentMethod": "CARD",
                    "sourceAmount": 102.0,
                    "sourceCurrency": "USD",
                    "destinationAmount": 98.5,
                    "exchangeRate": 1.0355,
                    "fees": [
                        "network": 1.0,
                        "transaction": 1.5,
                        "partner": 0.0,
                        "total": 2.5,
                    ],
                ],
            ]
        }
        let quoteResult = try await manager.getHeadlessOnRampQuote(
            ParaHeadlessOnRampQuoteParams(
                provider: .banxa,
                paymentMethod: .card,
                assetImplementationId: "impl-usdc",
                fiatAmount: "100.00"
            )
        )
        XCTAssertEqual(quoteResult.quote.provider, .banxa)
        XCTAssertEqual(quoteResult.quote.paymentMethod, .card)
        XCTAssertEqual(manager.recordedPayload(for: "getHeadlessOnRampQuote")?["fiat"] as? String, "USD")
        XCTAssertEqual(manager.recordedPayload(for: "getHeadlessOnRampQuote")?["fiatAmount"] as? String, "100.00")

        manager.stub("getHeadlessOnRampRequirements") { _ in
            [
                "eligible": true,
                "missingSteps": ["AGREEMENT"],
                "agreements": [
                    ["code": "A1", "type": "TERMS", "url": "https://example.com/a1"],
                ],
            ]
        }
        let requirements = try await manager.getHeadlessOnRampRequirements(
            ParaHeadlessOnRampRequirementsParams(
                provider: .banxa,
                paymentMethod: .card,
                assetImplementationId: "impl-usdc",
                fiatAmount: "100.00",
                walletId: "w-1"
            )
        )
        XCTAssertTrue(requirements.eligible)
        XCTAssertEqual(requirements.missingSteps, [.agreement])
        XCTAssertEqual(manager.recordedPayload(for: "getHeadlessOnRampRequirements")?["walletId"] as? String, "w-1")

        manager.stub("acceptHeadlessOnRampAgreements") { _ in
            ["acceptedCodes": ["A1"]]
        }
        let accepted = try await manager.acceptHeadlessOnRampAgreements(
            ParaHeadlessOnRampAgreementsParams(provider: .banxa, paymentMethod: .card, codes: ["A1"])
        )
        XCTAssertEqual(accepted.acceptedCodes, ["A1"])
        XCTAssertEqual(manager.recordedPayload(for: "acceptHeadlessOnRampAgreements")?["codes"] as? [String], ["A1"])

        manager.stub("createHeadlessOnRampOrder") { _ in
            [
                "purchaseId": "pur-1",
                "order": [
                    "id": "ord-1",
                    "paymentMethodType": "CARD",
                    "paymentMethodResponseDetails": ["sessionToken": "st-1"],
                ],
            ]
        }
        let order = try await manager.createHeadlessOnRampOrder(
            ParaHeadlessOnRampOrderParams(
                provider: .banxa,
                paymentMethod: .card,
                assetImplementationId: "impl-usdc",
                fiatAmount: "100.00",
                walletId: "w-1",
                idempotencyKey: "idem-1"
            )
        )
        XCTAssertEqual(order.purchaseId, "pur-1")
        XCTAssertEqual(order.providerSessionToken, "st-1")
        XCTAssertEqual(manager.recordedPayload(for: "createHeadlessOnRampOrder")?["idempotencyKey"] as? String, "idem-1")

        manager.stub("getKycStatus") { _ in
            ["status": "in_progress", "canRetry": true, "sharedProviders": ["MOONPAY"]]
        }
        let status = try await manager.getKycStatus()
        XCTAssertEqual(status.status, .inProgress)
        XCTAssertTrue(status.canRetry)
        XCTAssertEqual(status.sharedProviders, [.moonpay])

        manager.stub("createKycSession") { _ in
            ["provider": "SUMSUB", "accessToken": "sumsub-token"]
        }
        let session = try await manager.createKycSession()
        XCTAssertEqual(session.provider, .sumsub)
        XCTAssertEqual(session.accessToken, "sumsub-token")

        manager.stub("shareKyc") { _ in
            ["provider": "TRANSAK", "status": "shared"]
        }
        let shared = try await manager.shareKyc(ParaShareKycParams(provider: .transak))
        XCTAssertEqual(shared.provider, .transak)
        XCTAssertEqual(shared.status, .shared)
        XCTAssertEqual(manager.recordedPayload(for: "shareKyc")?["provider"] as? String, "TRANSAK")
    }

    // MARK: - ParaHeadlessOnRampCheckout State Machine

    @MainActor
    func testCheckoutHappyPathAndCancelResetIdempotencyKey() async throws {
        let client = MockHeadlessOnRampClient()
        let orderStatuses: [ParaOnRampPurchaseStatus] = [.initiated, .finished]
        var pollIndex = 0
        var unmountCount = 0

        client.onGetOrder = { _, _ in
            let next = orderStatuses[min(pollIndex, orderStatuses.count - 1)]
            pollIndex += 1
            return ParaOnRampOrder(id: "pur-1", userId: "u-1", status: next)
        }

        let checkout = ParaHeadlessOnRampCheckout(
            client: client,
            walletId: "w-1",
            assetImplementationId: "impl-usdc",
            amountUsd: "100.00",
            provider: .banxa,
            paymentMethod: .card,
            unmountPayment: { unmountCount += 1 },
            pollIntervalNanoseconds: 5_000_000
        )

        XCTAssertEqual(checkout.step, .idle)
        XCTAssertEqual(checkout.environment, .sandbox)

        await checkout.start()
        XCTAssertEqual(checkout.step, .review)
        XCTAssertEqual(checkout.agreements.map(\.code), ["TOS_1"])
        XCTAssertNotNil(checkout.quote)

        await checkout.confirm()
        XCTAssertEqual(checkout.step, .payment)
        XCTAssertEqual(checkout.providerSessionToken, "tok-1")
        let firstKey = client.createOrderKeys.first
        XCTAssertNotNil(firstKey)
        XCTAssertEqual(client.acceptedAgreementCalls, 1)

        // Cancelling before submission unmounts widget and generates a fresh key next confirm.
        checkout.onPaymentCancelled()
        XCTAssertEqual(checkout.step, .review)
        XCTAssertGreaterThan(unmountCount, 1)

        await checkout.confirm()
        XCTAssertEqual(checkout.step, .payment)
        XCTAssertEqual(client.createOrderKeys.count, 2)
        XCTAssertNotEqual(client.createOrderKeys[1], firstKey)
        XCTAssertEqual(client.acceptedAgreementCalls, 2)

        checkout.onPaymentSubmitted()
        XCTAssertEqual(checkout.step, .processing)

        try await waitUntil { checkout.step == .success }
        XCTAssertEqual(pollIndex, 2)
    }

    @MainActor
    func testCheckoutHandlesRequirementsAmountRangeAgreementsAndRepeatableOrderKey() async {
        let client = MockHeadlessOnRampClient()
        client.requirementsResult = ParaHeadlessOnRampRequirementsResult(
            eligible: false,
            missingSteps: [.verification],
            agreements: []
        )

        let checkout = ParaHeadlessOnRampCheckout(
            client: client,
            walletId: "w-1",
            assetImplementationId: "impl-usdc",
            amountUsd: "3.00",
            provider: .banxa,
            paymentMethod: .applePay,
            pollIntervalNanoseconds: 5_000_000
        )

        await checkout.start()
        XCTAssertEqual(checkout.step, .verificationRequired)

        // Amount out of range via nested Axios details.data formats USD minimum.
        client.requirementsResult = ParaHeadlessOnRampRequirementsResult(eligible: true, missingSteps: [], agreements: [])
        client.quoteError = ParaBridgeErrorPayload(
            message: "Amount out of range",
            code: "ONRAMP_AMOUNT_OUT_OF_RANGE",
            status: 422,
            details: .object(["data": .object(["minAmount": .integer(5), "maxAmount": .integer(500)])])
        )
        await checkout.start()
        XCTAssertEqual(checkout.step, .failure)
        XCTAssertEqual(checkout.error, "Minimum amount is $5")
        XCTAssertTrue(checkout.canRetry)

        // Agreement invalidation during confirm automatically restarts.
        client.quoteError = nil
        checkout.amountUsd = "50.00"
        await checkout.start()
        XCTAssertEqual(checkout.step, .review)

        var firstConfirm = true
        client.onCreateOrder = { _ in
            if firstConfirm {
                firstConfirm = false
                throw ParaError.bridgeError("Agreement stale (code: ONRAMP_AGREEMENT_REQUIRED, status: 409)")
            }
            return ParaHeadlessOnRampOrderResult(
                purchaseId: "pur-ok",
                order: ["id": .string("ord-ok"), "paymentMethodResponseDetails": .object(["sessionToken": .string("tok-ok")])]
            )
        }
        await checkout.confirm()
        XCTAssertEqual(checkout.step, .review)

        // Transient 500 error preserves the same idempotencyKey across retry().
        var failOnce = true
        client.onCreateOrder = { _ in
            if failOnce {
                failOnce = false
                throw ParaError.bridgeError("Server down (code: INTERNAL_ERROR, status: 500)")
            }
            return ParaHeadlessOnRampOrderResult(
                purchaseId: "pur-retry",
                order: ["id": .string("ord-retry")]
            )
        }
        await checkout.confirm()
        XCTAssertEqual(checkout.step, .failure)
        XCTAssertTrue(checkout.canRetry)
        XCTAssertEqual(checkout.error, "Could not start the purchase.")

        await checkout.retry()
        XCTAssertEqual(checkout.step, .payment)
        XCTAssertEqual(client.createOrderKeys.count, 3)
        XCTAssertEqual(client.createOrderKeys[1], client.createOrderKeys[2])
    }

    @MainActor
    func testCheckoutHandlesClosedOrderPaymentErrorsAndPollingOutcomes() async throws {
        let client = MockHeadlessOnRampClient()
        var orderStatus: ParaOnRampPurchaseStatus = .cancelled
        client.onGetOrder = { _, _ in
            ParaOnRampOrder(id: "pur-closed", userId: "u-1", status: orderStatus)
        }

        let checkout = ParaHeadlessOnRampCheckout(
            client: client,
            walletId: "w-1",
            assetImplementationId: "impl-usdc",
            amountUsd: "50.00",
            provider: .transak,
            paymentMethod: .card,
            pollIntervalNanoseconds: 5_000_000
        )

        await checkout.start()
        client.onCreateOrder = { _ in
            throw ParaBridgeErrorPayload(
                message: "Order already closed",
                code: "ONRAMP_ORDER_CLOSED",
                status: 409,
                details: .object(["purchaseId": .string("pur-closed")])
            )
        }
        await checkout.confirm()
        XCTAssertEqual(checkout.step, .failure)
        XCTAssertEqual(checkout.error, ParaHeadlessOnRampCheckout.orderCancelledMessage)
        XCTAssertTrue(checkout.canRetry)

        // Recoverable load failure remounts existing order on retry; attemptMayExist enters polling.
        client.onCreateOrder = nil
        orderStatus = .initiated
        await checkout.start()
        await checkout.confirm()
        XCTAssertEqual(checkout.step, .payment)

        checkout.onPaymentError(
            code: "PROVIDER_LOAD_FAILED",
            options: ParaHeadlessOnRampPaymentErrorOptions(attemptMayExist: false, loadFailed: true, recoverable: true)
        )
        XCTAssertEqual(checkout.step, .failure)
        XCTAssertEqual(checkout.error, ParaHeadlessOnRampCheckout.loadFailedMessage)
        XCTAssertTrue(checkout.canRetry)

        await checkout.retry()
        XCTAssertEqual(checkout.step, .payment)

        checkout.onPaymentError(
            code: "PAYMENT_METHOD_UNAVAILABLE",
            options: ParaHeadlessOnRampPaymentErrorOptions(attemptMayExist: false, loadFailed: false, recoverable: false)
        )
        XCTAssertEqual(checkout.step, .failure)
        XCTAssertEqual(checkout.error, ParaHeadlessOnRampCheckout.methodUnavailableMessage)
        XCTAssertFalse(checkout.canRetry)

        // Fatal 401 poll failure ends polling with canRetry = false.
        orderStatus = .initiated
        client.environment = .prod
        let prodCheckout = ParaHeadlessOnRampCheckout(
            client: client,
            walletId: "w-1",
            assetImplementationId: "impl-usdc",
            amountUsd: "50.00",
            provider: .banxa,
            paymentMethod: .card,
            pollIntervalNanoseconds: 5_000_000
        )
        XCTAssertEqual(prodCheckout.environment, .production)

        await prodCheckout.start()
        await prodCheckout.confirm()

        client.onGetOrder = { _, _ in
            throw ParaError.bridgeError("Unauthorized (code: UNAUTHORIZED, status: 401)")
        }
        prodCheckout.onPaymentSubmitted()
        try await waitUntil { prodCheckout.step == .failure }
        XCTAssertFalse(prodCheckout.canRetry)
    }

    @MainActor
    private func waitUntil(timeoutSeconds: TimeInterval = 2.0, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for checkout state transition")
    }
}

@MainActor
private final class MockHeadlessBridgeParaManager: ParaManager {
    private var handlers: [String: ([String: Any]) throws -> Any?] = [:]
    private var recordedPayloads: [String: [String: Any]] = [:]

    init() {
        super.init(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test-api-key",
            appScheme: "myapp"
        )
        paraWebView.initializationError = ParaWebViewError.webViewNotReady
    }

    func stub(_ method: String, handler: @escaping ([String: Any]) throws -> Any?) {
        handlers[method] = handler
    }

    func recordedPayload(for method: String) -> [String: Any]? {
        recordedPayloads[method]
    }

    override func ensureWebViewReady() async throws {}

    override func postMessage(method: String, payload: Encodable, timeout _: TimeInterval?) async throws -> Any? {
        let data = try JSONEncoder().encode(payload)
        let dict = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        recordedPayloads[method] = dict
        guard let handler = handlers[method] else {
            throw ParaError.bridgeError("Unstubbed bridge method: \(method)")
        }
        return try handler(dict)
    }
}

@MainActor
private final class MockHeadlessOnRampClient: ParaHeadlessOnRampClient {
    var environment: ParaEnvironment = .sandbox
    var quoteError: Error?
    var requirementsResult = ParaHeadlessOnRampRequirementsResult(
        eligible: true,
        missingSteps: [],
        agreements: [
            ParaHeadlessOnRampAgreement(code: "TOS_1", type: "TERMS", url: "https://example.com/tos"),
        ]
    )
    var acceptedAgreementCalls = 0
    var createOrderKeys: [String] = []
    var onCreateOrder: ((ParaHeadlessOnRampOrderParams) throws -> ParaHeadlessOnRampOrderResult)?
    var onGetOrder: ((String, String?) throws -> ParaOnRampOrder)?

    func getHeadlessOnRampQuote(_ params: ParaHeadlessOnRampQuoteParams) async throws -> ParaHeadlessOnRampQuoteResult {
        if let quoteError {
            throw quoteError
        }
        return ParaHeadlessOnRampQuoteResult(
            quote: ParaHeadlessOnRampQuote(
                provider: params.provider,
                paymentMethod: params.paymentMethod,
                sourceAmount: 102.5,
                sourceCurrency: params.fiat,
                destinationAmount: 100.0,
                exchangeRate: 1.025,
                fees: ParaHeadlessOnRampQuoteFees(network: 1.0, transaction: 1.5, partner: 0.0, total: 2.5)
            )
        )
    }

    func getHeadlessOnRampRequirements(
        _: ParaHeadlessOnRampRequirementsParams
    ) async throws -> ParaHeadlessOnRampRequirementsResult {
        requirementsResult
    }

    func acceptHeadlessOnRampAgreements(
        _ params: ParaHeadlessOnRampAgreementsParams
    ) async throws -> ParaHeadlessOnRampAgreementsResult {
        acceptedAgreementCalls += 1
        return ParaHeadlessOnRampAgreementsResult(acceptedCodes: params.codes)
    }

    func createHeadlessOnRampOrder(
        _ params: ParaHeadlessOnRampOrderParams
    ) async throws -> ParaHeadlessOnRampOrderResult {
        createOrderKeys.append(params.idempotencyKey)
        if let onCreateOrder {
            return try onCreateOrder(params)
        }
        return ParaHeadlessOnRampOrderResult(
            purchaseId: "pur-\(createOrderKeys.count)",
            order: [
                "id": .string("ord-\(createOrderKeys.count)"),
                "paymentMethodResponseDetails": .object(["sessionToken": .string("tok-\(createOrderKeys.count)")]),
            ]
        )
    }

    func getOnRampOrder(
        walletId: String?,
        purchaseId: String,
        externalWalletAddress _: String?,
        walletType _: String?,
        address _: String?
    ) async throws -> ParaOnRampOrder {
        if let onGetOrder {
            return try onGetOrder(purchaseId, walletId)
        }
        return ParaOnRampOrder(id: purchaseId, userId: "u-1", status: .finished)
    }

    func getKycStatus() async throws -> ParaKycStatusResult {
        ParaKycStatusResult(status: .approved, canRetry: false)
    }

    func createKycSession() async throws -> ParaKycSessionResult {
        ParaKycSessionResult(provider: .sumsub, accessToken: "sumsub-tok")
    }

    func shareKyc(_ params: ParaShareKycParams) async throws -> ParaShareKycResult {
        ParaShareKycResult(provider: params.provider, status: .shared)
    }
}
