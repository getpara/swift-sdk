import Combine
import Foundation

/// Current stage of a routed headless on-ramp checkout.
public enum ParaHeadlessOnRampCheckoutStep: String, Sendable, Equatable {
    case idle = "IDLE"
    case starting = "STARTING"
    case review = "REVIEW"
    case verificationRequired = "VERIFICATION_REQUIRED"
    case submitting = "SUBMITTING"
    case payment = "PAYMENT"
    case processing = "PROCESSING"
    case success = "SUCCESS"
    case failure = "FAILURE"
}

/// Recovery action performed by `ParaHeadlessOnRampCheckout.retry()`.
public enum ParaHeadlessOnRampRetryAction: String, Sendable, Equatable {
    case start = "START"
    case confirm = "CONFIRM"
    case remount = "REMOUNT"
    case none = "NONE"
}

/// Target environment passed to the Meld native SDK.
public enum ParaHeadlessOnRampEnvironment: String, Codable, Sendable, Equatable {
    case sandbox
    case production

    public init(paraEnvironment: ParaEnvironment) {
        switch paraEnvironment {
        case .prod:
            self = .production
        case .dev, .sandbox, .beta:
            self = .sandbox
        }
    }
}

/// Normalized payment error metadata reported by `ParaHeadlessOnRampPaymentView` or a custom payment surface.
public struct ParaHeadlessOnRampPaymentErrorOptions: Sendable, Equatable {
    public let attemptMayExist: Bool
    public let loadFailed: Bool
    public let recoverable: Bool

    public init(
        attemptMayExist: Bool = false,
        loadFailed: Bool = false,
        recoverable: Bool = false
    ) {
        self.attemptMayExist = attemptMayExist
        self.loadFailed = loadFailed
        self.recoverable = recoverable
    }
}

private struct QuotedHeadlessPurchase {
    let params: ParaHeadlessOnRampQuoteParams
    let walletId: String
    let amountUsd: String?
}

private enum PollReadResult {
    case ok(ParaOnRampPurchaseStatus?)
    case fatal
    case transient
}

private final class PollTaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>?) {
        lock.lock()
        let previous = task
        task = newTask
        lock.unlock()
        previous?.cancel()
    }

    func cancelAll() {
        replace(with: nil)
    }
}

/// Observable state machine orchestrating routed headless card and Apple Pay checkouts.
@MainActor
public final class ParaHeadlessOnRampCheckout: ObservableObject {
    public static let methodUnavailableMessage =
        "This payment method isn't available here. Choose another way to pay."
    public static let loadFailedMessage = "The payment form did not load."
    public static let orderCancelledMessage = "No funds were added to your wallet."

    private static let missingPurchaseMessage =
        "This purchase is missing its wallet or amount. Go back and try again."
    private static let startFailedMessage = "Could not start the purchase."
    private static let contactMissingMessage = "Add an email address to your account to continue."
    private static let orderStatusUnavailableMessage =
        "Could not check the status of your purchase. Check your wallet activity before trying again."
    private static let orderPollTimeoutMessage =
        "We are still confirming your purchase. Check your wallet activity before trying again."

    private static let maxPollAttempts = 120
    private static let maxConsecutivePollErrors = 12
    private static let maxPollErrorBackoffSeconds: Double = 30.0
    private static let requestTimeoutStatus = 408
    private static let htmlTagRegex = try? NSRegularExpression(pattern: "<[a-z!/]", options: [.caseInsensitive])
    private static let usdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private struct NoAttemptOutcome {
        let message: String
        let retryAction: ParaHeadlessOnRampRetryAction
    }

    private static let noAttemptOutcomes: [String: NoAttemptOutcome] = [
        "PAYMENT_REJECTED": NoAttemptOutcome(
            message: "Your payment was declined. Try another card or payment method.",
            retryAction: .start
        ),
        "PAYMENT_METHOD_UNAVAILABLE": NoAttemptOutcome(
            message: methodUnavailableMessage,
            retryAction: .none
        ),
        "VERIFICATION_PENDING": NoAttemptOutcome(
            message: "Your identity is still in review. Try again later.",
            retryAction: .none
        ),
        "ORDER_STATE_CHANGED": NoAttemptOutcome(
            message: "This order expired. Try again to start a new one.",
            retryAction: .start
        ),
        "PRESENTATION_FAILED": NoAttemptOutcome(
            message: loadFailedMessage,
            retryAction: .start
        ),
    ]
    private static let defaultNoAttemptOutcome = NoAttemptOutcome(
        message: "The payment failed.",
        retryAction: .start
    )
    private static let agreementErrorCodes: Set<String> = [
        "ONRAMP_AGREEMENT_REQUIRED",
        "ONRAMP_AGREEMENT_UNKNOWN",
    ]
    private static let repeatableOrderCodes: Set<String> = [
        "ONRAMP_ORDER_IN_PROGRESS",
        "MELD_ORDER_FAILED",
    ]

