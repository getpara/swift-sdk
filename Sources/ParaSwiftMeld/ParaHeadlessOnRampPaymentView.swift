import MeldSDK
import ParaSwift
import SwiftUI
import UIKit

/// Apple Pay configuration forwarded to Meld's native Apple Pay sheet when `paymentMethod == .applePay`.
public struct ParaHeadlessOnRampApplePayRequest: Sendable, Equatable {
    public let amount: Decimal
    public let currencyCode: String
    public let walletAddress: String
    public let clientIpAddress: String
    public let email: String?
    public let summaryItemLabel: String

    public init(
        amount: Decimal,
        currencyCode: String = "USD",
        walletAddress: String,
        clientIpAddress: String,
        email: String? = nil,
        summaryItemLabel: String
    ) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.walletAddress = walletAddress
        self.clientIpAddress = clientIpAddress
        self.email = email
        self.summaryItemLabel = summaryItemLabel
    }

    var meldValue: MeldApplePayRequest {
        MeldApplePayRequest(
            amount: amount,
            currencyCode: currencyCode,
            walletAddress: walletAddress,
            clientIpAddress: clientIpAddress,
            email: email,
            summaryItemLabel: summaryItemLabel
        )
    }
}

/// Capabilities reported by `Meld.capabilities(for:)` for a parsed provider order.
public struct ParaMeldCapabilities: Sendable, Equatable {
    public let embeddable: Bool
    public let surface: String
    public let requiresUserGesture: Bool
}

/// Helpers for configuring `MeldSDK` and inspecting order capabilities outside `ParaHeadlessOnRampPaymentView`.
@MainActor
public enum ParaHeadlessOnRampPaymentHelper {
    /// Configures the native Meld SDK for the specified Para headless environment.
    public static func configure(environment: ParaHeadlessOnRampEnvironment) {
        let meldEnvironment: MeldEnvironment = switch environment {
        case .production: .production
        case .sandbox: .sandbox
        }
        Meld.configure(environment: meldEnvironment)
    }

    /// Inspects the native Meld capabilities for a headless on-ramp order.
    public static func capabilities(for order: ParaHeadlessOnRampOrderResult) throws -> ParaMeldCapabilities {
        let parsedOrder = try MeldOrder.from(jsonData: order.encodedOrderData())
        let capabilities = Meld.capabilities(for: parsedOrder)
        return ParaMeldCapabilities(
            embeddable: capabilities.embeddable,
            surface: capabilities.surface,
            requiresUserGesture: capabilities.requiresUserGesture
        )
    }
}

/// SwiftUI view wrapping `MeldSDK` (`Meld.configure`, `Meld.capabilities`, and `Meld.mount`) for headless on-ramp orders.
public struct ParaHeadlessOnRampPaymentView: UIViewRepresentable {
    public let order: ParaHeadlessOnRampOrderResult
    public let environment: ParaHeadlessOnRampEnvironment
    public let applePay: ParaHeadlessOnRampApplePayRequest?
    public let onReady: ((String?) -> Void)?
    public let onPaymentSubmitted: ((String?) -> Void)?
    public let onStatusChange: ((MeldStatusChange) -> Void)?
    public let onCancel: ((String?) -> Void)?
    public let onError: ((String, ParaHeadlessOnRampPaymentErrorOptions) -> Void)?
    public let onMeldError: ((MeldError) -> Void)?

    public init(
        order: ParaHeadlessOnRampOrderResult,
        environment: ParaHeadlessOnRampEnvironment,
        applePay: ParaHeadlessOnRampApplePayRequest? = nil,
        onReady: ((String?) -> Void)? = nil,
        onPaymentSubmitted: ((String?) -> Void)? = nil,
        onStatusChange: ((MeldStatusChange) -> Void)? = nil,
        onCancel: ((String?) -> Void)? = nil,
        onError: ((String, ParaHeadlessOnRampPaymentErrorOptions) -> Void)? = nil,
        onMeldError: ((MeldError) -> Void)? = nil
    ) {
        self.order = order
        self.environment = environment
        self.applePay = applePay
        self.onReady = onReady
        self.onPaymentSubmitted = onPaymentSubmitted
        self.onStatusChange = onStatusChange
        self.onCancel = onCancel
        self.onError = onError
        self.onMeldError = onMeldError
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context _: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.syncCallbacks(from: self)
        context.coordinator.mountIfNeeded(
            order: order,
            environment: environment,
            applePay: applePay,
            into: uiView
        )
    }

