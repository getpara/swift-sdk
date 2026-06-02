import XCTest
@testable import ParaSwift

final class StellarTests: XCTestCase {
    func testWalletTypeDecodesStellar() {
        let wallet = Wallet(result: [
            "id": "stellar-wallet",
            "type": "STELLAR",
            "address": "GDNE6FB6Z4PD4DLHQDAJMXFZKCXOJGHFDKRJV4FM7QXCHY2ZUPRDEZKV",
            "scheme": "ED25519",
        ])

        XCTAssertEqual(wallet.type, .stellar)
        XCTAssertEqual(wallet.address, "GDNE6FB6Z4PD4DLHQDAJMXFZKCXOJGHFDKRJV4FM7QXCHY2ZUPRDEZKV")
    }

    func testStellarTransactionPaymentEncodesBridgePayload() throws {
        let transaction = StellarTransaction(
            to: "GDESTINATION1234567890",
            amount: "10.5",
            memo: .text("hello"),
            networkPassphrase: StellarNetwork.testnetPassphrase,
            fee: "100",
            timeout: 60,
            sequenceNumber: "12345"
        )

        let payload = try encodedPayload(transaction)

        XCTAssertEqual(payload["chainType"] as? String, "STELLAR")
        XCTAssertEqual(payload["to"] as? String, "GDESTINATION1234567890")
        XCTAssertEqual(payload["amount"] as? String, "10.5")
        XCTAssertEqual(payload["networkPassphrase"] as? String, StellarNetwork.testnetPassphrase)
        XCTAssertEqual(payload["fee"] as? String, "100")
        XCTAssertEqual(payload["timeout"] as? Int, 60)
        XCTAssertEqual(payload["sequenceNumber"] as? String, "12345")

        let memo = try XCTUnwrap(payload["memo"] as? [String: Any])
        XCTAssertEqual(memo["type"] as? String, "text")
        XCTAssertEqual(memo["value"] as? String, "hello")
    }

    func testStellarTransactionSerializedXDREncodesBridgePayload() throws {
        let transaction = StellarTransaction(
            serializedXDR: "AAAAAgAAA...",
            networkPassphrase: StellarNetwork.publicPassphrase
        )

        let payload = try encodedPayload(transaction)

        XCTAssertEqual(payload["chainType"] as? String, "STELLAR")
        XCTAssertEqual(payload["type"] as? String, "serialized")
        XCTAssertEqual(payload["data"] as? String, "AAAAAgAAA...")
        XCTAssertEqual(payload["networkPassphrase"] as? String, StellarNetwork.publicPassphrase)
    }

    func testDerivesStellarAddressFromHexPublicKey() throws {
        let publicKeyHex = "da4f143ecf1e3e0d6780c0965cb950aee498e51aa29af0acfc2e23e359a3e232"

        let address = try StellarAddress.fromPublicKey(publicKeyHex)

        XCTAssertEqual(address, "GDNE6FB6Z4PD4DLHQDAJMXFZKCXOJGHFDKRJV4FM7QXCHY2ZUPRDEZKV")
    }

    func testDerivesStellarAddressFromSolanaAddress() throws {
        let solanaAddress = "FhBpLCxutevuuZ8bnQMLSvQ6Z9tLXr6vZP5DLSbbDpGq"

        let address = try StellarAddress.fromSolanaAddress(solanaAddress)

        XCTAssertEqual(address, "GDNE6FB6Z4PD4DLHQDAJMXFZKCXOJGHFDKRJV4FM7QXCHY2ZUPRDEZKV")
    }

    private func encodedPayload<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