    @Published public private(set) var step: ParaHeadlessOnRampCheckoutStep = .idle
    @Published public private(set) var error: String?
    @Published public private(set) var quote: ParaHeadlessOnRampQuote?
    @Published public private(set) var agreements: [ParaHeadlessOnRampAgreement] = []
    @Published public private(set) var order: ParaHeadlessOnRampOrderResult?
    @Published public private(set) var canRetry: Bool = true

    public var walletId: String?
    public var assetImplementationId: String?
    public var amountUsd: String?
    public var provider: ParaOnRampProvider?
    public var paymentMethod: ParaHeadlessOnRampPaymentMethod?

    public var providerSessionToken: String? {
        order?.providerSessionToken
    }

    public var environment: ParaHeadlessOnRampEnvironment {
        ParaHeadlessOnRampEnvironment(paraEnvironment: client?.environment ?? .sandbox)
    }

    private weak var client: (any ParaHeadlessOnRampClient)?
    private let prefetchSdk: (@MainActor () async throws -> Void)?
    private let unmountPayment: (@MainActor () -> Void)?
    private let pollIntervalNanoseconds: UInt64

    private var quotedPurchase: QuotedHeadlessPurchase?
    private var acceptedAgreements: [ParaHeadlessOnRampAgreement] = []
    private var idempotencyKey: String?
    private var acceptedKey: String?
    private var trackedPurchaseId: String?
    private var trackedWalletId: String?
    private var operationGeneration: UInt64 = 0
    private var pollGeneration: UInt64 = 0
    private var pollAttempts = 0
    private var consecutivePollErrors = 0
    private var retryAction: ParaHeadlessOnRampRetryAction = .start
    private var isTracking = false
    private var isConfirming = false
    private var isCancelled = false
    private let pollTaskHolder = PollTaskHolder()