    public static func dismantleUIView(_: UIView, coordinator: Coordinator) {
        coordinator.unmount()
    }

    @MainActor
    public final class Coordinator {
        private var mountedKey: String?
        private var mountedApplePay: ParaHeadlessOnRampApplePayRequest?
        private var handle: MeldWidgetHandle?
        private var onReady: ((String?) -> Void)?
        private var onPaymentSubmitted: ((String?) -> Void)?
        private var onStatusChange: ((MeldStatusChange) -> Void)?
        private var onCancel: ((String?) -> Void)?
        private var onError: ((String, ParaHeadlessOnRampPaymentErrorOptions) -> Void)?
        private var onMeldError: ((MeldError) -> Void)?

        func syncCallbacks(from parent: ParaHeadlessOnRampPaymentView) {
            onReady = parent.onReady
            onPaymentSubmitted = parent.onPaymentSubmitted
            onStatusChange = parent.onStatusChange
            onCancel = parent.onCancel
            onError = parent.onError
            onMeldError = parent.onMeldError
        }

        func mountIfNeeded(
            order: ParaHeadlessOnRampOrderResult,
            environment: ParaHeadlessOnRampEnvironment,
            applePay: ParaHeadlessOnRampApplePayRequest?,
            into container: UIView
        ) {
            let nextKey = "\(environment.rawValue)|\(order.purchaseId)|\(order.orderId ?? "")"
            guard mountedKey != nextKey || mountedApplePay != applePay else { return }

            unmount()
            mountedKey = nextKey
            mountedApplePay = applePay
            ParaHeadlessOnRampPaymentHelper.configure(environment: environment)

            do {
                let parsedOrder = try MeldOrder.from(jsonData: order.encodedOrderData())
                let capabilities = Meld.capabilities(for: parsedOrder)
                if capabilities.surface == "unsupported" {
                    unmount()
                    onError?(
                        MeldErrorCode.paymentMethodUnavailable,
                        ParaHeadlessOnRampPaymentErrorOptions(attemptMayExist: false, loadFailed: false, recoverable: false)
                    )
                    return
                }

                let handlers = MeldEventHandlers(
                    onReady: { [weak self] orderId in
                        Task { @MainActor in
                            self?.onReady?(orderId)
                        }
                    },
                    onPaymentSubmitted: { [weak self] orderId in
                        Task { @MainActor in
                            self?.onPaymentSubmitted?(orderId)
                        }
                    },
                    onStatusChange: { [weak self] change in
                        Task { @MainActor in
                            self?.onStatusChange?(change)
                        }
                    },
                    onCancel: { [weak self] orderId in
                        Task { @MainActor in
                            self?.onCancel?(orderId)
                        }
                    },
                    onError: { [weak self] meldError in
                        Task { @MainActor in
                            self?.onMeldError?(meldError)
                            let loadFailed = meldError.code == MeldErrorCode.providerLoadFailed
                            if !meldError.recoverable || loadFailed {
                                self?.unmount()
                                let attemptMayExist = !loadFailed && (meldError.attemptMayExist || MeldErrorCode.attemptMayExist(meldError.code))
                                self?.onError?(
                                    meldError.code,
                                    ParaHeadlessOnRampPaymentErrorOptions(
                                        attemptMayExist: attemptMayExist,
                                        loadFailed: loadFailed,
                                        recoverable: meldError.recoverable
                                    )
                                )
                            }
                        }
                    }
                )

                handle = try Meld.mount(
                    parsedOrder,
                    into: capabilities.embeddable ? container : nil,
                    applePay: applePay?.meldValue,
                    handlers: handlers
                )
            } catch {
                unmount()
                onError?(
                    "MOUNT_FAILED",
                    ParaHeadlessOnRampPaymentErrorOptions(attemptMayExist: false, loadFailed: true, recoverable: false)
                )
            }
        }

        func unmount() {
            handle?.unmount()
            handle = nil
            mountedKey = nil
            mountedApplePay = nil
        }
    }
}
