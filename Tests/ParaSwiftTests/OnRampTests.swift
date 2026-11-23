import AuthenticationServices
@testable import ParaSwift
import XCTest

final class OnRampTests: XCTestCase {
    // MARK: - Init Arguments & Helpers

    func testBuildInitArgumentsIncludesHostOsAndSupportsEvents() {
        let args = ParaWebView.buildInitArguments(
            environment: .sandbox,
            apiKey: "test-api-key",
            packageVersion: "2.11.0",
            isPasskeySupported: true
        )

        XCTAssertEqual(args["environment"] as? String, "SANDBOX")
        XCTAssertEqual(args["apiKey"] as? String, "test-api-key")
        XCTAssertEqual(args["platform"] as? String, "iOS")
        XCTAssertEqual(args["hostOs"] as? String, "ios")
        XCTAssertEqual(args["package"] as? String, "2.11.0")
        XCTAssertEqual(args["isPasskeySupported"] as? Bool, true)
        XCTAssertEqual(args["supportsAuthV2"] as? Bool, true)
        XCTAssertEqual(args["supportsEvents"] as? Bool, true)
    }

    // MARK: - Structured Bridge Error Parsing & JSON Details Encoding

    func testParseBridgeErrorExtractsDictionaryFieldsAndStatusCode() {
        let errorDict: [String: Any] = [
            "message": "Checkout validation failed",
            "code": "INVALID_AMOUNT",
            "statusCode": 422,
            "details": [
                "field": "amountUsd",
                "minimum": 5,
            ],
        ]

        let parsed = ParaWebView.parseBridgeError(errorDict)
        XCTAssertEqual(parsed?.message, "Checkout validation failed")
        XCTAssertEqual(parsed?.code, "INVALID_AMOUNT")
        XCTAssertEqual(parsed?.status, 422)
        XCTAssertEqual(parsed?.details?["field"], .string("amountUsd"))
        XCTAssertEqual(parsed?.details?["minimum"], .integer(5))
        XCTAssertEqual(
            parsed?.formattedMessage,
            "Checkout validation failed (code: INVALID_AMOUNT, status: 422)"
        )
    }

    func testParseBridgeErrorUnwrapsAxiosDetailsDataAndPrefersDetailMessage() {
        let axiosError: [String: Any] = [
            "message": "Request failed with status code 422",
            "code": "ERR_BAD_REQUEST",
            "status": 422,
            "statusCode": 422,
            "details": [
                "message": "Request failed with status code 422",
                "code": "ERR_BAD_REQUEST",
                "status": 422,
                "statusCode": 422,
                "data": [
                    "message": "Order rejected",
                    "code": "ONRAMP_LIMIT_EXCEEDED",
                ],
            ],
        ]

        let unwrapped = ParaWebView.parseBridgeError(axiosError)
        XCTAssertEqual(unwrapped?.message, "Order rejected")
        XCTAssertEqual(unwrapped?.code, "ONRAMP_LIMIT_EXCEEDED")
        XCTAssertEqual(unwrapped?.status, 422)
        XCTAssertEqual(
            unwrapped?.formattedMessage,
            "Order rejected (code: ONRAMP_LIMIT_EXCEEDED, status: 422)"
        )

        let detailDict: [String: Any] = [
            "message": "Request failed",
            "code": "RATE_LIMITED",
            "status": 429,
            "details": [
                "message": "Too many checkout attempts",
            ],
        ]
        let parsed = ParaWebView.parseBridgeError(detailDict)
        XCTAssertEqual(parsed?.message, "Too many checkout attempts")
        XCTAssertEqual(parsed?.code, "RATE_LIMITED")
        XCTAssertEqual(parsed?.status, 429)
    }