    public init(
        client: (any ParaHeadlessOnRampClient)?,
        walletId: String? = nil,
        assetImplementationId: String? = nil,
        amountUsd: String? = nil,
        provider: ParaOnRampProvider? = nil,
        paymentMethod: ParaHeadlessOnRampPaymentMethod? = nil,
        prefetchSdk: (@MainActor () async throws -> Void)? = nil,
        unmountPayment: (@MainActor () -> Void)? = nil,
        pollIntervalNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.client = client
        self.walletId = walletId
        self.assetImplementationId = assetImplementationId
        self.amountUsd = amountUsd
        self.provider = provider
        self.paymentMethod = paymentMethod
        self.prefetchSdk = prefetchSdk
        self.unmountPayment = unmountPayment
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    deinit {
        pollTaskHolder.cancelAll()
    }

    /// Fetches the quote and user requirements and moves to `.review`, `.verificationRequired`, or `.failure`.
    public func start() async {
        guard !isTracking else { return }
        isCancelled = false
        operationGeneration &+= 1
        let expectedGeneration = operationGeneration
        stopPolling()
        unmountPayment?()
        error = nil

        guard let client,
              let walletId = nonEmptyTrimmed(walletId),
              let assetImplementationId = nonEmptyTrimmed(assetImplementationId),
              let amountUsd = nonEmptyTrimmed(amountUsd),
              let provider,
              let paymentMethod
        else {
            fail(Self.missingPurchaseMessage, retryAction: .start)
            return
        }

        let quoteParams = ParaHeadlessOnRampQuoteParams(
            provider: provider,
            paymentMethod: paymentMethod,
            assetImplementationId: assetImplementationId,
            fiatAmount: amountUsd,
            fiat: "USD"
        )
        quotedPurchase = nil
        moveTo(.starting)

        do {
            try await prefetchSdk?()
            guard !isCancelled, operationGeneration == expectedGeneration else { return }

            let quoteResult = try await client.getHeadlessOnRampQuote(quoteParams)
            guard !isCancelled, operationGeneration == expectedGeneration else { return }

            let requirements = try await client.getHeadlessOnRampRequirements(
                ParaHeadlessOnRampRequirementsParams(
                    provider: provider,
                    paymentMethod: paymentMethod,
                    assetImplementationId: assetImplementationId,
                    fiatAmount: amountUsd,
                    fiat: "USD",
                    walletId: walletId
                )
            )
            guard !isCancelled, operationGeneration == expectedGeneration else { return }

            quotedPurchase = QuotedHeadlessPurchase(params: quoteParams, walletId: walletId, amountUsd: amountUsd)
            quote = quoteResult.quote
            acceptedAgreements = requirements.agreements
            agreements = requirements.agreements
            order = nil
            trackedPurchaseId = nil
            trackedWalletId = nil
            idempotencyKey = nil
            setRetryAction(.start)

            if Self.needsVerification(requirements.missingSteps) {
                moveTo(.verificationRequired)
            } else if requirements.missingSteps.contains(.contact) {
                fail(Self.contactMissingMessage, retryAction: .start)
            } else {
                moveTo(.review)
            }
        } catch {
            guard !isCancelled, operationGeneration == expectedGeneration else { return }
            fail(purchaseErrorMessage(from: error, amountUsd: amountUsd), retryAction: .start)
        }
    }

    /// Accepts required agreements and creates the provider order, then transitions to `.payment`.
    public func confirm() async {
        guard let client, let quoted = quotedPurchase, !isTracking, !isConfirming else { return }
        guard canConfirmFromCurrentState else { return }

        let expectedGeneration = operationGeneration
        isConfirming = true
        error = nil
        moveTo(.submitting)

        do {
            let currentKey = idempotencyKey ?? UUID().uuidString
            idempotencyKey = currentKey
            let codes = acceptedAgreements.map(\.code)
            if !codes.isEmpty, acceptedKey != currentKey {
                _ = try await client.acceptHeadlessOnRampAgreements(
                    ParaHeadlessOnRampAgreementsParams(
                        provider: quoted.params.provider,
                        paymentMethod: quoted.params.paymentMethod,
                        codes: codes
                    )
                )
                guard !isCancelled, operationGeneration == expectedGeneration else {
                    isConfirming = false
                    return
                }
                acceptedKey = currentKey
            }

            let createdOrder = try await client.createHeadlessOnRampOrder(
                ParaHeadlessOnRampOrderParams(
                    provider: quoted.params.provider,
                    paymentMethod: quoted.params.paymentMethod,
                    assetImplementationId: quoted.params.assetImplementationId,
                    fiatAmount: quoted.params.fiatAmount,
                    fiat: quoted.params.fiat,
                    walletId: quoted.walletId,
                    idempotencyKey: currentKey
                )
            )
            guard !isCancelled, operationGeneration == expectedGeneration else {
                isConfirming = false
                return
            }

            order = createdOrder
            isConfirming = false
            moveTo(.payment)
        } catch {
            guard !isCancelled, operationGeneration == expectedGeneration else {
                isConfirming = false
                return
            }
            let parsed = parseBridgeError(error)
            if let closedPurchaseId = Self.closedPurchaseId(from: parsed) {
                isConfirming = false
                await trackClosedOrder(purchaseId: closedPurchaseId, walletId: quoted.walletId)
                return
            }
            if Self.needsVerification(Self.missingSteps(from: parsed)) {
                isConfirming = false
                setRetryAction(.start)
                moveTo(.verificationRequired)
                return
            }
            if let code = parsed.code, Self.agreementErrorCodes.contains(code) {
                isConfirming = false
                await start()
                return
            }

            isConfirming = false
            fail(
                purchaseErrorMessage(from: parsed, amountUsd: quoted.amountUsd),
                retryAction: Self.canRepeatOrderKey(parsed) ? .confirm : .start
            )
        }
    }

    /// Retries the checkout according to the failure's retry policy (`.remount`, `.confirm`, `.start`, or `.none`).
    public func retry() async {
        guard !isTracking else { return }
        switch retryAction {
        case .none:
            return
        case .remount:
            guard order != nil else {
                await start()
                return
            }
            error = nil
            moveTo(.payment)
        case .confirm:
            if idempotencyKey != nil {
                await confirm()
            } else {
                await start()
            }
        case .start:
            await start()
        }
    }

    /// Notifies the checkout that payment details were submitted and begins polling `getOnRampOrder`.
    public func onPaymentSubmitted() {
        unmountPayment?()
        stopPolling()
        isTracking = true
        pollAttempts = 0
        consecutivePollErrors = 0
        trackedPurchaseId = order?.purchaseId ?? trackedPurchaseId
        trackedWalletId = quotedPurchase?.walletId ?? nonEmptyTrimmed(walletId) ?? trackedWalletId
        moveTo(.processing)
        schedulePoll(delayNanoseconds: pollIntervalNanoseconds)
    }

    /// Notifies the checkout that the user cancelled the payment surface before submission.
    public func onPaymentCancelled() {
        guard !isTracking else { return }
        unmountPayment?()
        idempotencyKey = nil
        moveTo(.review)
    }

    /// Handles a normalized payment error reported by `ParaHeadlessOnRampPaymentView` or a custom payment surface.
    public func onPaymentError(
        code: String,
        options: ParaHeadlessOnRampPaymentErrorOptions = ParaHeadlessOnRampPaymentErrorOptions()
    ) {
        guard !isTracking else { return }
        if !options.loadFailed, options.attemptMayExist {
            onPaymentSubmitted()
            return
        }
        unmountPayment?()
        if !options.loadFailed {
            let outcome = Self.noAttemptOutcomes[code] ?? Self.defaultNoAttemptOutcome
            fail(outcome.message, retryAction: outcome.retryAction)
            return
        }
        fail(Self.loadFailedMessage, retryAction: options.recoverable ? .remount : .start)
    }

    /// Unmounts the payment surface and transitions directly to `.failure`.
    public func failPayment(
        _ message: String,
        retryAction: ParaHeadlessOnRampRetryAction = .start
    ) {
        guard !isTracking else { return }
        unmountPayment?()
        let allowedAction: ParaHeadlessOnRampRetryAction = retryAction == .none ? .none : .start
        fail(message, retryAction: allowedAction)
    }

    /// Cancels active polling and unmounts the payment surface.
    public func cancel() {
        isCancelled = true
        operationGeneration &+= 1
        isConfirming = false
        stopPolling()
        unmountPayment?()
    }

    // MARK: - Polling

    private func trackClosedOrder(purchaseId: String, walletId: String) async {
        let expectedGeneration = operationGeneration
        stopPolling()
        isTracking = true
        pollAttempts = 0
        consecutivePollErrors = 0
        trackedPurchaseId = purchaseId
        trackedWalletId = walletId
        moveTo(.processing)

        let result = await readTrackedOrder()
        guard !isCancelled, operationGeneration == expectedGeneration else { return }

        switch result {
        case .fatal:
            fail(Self.orderStatusUnavailableMessage, retryAction: .none)
        case let .ok(status):
            if !settleTrackedOrder(status) {
                pollAttempts = 1
                schedulePoll(delayNanoseconds: pollIntervalNanoseconds)
            }
        case .transient:
            consecutivePollErrors = 1
            pollAttempts = 1
            schedulePoll(delayNanoseconds: pollIntervalNanoseconds)
        }
    }

    private func readTrackedOrder() async -> PollReadResult {
        guard let client,
              let purchaseId = trackedPurchaseId,
              let walletId = trackedWalletId
        else {
            return .fatal
        }

        do {
            let fetched = try await client.getOnRampOrder(
                walletId: walletId,
                purchaseId: purchaseId,
                externalWalletAddress: nil,
                walletType: nil,
                address: nil
            )
            return .ok(fetched.status)
        } catch {
            let parsed = parseBridgeError(error)
            return Self.isFatalPollError(parsed, rawError: error) ? .fatal : .transient
        }
    }

    private func settleTrackedOrder(_ status: ParaOnRampPurchaseStatus?) -> Bool {
        if status == .finished {
            moveTo(.success)
            return true
        }
        if status == .cancelled {
            isTracking = false
            fail(Self.orderCancelledMessage, retryAction: .start)
            return true
        }
        return false
    }

    private func schedulePoll(delayNanoseconds: UInt64) {
        guard !isCancelled, trackedPurchaseId != nil, trackedWalletId != nil else { return }
        pollGeneration &+= 1
        let expectedGeneration = pollGeneration

        let task = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self, !self.isCancelled, self.pollGeneration == expectedGeneration else {
                return
            }

            let result = await self.readTrackedOrder()
            guard !Task.isCancelled, !self.isCancelled, self.pollGeneration == expectedGeneration else {
                return
            }

            switch result {
            case .fatal:
                self.stopPolling()
                self.fail(Self.orderStatusUnavailableMessage, retryAction: .none)
            case let .ok(status):
                if self.settleTrackedOrder(status) {
                    self.stopPolling()
                    return
                }
                self.pollAttempts += 1
                self.consecutivePollErrors = 0
                if self.pollAttempts >= Self.maxPollAttempts {
                    self.stopPolling()
                    self.fail(Self.orderPollTimeoutMessage, retryAction: .none)
                    return
                }
                self.schedulePoll(delayNanoseconds: self.pollIntervalNanoseconds)
            case .transient:
                self.pollAttempts += 1
                self.consecutivePollErrors += 1
                if self.consecutivePollErrors >= Self.maxConsecutivePollErrors
                    || self.pollAttempts >= Self.maxPollAttempts
                {
                    self.stopPolling()
                    self.fail(Self.orderPollTimeoutMessage, retryAction: .none)
                    return
                }
                let baseSeconds = Double(self.pollIntervalNanoseconds) / 1_000_000_000.0
                let exponent = Double(self.consecutivePollErrors - 1)
                let backoffSeconds = min(baseSeconds * pow(2.0, exponent), Self.maxPollErrorBackoffSeconds)
                let nextDelay = UInt64(max(0.0, backoffSeconds) * 1_000_000_000.0)
                self.schedulePoll(delayNanoseconds: nextDelay)
            }
        }
        pollTaskHolder.replace(with: task)
    }

