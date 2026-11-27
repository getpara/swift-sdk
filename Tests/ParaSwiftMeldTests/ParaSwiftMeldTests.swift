@testable import ParaSwift
@testable import ParaSwiftMeld
import XCTest

final class ParaSwiftMeldTests: XCTestCase {
    func testApplePayRequestPropertiesAndMeldMapping() {
        let req = ParaHeadlessOnRampApplePayRequest(
            amount: Decimal(string: "25.50")!,
            currencyCode: "USD",
            walletAddress: "0x1111111111111111111111111111111111111111",
            clientIpAddress: "203.0.113.10",
            email: "buyer@example.com",
            summaryItemLabel: "Purchase USDC"
        )

        XCTAssertEqual(req.amount, Decimal(string: "25.50")!)
        XCTAssertEqual(req.currencyCode, "USD")
        XCTAssertEqual(req.email, "buyer@example.com")
        let meldReq = req.meldValue
        XCTAssertEqual(meldReq.walletAddress, "0x1111111111111111111111111111111111111111")
        XCTAssertEqual(meldReq.summaryItemLabel, "Purchase USDC")
    }

    @MainActor
    func testCoordinatorUnmountsOnUnsupportedSurfaceForRemount() {
        let unsupportedOrder = ParaHeadlessOnRampOrderResult(
            purchaseId: "pur-1",
            order: ["unexpected": .string("payload")]
        )
        var reportedCodes: [(String, ParaHeadlessOnRampPaymentErrorOptions)] = []
        let view = ParaHeadlessOnRampPaymentView(
            order: unsupportedOrder,
            environment: .sandbox,
            onError: { code, opts in
                reportedCodes.append((code, opts))
            }
        )

        let coordinator = view.makeCoordinator()
        coordinator.syncCallbacks(from: view)
        let container = UIView()
        coordinator.mountIfNeeded(
            order: unsupportedOrder,
            environment: .sandbox,
            applePay: nil,
            into: container
        )

        XCTAssertEqual(reportedCodes.count, 1)
        XCTAssertEqual(reportedCodes.first?.0, "PAYMENT_METHOD_UNAVAILABLE")
        XCTAssertEqual(reportedCodes.first?.1.loadFailed, false)

        coordinator.mountIfNeeded(
            order: unsupportedOrder,
            environment: .sandbox,
            applePay: nil,
            into: container
        )
        XCTAssertEqual(reportedCodes.count, 2)
    }
}