    func testParseBridgeErrorHandlesStringJsonStringNullAndLargeNumbersInDetails() throws {
        XCTAssertNil(ParaWebView.parseBridgeError(nil))
        XCTAssertNil(ParaWebView.parseBridgeError(NSNull()))

        let plain = ParaWebView.parseBridgeError("Network error")
        XCTAssertEqual(plain, ParaBridgeErrorPayload(message: "Network error"))
        XCTAssertEqual(plain?.formattedMessage, "Network error")

        let jsonError = ParaWebView.parseBridgeError(#"{"message":"Unauthorized","code":"AUTH_REQUIRED","status":401}"#)
        XCTAssertEqual(jsonError?.message, "Unauthorized")
        XCTAssertEqual(jsonError?.code, "AUTH_REQUIRED")
        XCTAssertEqual(jsonError?.status, 401)

        let payloadWithLargeNumber = ParaBridgeErrorPayload(
            message: "Big detail",
            code: "ERR",
            status: 500,
            details: .object(["nonce": .integer(9_007_199_254_740_992)])
        )
        let encoded = try JSONEncoder().encode(payloadWithLargeNumber)
        let decoded = try JSONDecoder().decode(ParaBridgeErrorPayload.self, from: encoded)
        XCTAssertEqual(decoded.details?["nonce"], .integer(9_007_199_254_740_992))
    }

    @MainActor
    func testParaManagerPostMessagePreservesFormattedBridgeErrorWithoutJsonReparse() async {
        let manager = ErrorForwardingParaManager(
            errorToThrow: ParaWebViewError.bridgeError(#"{"message":"verbatim"} (code: RAW_JSON, status: 400)"#)
        )

        do {
            _ = try await manager.postMessage(method: "createOnRampOrder", payload: EmptyPayload(), timeout: nil)
            XCTFail("Expected ParaError.bridgeError")
        } catch let ParaError.bridgeError(msg) {
            XCTAssertEqual(msg, #"{"message":"verbatim"} (code: RAW_JSON, status: 400)"#)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testRealParaManagerPostMessageMapsWebViewErrorsDirectly() async throws {
        // 1. Not ready -> ParaError.bridgeError("WebView is not ready")
        let notReadyManager = ParaManager(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "test"
        )
        notReadyManager.paraWebView.initializationError = ParaWebViewError.webViewNotReady
        do {
            _ = try await notReadyManager.postMessage(method: "getOnRampConfig", payload: EmptyPayload())
            XCTFail("Expected ParaError.bridgeError")
        } catch let ParaError.bridgeError(msg) {
            XCTAssertEqual(msg, "WebView is not ready")
        }

        // 2. Ready ParaWebView: bridge error, timeout, and invalid arguments map directly through ParaManager.postMessage
        let manager = ParaManager(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "test"
        )
        manager.paraWebView.handleCallback(response: ["method": "Para#init"])

        // Timeout -> ParaError.bridgeTimeoutError
        do {
            _ = try await manager.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: 0)
            XCTFail("Expected ParaError.bridgeTimeoutError")
        } catch ParaError.bridgeTimeoutError {
            // Expected
        }

        // Invalid arguments -> ParaError.error("Invalid arguments: ...")
        struct UnencodablePayload: Encodable {
            func encode(to _: Encoder) throws {
                throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "bad payload"))
            }
        }
        do {
            _ = try await manager.postMessage(method: "getOnRampConfig", payload: UnencodablePayload())
            XCTFail("Expected ParaError.error")
        } catch let ParaError.error(msg) {
            XCTAssertTrue(msg.contains("Invalid arguments:"))
        }

        // Structured bridge error -> ParaError.bridgeError with unwrapped details.data message/code/status
        let callTask = Task {
            try await manager.postMessage(method: "createOnRampOrder", payload: EmptyPayload(), timeout: 10.0)
        }
        while manager.paraWebView.pendingRequestIds.isEmpty {
            await Task.yield()
        }
        let reqId = try XCTUnwrap(manager.paraWebView.pendingRequestIds.first)
        manager.paraWebView.handleCallback(response: [
            "method": "createOnRampOrder",
            "requestId": reqId,
            "error": [
                "message": "Request failed with status code 422",
                "code": "ERR_BAD_REQUEST",
                "status": 422,
                "details": [
                    "data": [
                        "message": "Order rejected",
                        "code": "ONRAMP_LIMIT_EXCEEDED",
                    ],
                ],
            ],
        ])
        do {
            _ = try await callTask.value
            XCTFail("Expected ParaError.bridgeError")
        } catch let ParaError.bridgeError(msg) {
            XCTAssertEqual(msg, "Order rejected (code: ONRAMP_LIMIT_EXCEEDED, status: 422)")
        }
    }

    // MARK: - Log Redaction

    func testRedactLogMessageScrubsSensitiveKeysEscapedJsonAndLaunchTokenFragments() {
        let raw = #"""
        {"publicToken":"public-sandbox-123","plaidLinkToken":"link-sandbox-456","launchToken":"lt-789","providerKey":"pk-secret","accessToken":"acc-111","apiKey":"api-222","secret":"sec-333","authentication_token":"auth-444","paymentLink":{"url":"https://pay.coinbase.com/session?token=1"},"upgradeUrl":"https://pay.coinbase.com/upgrade","purchaseId":"pur-safe"}
        {\"apiKey\":\"escaped-key-555\",\"paymentLink\":{\"url\":\"https://pay.coinbase.com/escaped\"}}
        https://portal.getpara.com/onramp?apiKey=query-key&publicToken=pub-q#rampLaunchToken=jwt.header.sig&status=INITIATED
        apiKey: raw-key-999 authentication_token=raw-auth-000
        """#

        let redacted = ParaWebView.redactLogMessage(raw)

        for secretValue in [
            "public-sandbox-123",
            "link-sandbox-456",
            "lt-789",
            "pk-secret",
            "acc-111",
            "api-222",
            "sec-333",
            "auth-444",
            "https://pay.coinbase.com/session?token=1",
            "https://pay.coinbase.com/upgrade",
            "escaped-key-555",
            "https://pay.coinbase.com/escaped",
            "query-key",
            "pub-q",
            "jwt.header.sig",
            "raw-key-999",
            "raw-auth-000",
        ] {
            XCTAssertFalse(redacted.contains(secretValue), "Redacted output leaked secret value: \(secretValue)")
        }

        XCTAssertTrue(redacted.contains("\"purchaseId\":\"pur-safe\""))
        XCTAssertTrue(redacted.contains("#rampLaunchToken=[REDACTED]&status=INITIATED"))
    }

    // MARK: - Para#event Parsing & Live ParaWebView Lifecycle

    func testParseOnRampEventDecodesLaunchedCompletedAndPartialFallbackPayloads() {
        let launchedResponse: [String: Any] = [
            "method": "Para#event",
            "event": "ONRAMP_LAUNCHED",
            "data": [
                "userId": "user-1",
                "purchaseId": "pur-1",
                "provider": "STRIPE",
                "direction": "BUY",
                "paymentMethod": "CARD",
                "transactionHash": NSNull(),
                "asset": [
                    "symbol": "USDC",
                    "name": "USD Coin",
                    "contractAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                    "type": "EVM",
                    "chainId": "1",
                    "networkName": "Ethereum",
                    "decimals": 6,
                ],
                "assetQuantity": 100,
                "fiatAmount": 100.5,
                "fiatCurrency": "USD",
                "walletId": "wallet-1",
                "destinationAddress": "0xabc",
                "providerOrderId": "ord-1",
                "providerTransactionId": "ptx-1",
                "testMode": true,
                "completedAt": NSNull(),
            ],
        ]

        let launchedEvent = ParaWebView.parseOnRampEvent(from: launchedResponse)
        guard case let .launched(launchedPayload) = launchedEvent else {
            return XCTFail("Expected .launched event, got \(String(describing: launchedEvent))")
        }
        XCTAssertEqual(launchedPayload.userId, "user-1")
        XCTAssertEqual(launchedPayload.purchaseId, "pur-1")
        XCTAssertEqual(launchedPayload.provider, .stripe)
        XCTAssertEqual(launchedPayload.direction, .buy)
        XCTAssertEqual(launchedPayload.paymentMethod, .card)
        XCTAssertEqual(launchedPayload.assetQuantity, "100")
        XCTAssertEqual(launchedPayload.fiatAmount, "100.5")
        XCTAssertEqual(launchedPayload.providerOrderId, "ord-1")
        XCTAssertEqual(launchedPayload.providerTransactionId, "ptx-1")
        XCTAssertNil(launchedPayload.transactionHash)
        XCTAssertNil(launchedPayload.completedAt)
        XCTAssertEqual(launchedPayload.asset?.symbol, "USDC")
        XCTAssertEqual(launchedPayload.asset?.decimals, 6)
        XCTAssertEqual(launchedPayload.testMode, true)

        let fallbackCompletedResponse: [String: Any] = [
            "method": "Para#event",
            "event": "paraOnRampTransactionCompleteV2",
            "data": [
                "id": "pur-fallback",
                "provider": "NEW_PROVIDER",
                "paymentMethod": "CRYPTO_PAY",
                "transactionHash": "0xdeadbeef",
                "completedAt": "2026-11-22T12:00:00.000Z",
            ],
        ]

        let completedEvent = ParaWebView.parseOnRampEvent(from: fallbackCompletedResponse)
        guard case let .completed(completedPayload) = completedEvent else {
            return XCTFail("Expected .completed event, got \(String(describing: completedEvent))")
        }
        XCTAssertEqual(completedPayload.purchaseId, "pur-fallback")
        XCTAssertEqual(completedPayload.provider, .unknown("NEW_PROVIDER"))
        XCTAssertEqual(completedPayload.paymentMethod, .unknown("CRYPTO_PAY"))
        XCTAssertNil(completedPayload.userId)
        XCTAssertNil(completedPayload.asset)
        XCTAssertNil(completedPayload.testMode)
        XCTAssertEqual(completedPayload.transactionHash, "0xdeadbeef")
    }

    @MainActor
    func testWebViewStreamsEventsToMultipleSubscribersWithoutSettingLastError() async {
        let webView = ParaWebView(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test-key",
            requestTimeout: 5.0
        )

        let streamA = webView.onRampEvents
        let streamB = webView.onRampEvents

        let receivedA = Task { () -> ParaOnRampEvent? in
            for await event in streamA {
                return event
            }
            return nil
        }
        let receivedB = Task { () -> ParaOnRampEvent? in
            for await event in streamB {
                return event
            }
            return nil
        }

        await Task.yield()

        webView.handleCallback(response: [
            "method": "Para#event",
            "event": "ONRAMP_LAUNCHED",
            "data": [
                "userId": "u1",
                "purchaseId": "p1",
                "transactionHash": NSNull(),
                "asset": ["symbol": "USDC"],
                "testMode": true,
                "completedAt": NSNull(),
            ],
        ])

        let eventA = await receivedA.value
        let eventB = await receivedB.value

        XCTAssertNil(webView.lastError)
        guard case let .launched(payloadA) = eventA, case let .launched(payloadB) = eventB else {
            return XCTFail("Expected both subscribers to receive .launched")
        }
        XCTAssertEqual(payloadA.purchaseId, "p1")
        XCTAssertEqual(payloadB.purchaseId, "p1")

        webView.handleCallback(response: [
            "method": "Para#event",
            "event": "UNKNOWN_EVENT",
            "data": ["foo": "bar"],
        ])
        XCTAssertNil(webView.lastError)
    }

    @MainActor
    func testOnRampEventBroadcasterCleansUpOnTerminationAndFinishesOnWebViewDeinit() async throws {
        // 1. onTermination removes cancelled/ended subscriptions from broadcaster
        do {
            let webView = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 5.0
            )
            XCTAssertEqual(webView.activeOnRampEventSubscriberCount, 0)

            let stream = webView.onRampEvents
            let consumer = Task {
                for await _ in stream {}
            }
            while webView.activeOnRampEventSubscriberCount == 0 {
                await Task.yield()
            }
            XCTAssertEqual(webView.activeOnRampEventSubscriberCount, 1)

            consumer.cancel()
            _ = await consumer.value
            while webView.activeOnRampEventSubscriberCount > 0 {
                await Task.yield()
            }
            XCTAssertEqual(webView.activeOnRampEventSubscriberCount, 0)
        }

        // 2. ParaWebView.deinit calls finishAll() so awaiting consumers terminate cleanly instead of hanging
        do {
            var webView: ParaWebView? = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 5.0
            )
            let stream = try XCTUnwrap(webView?.onRampEvents)
            let finished = Task<Bool, Never> {
                for await _ in stream {}
                return true
            }
            while (webView?.activeOnRampEventSubscriberCount ?? 0) == 0 {
                await Task.yield()
            }
            webView = nil
            let didFinish = await finished.value
            XCTAssertTrue(didFinish)
        }
    }

    @MainActor
    func testWebViewInitErrorRedactsStoredErrorsAndDoesNotMarkReady() {
        let webView = ParaWebView(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test-key",
            requestTimeout: 5.0
        )

        webView.handleCallback(response: [
            "method": "Para#init",
            "error": ["message": "Invalid apiKey=secret_abc", "code": "INVALID_API_KEY", "status": 401],
        ])

        XCTAssertFalse(webView.isReady)
        XCTAssertNotNil(webView.initializationError)
        XCTAssertNotNil(webView.lastError)
        XCTAssertFalse(webView.initializationError?.localizedDescription.contains("secret_abc") ?? true)
        XCTAssertFalse(webView.lastError?.localizedDescription.contains("secret_abc") ?? true)
    }

    @MainActor
    func testWebViewImmediatelyResumesPendingRequestWithStructuredErrorOnErrorCallback() async throws {
        let webView = ParaWebView(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test-key",
            requestTimeout: 30.0
        )
        webView.handleCallback(response: ["method": "Para#init"])
        XCTAssertTrue(webView.isReady)

        let start = Date()
        let callTask = Task {
            try await webView.postMessage(method: "createOnRampOrder", payload: EmptyPayload(), timeout: 30.0)
        }

        while webView.pendingRequestIds.isEmpty {
            await Task.yield()
        }
        let requestId = try XCTUnwrap(webView.pendingRequestIds.first)

        webView.handleCallback(response: [
            "method": "createOnRampOrder",
            "requestId": requestId,
            "error": [
                "message": "Unsupported asset",
                "code": "UNSUPPORTED_ASSET",
                "status": 400,
            ],
        ])

        do {
            _ = try await callTask.value
            XCTFail("Expected postMessage to throw bridgeError")
        } catch let error as ParaWebViewError {
            guard case let .bridgeError(msg) = error else {
                return XCTFail("Expected ParaWebViewError.bridgeError, got \(error)")
            }
            XCTAssertTrue(msg.contains("Unsupported asset"))
            XCTAssertTrue(msg.contains("UNSUPPORTED_ASSET"))
            XCTAssertTrue(msg.contains("400"))
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertTrue(webView.pendingRequestIds.isEmpty)
    }

    @MainActor
    func testWebViewPostMessageHandlesNegativeTimeoutCancellationAndDeinit() async throws {
        // 1. Negative timeout clamps to 0 without trapping and throws .requestTimeout.
        do {
            let webView = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 30.0
            )
            webView.handleCallback(response: ["method": "Para#init"])
            do {
                _ = try await webView.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: -5.0)
                XCTFail("Expected ParaWebViewError.requestTimeout")
            } catch let error as ParaWebViewError {
                guard case .requestTimeout = error else {
                    return XCTFail("Expected requestTimeout, got \(error)")
                }
            }
        }

        // 2. Cancelling caller task fails immediately with CancellationError and cleans up pendingRequestIds.
        do {
            let webView = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 30.0
            )
            webView.handleCallback(response: ["method": "Para#init"])

            let task = Task {
                try await webView.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: 30.0)
            }
            while webView.pendingRequestIds.isEmpty {
                await Task.yield()
            }
            let requestId = try XCTUnwrap(webView.pendingRequestIds.first)
            task.cancel()

            do {
                _ = try await task.value
                XCTFail("Expected CancellationError")
            } catch is CancellationError {
                // Expected
            }
            XCTAssertTrue(webView.pendingRequestIds.isEmpty)

            // Late callback after cancellation should be a clean no-op without crashing.
            webView.handleCallback(response: ["method": "getOnRampConfig", "requestId": requestId, "responseData": [:]])
        }

        // 3. Deallocating ParaWebView while a request is pending cancels timeout and resumes continuation instead of hanging.
        do {
            var webView: ParaWebView? = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 60.0
            )
            weak var weakWebView = webView
            let timeoutTask = Task<Void, Never> {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
            let pendingTask = Task<Any?, Error> {
                try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        webView?.insertPendingRequestForTesting(
                            id: "req-deinit-test",
                            continuation: continuation,
                            timeoutTask: timeoutTask
                        )
                        webView = nil
                    }
                }
            }

            let start = Date()
            do {
                _ = try await pendingTask.value
                XCTFail("Expected error when ParaWebView deallocates")
            } catch {
                XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
            }
            XCTAssertNil(weakWebView)
            XCTAssertTrue(timeoutTask.isCancelled)
        }

        // 4. Infinite and greatestFiniteMagnitude timeouts clamp safely without UInt64 overflow traps.
        do {
            XCTAssertEqual(ParaWebView.clampedTimeoutNanoseconds(.nan), 0)
            XCTAssertEqual(ParaWebView.clampedTimeoutNanoseconds(-10), 0)
            XCTAssertEqual(ParaWebView.clampedTimeoutNanoseconds(-.infinity), 0)
            let expectedMax = UInt64(31_536_000) * 1_000_000_000
            XCTAssertEqual(ParaWebView.clampedTimeoutNanoseconds(.infinity), expectedMax)
            XCTAssertEqual(ParaWebView.clampedTimeoutNanoseconds(.greatestFiniteMagnitude), expectedMax)

            let webView = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 30.0
            )
            webView.handleCallback(response: ["method": "Para#init"])

            for hugeTimeout in [TimeInterval.infinity, TimeInterval.greatestFiniteMagnitude] {
                let task = Task {
                    try await webView.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: hugeTimeout)
                }
                while webView.pendingRequestIds.isEmpty {
                    await Task.yield()
                }
                task.cancel()
                do {
                    _ = try await task.value
                    XCTFail("Expected CancellationError")
                } catch is CancellationError {
                    // Expected without overflow trap
                }
            }
        }

        // 5. evaluateJavaScript error path resumes once, and post-timeout JS error is a safe no-op.
        do {
            let webView = ParaWebView(
                environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
                apiKey: "test-key",
                requestTimeout: 30.0
            )
            webView.handleCallback(response: ["method": "Para#init"])

            let expectedError = NSError(domain: "WKErrorDomain", code: 4, userInfo: [NSLocalizedDescriptionKey: "JS eval failed"])
            webView.javascriptEvaluator = { _, completion in
                completion(nil, expectedError)
            }

            do {
                _ = try await webView.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: 10.0)
                XCTFail("Expected JS eval error")
            } catch let error as NSError {
                XCTAssertEqual(error.domain, "WKErrorDomain")
                XCTAssertEqual(error.code, 4)
            }
            XCTAssertTrue(webView.pendingRequestIds.isEmpty)

            // Delayed JS error firing after timeout already resumed must not crash or double-resume.
            var capturedCompletion: ((Any?, Error?) -> Void)?
            webView.javascriptEvaluator = { _, completion in
                capturedCompletion = completion
            }
            do {
                _ = try await webView.postMessage(method: "getOnRampConfig", payload: EmptyPayload(), timeout: 0.0)
                XCTFail("Expected requestTimeout")
            } catch let error as ParaWebViewError {
                guard case .requestTimeout = error else {
                    return XCTFail("Expected requestTimeout, got \(error)")
                }
            }
            capturedCompletion?(nil, expectedError)
            XCTAssertTrue(webView.pendingRequestIds.isEmpty)
        }
    }

    // MARK: - Model Codable Parity & Forward-Compatible Enums

    func testOnRampModelsDecodeCanonicalPayloadsAndUnknownEnums() throws {
        let configJSON = Data(#"""
        {
          "isBuyEnabled": true,
          "isReceiveEnabled": true,
          "isWithdrawEnabled": false,
          "isSendEnabled": true,
          "onRampSelectionMode": "CUSTOM",
          "defaultOnRampAssetImplementation": {
            "assetImplementationId": "impl-1",
            "assetId": "asset-usdc",
            "symbol": "USDC",
            "name": "USD Coin",
            "logoUrl": "https://cdn.example/usdc.png",
            "marketCapRank": 6,
            "networkId": "net-base",
            "chainId": "8453",
            "networkName": "Base",
            "networkLogoUrl": "https://cdn.example/base.png",
            "walletType": "EVM",
            "isTestnet": false,
            "contractAddress": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "decimals": 6,
            "providers": [
              {
                "provider": "BANXA",
                "isBuy": true,
                "isSell": true,
                "paymentMethods": ["CARD", "APPLE_PAY", "WIDGET"],
                "minAmount": 20,
                "maxAmount": 10000
              },
              {
                "provider": "TRANSAK",
                "isBuy": true,
                "isSell": false,
                "paymentMethods": ["CARD", "BANK", "FUTURE_METHOD"]
              },
              {
                "provider": "FUTURE_PROVIDER",
                "isBuy": true,
                "isSell": false,
                "paymentMethods": ["WIDGET"]
              }
            ]
          },
          "defaultBuyAmount": { "value": 50, "currency": "USD" },
          "rampApiKey": "ramp-key",
          "inlineApplePayProviders": ["CDP", "FUTURE_APPLE_PAY"],
          "reusableKycEnabled": true
        }
        """#.utf8)

        let config = try JSONDecoder().decode(ParaOnRampConfig.self, from: configJSON)
        XCTAssertTrue(config.isBuyEnabled)
        XCTAssertFalse(config.isWithdrawEnabled)
        XCTAssertEqual(config.onRampSelectionMode, "CUSTOM")
        XCTAssertEqual(config.defaultBuyAmount?.value, 50)
        XCTAssertEqual(config.defaultBuyAmount?.currency, "USD")
        XCTAssertEqual(config.inlineApplePayProviders, [.cdp, .unknown("FUTURE_APPLE_PAY")])
        XCTAssertEqual(config.reusableKycEnabled, true)
        XCTAssertEqual(
            config.defaultOnRampAssetImplementation?.providers.map(\.provider),
            [.banxa, .transak, .unknown("FUTURE_PROVIDER")]
        )
        XCTAssertEqual(
            config.defaultOnRampAssetImplementation?.providers[1].paymentMethods,
            [.card, .bank, .unknown("FUTURE_METHOD")]
        )

        let catalogJSON = Data(#"""
        {
          "items": [],
          "total": 42,
          "limit": 20,
          "offset": 0
        }
        """#.utf8)
        let catalog = try JSONDecoder().decode(ParaOnRampCatalogResponse.self, from: catalogJSON)
        XCTAssertEqual(catalog.total, 42)
        XCTAssertEqual(catalog.limit, 20)

        let orderResultJSON = Data(#"""
        {
          "onRampPurchase": {
            "id": "pur-123",
            "userId": "user-1",
            "type": "SELL",
            "walletId": "wallet-1",
            "walletType": "EVM",
            "status": "FAILED",
            "provider": "MOONPAY",
            "fiat": "USD",
            "fiatQuantity": 100,
            "asset": "USDC",
            "assetQuantity": 99.5,
            "network": "BASE",
            "paymentMethod": "WIDGET",
            "testMode": true
          },
          "eventData": {
            "userId": "user-1",
            "purchaseId": "pur-123",
            "provider": "MOONPAY",
            "direction": "SELL",
            "transactionHash": null,
            "asset": { "symbol": "USDC" },
            "testMode": true,
            "completedAt": null
          },
          "pendingDeposit": {
            "destinationAddress": "0xdeposit",
            "assetQuantity": 100,
            "asset": "USDC",
            "network": "BASE",
            "updatedAt": "2026-11-22T12:00:00.000Z"
          }
        }
        """#.utf8)
        let getOrder = try JSONDecoder().decode(ParaGetOnRampOrderResult.self, from: orderResultJSON)
        XCTAssertEqual(getOrder.onRampPurchase.status, .failed)
        XCTAssertEqual(getOrder.onRampPurchase.type, .sell)
        XCTAssertEqual(getOrder.onRampPurchase.fiatQuantity, "100")
        XCTAssertEqual(getOrder.onRampPurchase.assetQuantity, "99.5")
        XCTAssertEqual(getOrder.eventData?.purchaseId, "pur-123")
        XCTAssertEqual(getOrder.eventData?.direction, .sell)
        XCTAssertEqual(getOrder.pendingDeposit?.destinationAddress, "0xdeposit")
        XCTAssertEqual(getOrder.pendingDeposit?.assetQuantity, "100")

        let offRampFallbackJSON = Data(#"""
        {
          "txHash": "0xfallback",
          "updatedOnRampPurchase": {
            "id": "pur-off",
            "status": "INITIATED",
            "type": "SWAP_OUT"
          }
        }
        """#.utf8)
        let offRampResult = try JSONDecoder().decode(ParaSendOffRampDepositResult.self, from: offRampFallbackJSON)
        XCTAssertEqual(offRampResult.txHash, "0xfallback")
        XCTAssertEqual(offRampResult.onRampPurchase?.id, "pur-off")
        XCTAssertEqual(offRampResult.onRampPurchase?.type, .unknown("SWAP_OUT"))
    }

    func testBraleAndCoinbaseModelsDecodeAndEncode() throws {
        let braleCheckoutJSON = Data(#"""
        {
          "id": "chk-1",
          "walletId": "w-1",
          "amountUsd": "100.00",
          "stage": "link_required",
          "nextAction": "launch_plaid",
          "linkTokenExpiresAt": "2026-11-22T13:00:00.000Z",
          "plaidLinkToken": "link-sandbox-token",
          "purchaseId": null,
          "braleStatus": "pending",
          "failure": {
            "returnCode": "R01",
            "reason": "Insufficient funds",
            "category": "nsf",
            "retriable": true
          },
          "savedBank": {
            "name": "Chase Checking",
            "accountType": "checking",
            "accountNumberMask": "4821",
            "needsUpdate": false
          }
        }
        """#.utf8)
        let checkout = try JSONDecoder().decode(ParaBraleAchCheckout.self, from: braleCheckoutJSON)
        XCTAssertEqual(checkout.id, "chk-1")
        XCTAssertEqual(checkout.stage, "link_required")
        XCTAssertEqual(checkout.nextAction, "launch_plaid")
        XCTAssertEqual(checkout.plaidLinkToken, "link-sandbox-token")
        XCTAssertEqual(checkout.failure?.returnCode, "R01")
        XCTAssertEqual(checkout.savedBank?.accountNumberMask, "4821")

        let transfersJSON = Data(#"""
        {
          "transfers": [
            {
              "checkoutId": "chk-1",
              "purchaseId": "pur-1",
              "assetImplementationId": "impl-1",
              "amountUsd": "25.00",
              "asset": "USDC",
              "network": "BASE",
              "bankAccountMask": "4821",
              "stage": "submitted",
              "braleStatus": "complete",
              "createdAt": "2026-11-22T12:00:00.000Z",
              "failedAt": null,
              "failure": null
            }
          ]
        }
        """#.utf8)
        let transfers = try JSONDecoder().decode(ParaBraleTransferListResponse.self, from: transfersJSON)
        XCTAssertEqual(transfers.transfers.count, 1)
        XCTAssertEqual(transfers.transfers.first?.braleStatus, "complete")

        let cdpParams = ParaCoinbaseOrderParams(
            paymentAmount: "50.00",
            assetImplementationId: "impl-1",
            walletId: "w-1",
            phoneNumber: "+15555550100",
            domain: "app.example.com",
            purchaseId: "pur-cdp-pre"
        )
        let cdpParamsData = try JSONEncoder().encode(cdpParams)
        let cdpParamsDict = try XCTUnwrap(JSONSerialization.jsonObject(with: cdpParamsData) as? [String: Any])
        XCTAssertEqual(cdpParamsDict["domain"] as? String, "app.example.com")
        XCTAssertEqual(cdpParamsDict["purchaseId"] as? String, "pur-cdp-pre")

        let cdpOrderJSON = Data(#"""
        {
          "purchaseId": "pur-cdp-1",
          "order": {
            "orderId": "cdp-ord-1",
            "paymentTotal": "102.50",
            "paymentSubtotal": "100.00",
            "paymentCurrency": "USD",
            "purchaseAmount": "100.00",
            "purchaseCurrency": "USDC",
            "fees": [{ "type": "FEE_TYPE_NETWORK", "amount": "2.50", "currency": "USD" }],
            "exchangeRate": "1.00",
            "destinationAddress": "0xabc",
            "destinationNetwork": "base",
            "status": "ONRAMP_ORDER_STATUS_CREATED"
          },
          "paymentLink": {
            "url": "https://pay.coinbase.com/apple-pay",
            "paymentLinkType": "PAYMENT_LINK_TYPE_APPLE_PAY_BUTTON"
          }
        }
        """#.utf8)
        let cdpOrder = try JSONDecoder().decode(ParaCoinbaseOrderResult.self, from: cdpOrderJSON)
        XCTAssertEqual(cdpOrder.purchaseId, "pur-cdp-1")
        XCTAssertEqual(cdpOrder.paymentLink?.url, "https://pay.coinbase.com/apple-pay")
        XCTAssertEqual(cdpOrder.order?.fees?.first?.amount, "2.50")

        let limitsJSON = Data(#"""
        {
          "limits": [{ "limitType": "WEEKLY", "limit": "500", "remaining": "400", "currency": "USD" }],
          "status": "ACTIVE",
          "upgradeable": true
        }
        """#.utf8)
        let limits = try JSONDecoder().decode(ParaCoinbaseLimitsResult.self, from: limitsJSON)
        XCTAssertEqual(limits.upgradeable, true)
        XCTAssertEqual(limits.limits?.first?.remaining, "400")

        let upgradeJSON = Data(#"""
        {
          "upgradeUrl": "https://verify.coinbase.com/upgrade",
          "expiresAt": "2026-11-22T12:15:00.000Z"
        }
        """#.utf8)
        let upgrade = try JSONDecoder().decode(ParaCoinbaseLimitUpgradeResult.self, from: upgradeJSON)
        XCTAssertEqual(upgrade.upgradeUrl, "https://verify.coinbase.com/upgrade")
    }

    // MARK: - Portal URL Validation, Runtime Launching & Callback Parsing

    func testPortalUrlConstructionValidationAndCallbackParsing() throws {
        let portalUrl = try XCTUnwrap(
            URL(string: "https://portal.getpara.com/wallet/u1/on-ramp/p1#rampLaunchToken=secret-token")
        )
        let built = try ParaManager.buildOnRampPortalLaunchURL(
            portalUrl: portalUrl,
            callbackURLScheme: " myapp ",
            fallbackAppScheme: "com.para.app"
        )

        XCTAssertEqual(built.callbackScheme, "myapp")
        XCTAssertEqual(built.url.fragment, "rampLaunchToken=secret-token")
        XCTAssertEqual(built.url.valueOf("nativeCallbackUrl"), "myapp://")

        // Rejects non-http(s) URLs and missing hosts
        XCTAssertThrowsError(
            try ParaManager.buildOnRampPortalLaunchURL(
                portalUrl: XCTUnwrap(URL(string: "javascript:alert(1)")),
                callbackURLScheme: "myapp",
                fallbackAppScheme: "com.para.app"
            )
        )
        XCTAssertThrowsError(
            try ParaManager.buildOnRampPortalLaunchURL(
                portalUrl: XCTUnwrap(URL(string: "https:///no-host")),
                callbackURLScheme: "myapp",
                fallbackAppScheme: "com.para.app"
            )
        )

        // Rejects blank callback scheme instead of producing nativeCallbackUrl=://
        XCTAssertThrowsError(
            try ParaManager.buildOnRampPortalLaunchURL(
                portalUrl: portalUrl,
                callbackURLScheme: "   ",
                fallbackAppScheme: "com.para.app"
            )
        )
        XCTAssertThrowsError(
            try ParaManager.buildOnRampPortalLaunchURL(
                portalUrl: portalUrl,
                callbackURLScheme: nil,
                fallbackAppScheme: " "
            )
        )

        let callbackUrl = try XCTUnwrap(URL(string: "myapp://?status=FINISHED&purchaseId=pur-999"))
        let parsed = ParaManager.parseOnRampPortalCallback(callbackUrl)
        XCTAssertEqual(parsed.status, .finished)
        XCTAssertEqual(parsed.rawStatus, "FINISHED")
        XCTAssertEqual(parsed.purchaseId, "pur-999")
        XCTAssertNil(parsed.error)
    }

    @MainActor
    func testLaunchOnRampPortalRuntimeFlows() async throws {
        let portalUrl = try XCTUnwrap(
            URL(string: "https://portal.getpara.com/wallet/u1/on-ramp/p1#rampLaunchToken=tok123")
        )

        // 1. Returns callback URL on completion
        let successPresenter = MockOnRampPortalPresenter { url, scheme in
            XCTAssertEqual(scheme, "myapp")
            XCTAssertEqual(url.fragment, "rampLaunchToken=tok123")
            return URL(string: "myapp://?status=FINISHED&purchaseId=p1")!
        }
        let manager = MockOnRampParaManager()
        manager.onRampPortalPresenter = successPresenter
        let result = try await manager.launchOnRampPortal(portalUrl: portalUrl, callbackURLScheme: "myapp")
        XCTAssertEqual(result?.absoluteString, "myapp://?status=FINISHED&purchaseId=p1")

        // 2. Returns nil when user cancels ASWebAuthenticationSession
        let canceledPresenter = MockOnRampPortalPresenter { _, _ in
            throw NSError(
                domain: ASWebAuthenticationSessionError.errorDomain,
                code: ASWebAuthenticationSessionError.canceledLogin.rawValue
            )
        }
        manager.onRampPortalPresenter = canceledPresenter
        let canceledResult = try await manager.launchOnRampPortal(portalUrl: portalUrl, callbackURLScheme: "myapp")
        XCTAssertNil(canceledResult)

        // 3. Invalid portalUrl throws before presenting
        let invalidUrl = try XCTUnwrap(URL(string: "file:///etc/passwd"))
        do {
            _ = try await manager.launchOnRampPortal(portalUrl: invalidUrl, callbackURLScheme: "myapp")
            XCTFail("Expected invalid URL error")
        } catch {
            // Expected
        }

        // 4. Blank callbackURLScheme throws before presenting
        do {
            _ = try await manager.launchOnRampPortal(portalUrl: portalUrl, callbackURLScheme: "   ")
            XCTFail("Expected blank callbackURLScheme error")
        } catch {
            // Expected
        }

        // 5. Task cancellation cancels active presenter and throws CancellationError
        let hangingPresenter = MockOnRampPortalPresenter(neverReturns: true)
        manager.onRampPortalPresenter = hangingPresenter
        let task = Task {
            try await manager.launchOnRampPortal(portalUrl: portalUrl, callbackURLScheme: "myapp")
        }
        while !hangingPresenter.started {
            await Task.yield()
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            XCTAssertTrue(hangingPresenter.cancelled)
        }
    }

    // MARK: - ParaManager+OnRamp Canonical Wire Payloads

    @MainActor
    func testParaManagerOnRampMethodsSendCanonicalWirePayloads() async throws {
        let manager = MockOnRampParaManager()

        manager.stub("getOnRampConfig") { _ in
            [
                "isBuyEnabled": true,
                "isReceiveEnabled": true,
                "isWithdrawEnabled": true,
                "isSendEnabled": true,
                "onRampSelectionMode": "ALL",
            ]
        }
        let config = try await manager.getOnRampConfig(walletTypes: ["EVM"])
        XCTAssertEqual(config.onRampSelectionMode, "ALL")
        XCTAssertEqual(manager.recordedPayload(for: "getOnRampConfig")?["walletTypes"] as? [String], ["EVM"])

        manager.stub("getOnRampCatalog") { _ in
            ["items": [], "total": 0, "limit": 10, "offset": 0]
        }
        let catalog = try await manager.getOnRampCatalog(search: "USDC", networkId: "base", limit: 10, offset: 0, testMode: true)
        XCTAssertEqual(catalog.total, 0)
        XCTAssertEqual(manager.recordedPayload(for: "getOnRampCatalog")?["search"] as? String, "USDC")
        XCTAssertEqual(manager.recordedPayload(for: "getOnRampCatalog")?["testMode"] as? Bool, true)

        // Canonical nested createOnRampOrder payload: { walletId?, externalWalletAddress?, nativeCallbackUrl?, params: { ... } }
        manager.stub("createOnRampOrder") { _ in
            [
                "onRampPurchase": ["id": "pur-1", "status": "INITIATED", "provider": "STRIPE", "type": "BUY"],
                "portalUrl": "https://portal.getpara.com/wallet/u1/on-ramp/pur-1#rampLaunchToken=tok",
            ]
        }
        let created = try await manager.createOnRampOrder(
            ParaCreateOnRampOrderParams(
                walletId: "w-1",
                walletType: "EVM",
                provider: .stripe,
                type: .buy,
                assetImplementationId: "impl-1",
                fiat: "USD",
                fiatQuantity: "50",
                returnUrl: "https://portal.getpara.com/return",
                nativeCallbackUrl: "myapp://callback",
                purchaseId: "pur-client-1"
            )
        )
        XCTAssertEqual(created.onRampPurchase.id, "pur-1")
        let createPayload = try XCTUnwrap(manager.recordedPayload(for: "createOnRampOrder"))
        XCTAssertEqual(createPayload["walletId"] as? String, "w-1")
        XCTAssertEqual(createPayload["nativeCallbackUrl"] as? String, "myapp://callback")
        XCTAssertNil(createPayload["provider"])
        let nestedParams = try XCTUnwrap(createPayload["params"] as? [String: Any])
        XCTAssertEqual(nestedParams["provider"] as? String, "STRIPE")
        XCTAssertEqual(nestedParams["type"] as? String, "BUY")
        XCTAssertEqual(nestedParams["walletType"] as? String, "EVM")
        XCTAssertEqual(nestedParams["assetImplementationId"] as? String, "impl-1")
        XCTAssertEqual(nestedParams["returnUrl"] as? String, "https://portal.getpara.com/return")
        XCTAssertEqual(nestedParams["purchaseId"] as? String, "pur-client-1")

        // getOnRampOrder supports both walletId and externalWalletAddress, and rejects missing both
        manager.stub("getOnRampOrder") { _ in
            [
                "onRampPurchase": ["id": "pur-1", "status": "INITIATED"],
                "pendingDeposit": NSNull(),
            ]
        }
        let fetched = try await manager.getOnRampOrder(
            walletId: "w-1",
            purchaseId: "pur-1",
            walletType: "EVM",
            address: "0xabc"
        )
        XCTAssertEqual(fetched.onRampPurchase.id, "pur-1")
        XCTAssertEqual(manager.recordedPayload(for: "getOnRampOrder")?["purchaseId"] as? String, "pur-1")

        _ = try await manager.getOnRampOrder(
            purchaseId: "pur-ext",
            externalWalletAddress: "0xext"
        )
        let extOrderPayload = try XCTUnwrap(manager.recordedPayload(for: "getOnRampOrder"))
        XCTAssertNil(extOrderPayload["walletId"])
        XCTAssertEqual(extOrderPayload["externalWalletAddress"] as? String, "0xext")

        _ = try await manager.getOnRampOrder(
            walletId: "  ",
            purchaseId: "pur-addr",
            externalWalletAddress: "  ",
            address: " 0xfallback "
        )
        let fallbackAddrPayload = try XCTUnwrap(manager.recordedPayload(for: "getOnRampOrder"))
        XCTAssertNil(fallbackAddrPayload["walletId"])
        XCTAssertNil(fallbackAddrPayload["externalWalletAddress"])
        XCTAssertEqual(fallbackAddrPayload["address"] as? String, "0xfallback")

        do {
            _ = try await manager.getOnRampOrder(purchaseId: "pur-missing")
            XCTFail("Expected validation error when neither walletId nor externalWalletAddress is provided")
        } catch {
            // Expected
        }

        // Canonical nested sendOffRampDeposit payload: { onRampPurchase: { ... }, depositRequest: { ... } }
        manager.stub("sendOffRampDeposit") { _ in
            [
                "txHash": "0xtxhash",
                "onRampPurchase": ["id": "pur-1", "status": "INITIATED", "transactionHash": "0xtxhash"],
            ]
        }
        let depositResult = try await manager.sendOffRampDeposit(
            ParaSendOffRampDepositParams(
                purchaseId: "pur-1",
                walletId: "w-1",
                walletType: "EVM",
                provider: .moonpay,
                address: "0xsrc",
                destinationAddress: "0xdest",
                assetQuantity: "10",
                chainId: "8453",
                providerOrderId: "mp-ord-1",
                testMode: true
            )
        )
        XCTAssertEqual(depositResult.txHash, "0xtxhash")
        let depositPayload = try XCTUnwrap(manager.recordedPayload(for: "sendOffRampDeposit"))
        XCTAssertNil(depositPayload["purchaseId"])
        XCTAssertNil(depositPayload["destinationAddress"])
        let onRampPurchaseArg = try XCTUnwrap(depositPayload["onRampPurchase"] as? [String: Any])
        XCTAssertEqual(onRampPurchaseArg["id"] as? String, "pur-1")
        XCTAssertEqual(onRampPurchaseArg["walletId"] as? String, "w-1")
        XCTAssertEqual(onRampPurchaseArg["walletType"] as? String, "EVM")
        XCTAssertEqual(onRampPurchaseArg["provider"] as? String, "MOONPAY")
        XCTAssertEqual(onRampPurchaseArg["address"] as? String, "0xsrc")
        XCTAssertEqual(onRampPurchaseArg["testMode"] as? Bool, true)
        let depositRequestArg = try XCTUnwrap(depositPayload["depositRequest"] as? [String: Any])
        XCTAssertEqual(depositRequestArg["destinationAddress"] as? String, "0xdest")
        XCTAssertEqual(depositRequestArg["assetQuantity"] as? String, "10")
        XCTAssertEqual(depositRequestArg["chainId"] as? String, "8453")
        XCTAssertEqual(depositRequestArg["providerOrderId"] as? String, "mp-ord-1")

        // createBraleAchCheckout defaults nil platform to "ios" and preserves explicit platform
        manager.stub("createBraleAchCheckout") { _ in
            [
                "id": "chk-1",
                "walletId": "w-1",
                "amountUsd": "100.00",
                "stage": "link_required",
                "nextAction": "launch_plaid",
                "plaidLinkToken": "link-tok",
                "braleStatus": NSNull(),
                "failure": NSNull(),
            ]
        }
        let braleCheckout = try await manager.createBraleAchCheckout(
            ParaCreateBraleAchCheckoutParams(
                walletId: "w-1",
                assetImplementationId: "impl-1",
                amountUsd: "100.00",
                customer: ParaBraleAchCustomer(legalName: "Ada Lovelace")
            )
        )
        XCTAssertEqual(braleCheckout.id, "chk-1")
        XCTAssertEqual(manager.recordedPayload(for: "createBraleAchCheckout")?["platform"] as? String, "ios")

        _ = try await manager.createBraleAchCheckout(
            ParaCreateBraleAchCheckoutParams(
                walletId: "w-1",
                amountUsd: "50.00",
                platform: "web"
            )
        )
        XCTAssertEqual(manager.recordedPayload(for: "createBraleAchCheckout")?["platform"] as? String, "web")

        manager.stub("linkBraleAchBank") { _ in
            [
                "id": "chk-1",
                "walletId": "w-1",
                "amountUsd": "100.00",
                "stage": "linked",
                "nextAction": "confirm_deposit",
                "braleStatus": NSNull(),
                "failure": NSNull(),
            ]
        }
        let linked = try await manager.linkBraleAchBank(checkoutId: "chk-1", publicToken: "pub-1")
        XCTAssertEqual(linked.stage, "linked")
        XCTAssertEqual(manager.recordedPayload(for: "linkBraleAchBank")?["publicToken"] as? String, "pub-1")

        manager.stub("getBraleAchAuthorization") { _ in
            ["version": "2026-11-10", "text": "Authorize $100.00"]
        }
        let auth = try await manager.getBraleAchAuthorization(amountLabel: "$100.00", bankLabel: "Chase ••4821")
        XCTAssertEqual(auth.version, "2026-11-10")

        manager.stub("submitBraleAchDeposit") { _ in
            [
                "id": "chk-1",
                "walletId": "w-1",
                "amountUsd": "100.00",
                "stage": "submitted",
                "nextAction": "wait",
                "purchaseId": "pur-brale-1",
                "braleStatus": "pending",
                "failure": NSNull(),
            ]
        }
        let submitted = try await manager.submitBraleAchDeposit(checkoutId: "chk-1", authorizationTextVersion: "2026-11-10")
        XCTAssertEqual(submitted.purchaseId, "pur-brale-1")

        manager.stub("getBraleAchCheckout") { _ in
            [
                "id": "chk-1",
                "walletId": "w-1",
                "amountUsd": "100.00",
                "stage": "submitted",
                "nextAction": "wait",
                "braleStatus": "processing",
                "failure": NSNull(),
            ]
        }
        let chk = try await manager.getBraleAchCheckout(checkoutId: "chk-1")
        XCTAssertEqual(chk.braleStatus, "processing")

        manager.stub("listBraleAchTransfers") { _ in
            ["transfers": []]
        }
        let transferList = try await manager.listBraleAchTransfers()
        XCTAssertTrue(transferList.transfers.isEmpty)

        manager.stub("createCoinbaseOnrampOrder") { _ in
            ["purchaseId": "pur-cdp-1"]
        }
        let cdpOrder = try await manager.createCoinbaseOnrampOrder(
            ParaCoinbaseOrderParams(
                paymentAmount: "50.00",
                assetImplementationId: "impl-1",
                walletId: "w-1",
                phoneNumber: "+15555550100",
                domain: "app.example.com",
                purchaseId: "pur-cdp-1"
            )
        )
        XCTAssertEqual(cdpOrder.purchaseId, "pur-cdp-1")

        manager.stub("checkCoinbaseOnrampLimits") { _ in
            ["status": "ACTIVE", "upgradeable": false]
        }
        let limits = try await manager.checkCoinbaseOnrampLimits(ParaCoinbaseLimitsParams(testMode: true))
        XCTAssertEqual(limits.upgradeable, false)

        manager.stub("createCoinbaseOnrampLimitUpgrade") { _ in
            ["upgradeUrl": "https://verify.coinbase.com/u"]
        }
        let upgrade = try await manager.createCoinbaseOnrampLimitUpgrade(ParaCoinbaseLimitUpgradeParams(testMode: true))
        XCTAssertEqual(upgrade.upgradeUrl, "https://verify.coinbase.com/u")

        manager.stub("settleCoinbaseOnrampPurchase") { _ in
            ["status": "FINISHED"]
        }
        let settledFromDict = try await manager.settleCoinbaseOnrampPurchase(
            purchaseId: "pur-cdp-1",
            walletId: "w-1",
            externalWalletAddress: "0xext"
        )
        XCTAssertEqual(settledFromDict, "FINISHED")
        let settlePayload = try XCTUnwrap(manager.recordedPayload(for: "settleCoinbaseOnrampPurchase"))
        XCTAssertEqual(settlePayload["purchaseId"] as? String, "pur-cdp-1")
        XCTAssertEqual(settlePayload["walletId"] as? String, "w-1")
        XCTAssertEqual(settlePayload["externalWalletAddress"] as? String, "0xext")

        manager.stub("settleCoinbaseOnrampPurchase") { _ in
            "FINISHED"
        }
        let settledFromString = try await manager.settleCoinbaseOnrampPurchase(purchaseId: "pur-cdp-1")
        XCTAssertEqual(settledFromString, "FINISHED")
    }
}

@MainActor
private final class MockOnRampPortalPresenter: OnRampPortalPresenting {
    private let handler: ((URL, String) async throws -> URL)?
    private let neverReturns: Bool
    private var continuation: CheckedContinuation<URL, Error>?
    private(set) var started = false
    private(set) var cancelled = false

    init(handler: @escaping (URL, String) async throws -> URL) {
        self.handler = handler
        neverReturns = false
    }

    init(neverReturns: Bool) {
        handler = nil
        self.neverReturns = neverReturns
    }

    func present(url: URL, callbackURLScheme: String) async throws -> URL {
        started = true
        if neverReturns {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.continuation = continuation
                }
            } onCancel: {
                Task { @MainActor in
                    self.cancelled = true
                    self.continuation?.resume(throwing: CancellationError())
                    self.continuation = nil
                }
            }
        }
        guard let handler else {
            throw ParaError.error("Missing mock handler")
        }
        return try await handler(url, callbackURLScheme)
    }
}

@MainActor
private final class MockOnRampParaManager: ParaManager {
    private var handlers: [String: ([String: Any]?) -> Any?] = [:]
    private var payloads: [String: [String: Any]] = [:]

    init() {
        super.init(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "test"
        )
        paraWebView.initializationError = ParaWebViewError.webViewNotReady
    }

    func stub(_ method: String, handler: @escaping ([String: Any]?) -> Any?) {
        handlers[method] = handler
    }

    func recordedPayload(for method: String) -> [String: Any]? {
        payloads[method]
    }

    override func ensureWebViewReady() async throws {}

    override func postMessage(method: String, payload: Encodable, timeout _: TimeInterval?) async throws -> Any? {
        let data = try JSONEncoder().encode(AnyEncodable(payload))
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let dict {
            payloads[method] = dict
        }
        return handlers[method]?(dict)
    }
}

@MainActor
private final class ErrorForwardingParaManager: ParaManager {
    private let errorToThrow: Error

    init(errorToThrow: Error) {
        self.errorToThrow = errorToThrow
        super.init(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "test"
        )
        paraWebView.initializationError = ParaWebViewError.webViewNotReady
    }

    override func postMessage(method: String, payload _: Encodable, timeout _: TimeInterval?) async throws -> Any? {
        do {
            throw errorToThrow
        } catch let error as ParaWebViewError {
            try mapParaWebViewError(error, method: method)
        }
    }
}