    private func stopPolling() {
        pollGeneration &+= 1
        pollTaskHolder.cancelAll()
    }

    // MARK: - State & Error Helpers

    private var canConfirmFromCurrentState: Bool {
        step == .review || (step == .failure && retryAction == .confirm)
    }

    private func moveTo(_ next: ParaHeadlessOnRampCheckoutStep) {
        step = next
    }

    private func setRetryAction(_ action: ParaHeadlessOnRampRetryAction) {
        retryAction = action
        canRetry = action != .none
    }

    private func fail(_ message: String, retryAction: ParaHeadlessOnRampRetryAction) {
        setRetryAction(retryAction)
        error = message
        moveTo(.failure)
    }

    private struct ParsedBridgeError {
        let message: String
        let code: String?
        let status: Int?
        let details: BridgeJSONValue?
        let hasStructuredStatus: Bool
    }

    private func parseBridgeError(_ error: Error) -> ParsedBridgeError {
        if let payload = error as? ParaBridgeErrorPayload {
            return ParsedBridgeError(
                message: payload.message,
                code: payload.code,
                status: payload.status,
                details: payload.details,
                hasStructuredStatus: true
            )
        }

        if case let ParaError.bridgeError(formatted) = error {
            if let manager = client as? ParaManager,
               let payload = manager.consumeLastBridgeErrorPayload(matchingFormattedMessage: formatted)
            {
                return ParsedBridgeError(
                    message: payload.message,
                    code: payload.code,
                    status: payload.status,
                    details: payload.details,
                    hasStructuredStatus: true
                )
            }
            return Self.parseFormattedBridgeMessage(formatted)
        }

        return ParsedBridgeError(
            message: error.localizedDescription,
            code: nil,
            status: nil,
            details: nil,
            hasStructuredStatus: false
        )
    }

    private static func parseFormattedBridgeMessage(_ formatted: String) -> ParsedBridgeError {
        // Matches `ParaBridgeErrorPayload.formattedMessage`: `<message> (code: <CODE>, status: <STATUS>)`
        guard formatted.hasSuffix(")"),
              let openParen = formatted.range(of: " (", options: .backwards)
        else {
            return ParsedBridgeError(
                message: formatted,
                code: nil,
                status: nil,
                details: nil,
                hasStructuredStatus: false
            )
        }

        let suffix = String(formatted[formatted.index(openParen.lowerBound, offsetBy: 2) ..< formatted.index(before: formatted.endIndex)])
        let parts = suffix.components(separatedBy: ", ")
        var parsedCode: String?
        var parsedStatus: Int?
        var matchedAny = false

        for part in parts {
            if part.hasPrefix("code: ") {
                parsedCode = String(part.dropFirst("code: ".count))
                matchedAny = true
            } else if part.hasPrefix("status: "), let intVal = Int(part.dropFirst("status: ".count)) {
                parsedStatus = intVal
                matchedAny = true
            } else {
                matchedAny = false
                break
            }
        }

        guard matchedAny else {
            return ParsedBridgeError(
                message: formatted,
                code: nil,
                status: nil,
                details: nil,
                hasStructuredStatus: false
            )
        }

        let baseMessage = String(formatted[..<openParen.lowerBound])
        return ParsedBridgeError(
            message: baseMessage,
            code: parsedCode,
            status: parsedStatus,
            details: nil,
            hasStructuredStatus: true
        )
    }

    private static func detailValue(_ key: String, in details: BridgeJSONValue?) -> BridgeJSONValue? {
        guard let dict = details?.objectValue else { return nil }
        if let topLevel = dict[key] {
            return topLevel
        }
        return dict["data"]?.objectValue?[key]
    }

    private static func missingSteps(from parsed: ParsedBridgeError) -> [ParaHeadlessOnRampMissingStep] {
        guard parsed.code == "ONRAMP_REQUIREMENTS_NOT_MET" else { return [] }
        guard let values = detailValue("missingSteps", in: parsed.details)?.arrayValue else {
            return []
        }
        return values.compactMap { $0.stringValue.flatMap(ParaHeadlessOnRampMissingStep.init(rawValue:)) }
    }

    private static func needsVerification(_ steps: [ParaHeadlessOnRampMissingStep]) -> Bool {
        steps.contains(.verification) || steps.contains(.share)
    }

    private static func closedPurchaseId(from parsed: ParsedBridgeError) -> String? {
        guard parsed.code == "ONRAMP_ORDER_CLOSED" else { return nil }
        return detailValue("purchaseId", in: parsed.details)?.stringValue
    }

    private static func canRepeatOrderKey(_ parsed: ParsedBridgeError) -> Bool {
        if let code = parsed.code, repeatableOrderCodes.contains(code) {
            return true
        }
        guard parsed.hasStructuredStatus else { return true }
        guard let status = parsed.status else { return true }
        return status == requestTimeoutStatus || status >= 500
    }

    private static func isFatalPollError(_ parsed: ParsedBridgeError, rawError _: Error) -> Bool {
        if parsed.hasStructuredStatus, let status = parsed.status {
            return status == 401 || status == 403 || status == 404
        }
        return parsed.message == "no userId is set"
    }

    private func purchaseErrorMessage(from error: Error, amountUsd: String?) -> String {
        purchaseErrorMessage(from: parseBridgeError(error), amountUsd: amountUsd)
    }

    private func purchaseErrorMessage(from parsed: ParsedBridgeError, amountUsd: String?) -> String {
        switch parsed.code {
        case "ONRAMP_METHOD_NOT_OFFERED":
            return Self.methodUnavailableMessage
        case "ONRAMP_AMOUNT_OUT_OF_RANGE":
            let minVal = Self.detailValue("minAmount", in: parsed.details)?.doubleValue
            let maxVal = Self.detailValue("maxAmount", in: parsed.details)?.doubleValue
            return Self.amountRangeMessage(amountUsd: amountUsd ?? "", min: minVal, max: maxVal) ?? Self.startFailedMessage
        case "ONRAMP_REQUIREMENTS_NOT_MET":
            return Self.missingSteps(from: parsed).contains(.contact) ? Self.contactMissingMessage : Self.startFailedMessage
        default:
            return Self.friendlyErrorMessage(from: parsed, fallback: Self.startFailedMessage)
        }
    }

    private static func friendlyErrorMessage(from parsed: ParsedBridgeError, fallback: String) -> String {
        if parsed.hasStructuredStatus {
            let showableStatus = parsed.status == 503 || (parsed.status != nil && parsed.status! >= 400 && parsed.status! < 500)
            let range = NSRange(location: 0, length: parsed.message.utf16.count)
            let hasHtml = htmlTagRegex?.firstMatch(in: parsed.message, options: [], range: range) != nil
            if showableStatus, !parsed.message.isEmpty, !hasHtml {
                return parsed.message
            }
            return fallback
        }
        return parsed.message.isEmpty ? fallback : parsed.message
    }

    private static func amountRangeMessage(amountUsd: String, min: Double?, max: Double?) -> String? {
        guard let amount = Double(amountUsd), !amount.isNaN else { return nil }
        if let min, amount < min, let formatted = formatUsdLimit(min) {
            return "Minimum amount is \(formatted)"
        }
        if let max, amount > max, let formatted = formatUsdLimit(max) {
            return "Maximum amount is \(formatted)"
        }
        return nil
    }

    private static func formatUsdLimit(_ limit: Double) -> String? {
        guard let formattedNumber = usdFormatter.string(from: NSNumber(value: limit)) else {
            return nil
        }
        return "$\(formattedNumber)"
    }

    private func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
