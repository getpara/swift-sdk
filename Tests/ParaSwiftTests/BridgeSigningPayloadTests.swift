import BigInt
@testable import ParaSwift
import XCTest

final class BridgeSigningPayloadTests: XCTestCase {
    func testWalletTypeDecodesSui() {
        let wallet = Wallet(result: [
            "id": "sui-wallet",
            "type": "SUI",
            "address": "0x1234",
        ])

        XCTAssertEqual(wallet.type, .sui)
    }

    func testTypedDataEncodesCanonicalBridgePayload() throws {
        let payload = EVMTypedDataMessage(
            domain: ["name": .string("Para"), "chainId": .integer(1)],
            types: ["Mail": [EVMTypedDataField(name: "contents", type: "string")]],
            primaryType: "Mail",
            message: ["contents": .string("Hello")],
        )

        let encoded = try encodedPayload(payload)
        guard case let .object(data) = encoded["data"] else {
            return XCTFail("Expected typed-data payload")
        }
        guard case let .object(domain) = data["domain"] else {
            return XCTFail("Expected typed-data domain")
        }

        XCTAssertNil(encoded["chainType"])
        XCTAssertEqual(encoded["type"], .string("typedData"))
        XCTAssertEqual(data["primaryType"], .string("Mail"))
        XCTAssertEqual(domain["chainId"], .integer(1))
    }

    func testSerializedTransactionsEncodeChainAndSignMode() throws {
        let solana = try encodedPayload(SerializedTransaction.solana("solana-bytes"))
        XCTAssertEqual(solana["type"], .string("serialized"))
        XCTAssertEqual(solana["chainType"], .string("SOLANA"))
        XCTAssertEqual(solana["data"], .string("solana-bytes"))

        let cosmos = try encodedPayload(SerializedTransaction.cosmos("sign-doc", signMode: .direct))
        XCTAssertEqual(cosmos["chainType"], .string("COSMOS"))
        XCTAssertEqual(cosmos["format"], .string("proto"))

        let sui = try encodedPayload(SerializedTransaction.sui("sui-bcs"))
        XCTAssertEqual(sui["chainType"], .string("SUI"))
        XCTAssertEqual(sui["data"], .string("sui-bcs"))
    }

    func testEVMTransactionEncodesTypeThreeAndTypeFourFields() throws {
        let authorization = EVMSignedAuthorization(
            address: "0x0000000000000000000000000000000000000770",
            chainId: 1,
            nonce: 7,
            yParity: 0,
            r: "0x11",
            s: "0x22",
        )
        let transaction = EVMTransaction(
            chainId: BigUInt(1),
            accessList: [EVMAccessListEntry(address: "0x1234", storageKeys: ["0xabcd"])],
            maxFeePerBlobGas: BigUInt(12),
            blobVersionedHashes: ["0x0100"],
            authorizationList: [authorization],
            type: 4,
        )

        let encoded = try encodedPayload(transaction)

        XCTAssertEqual(encoded["chainId"], .string("0x1"))
        XCTAssertEqual(encoded["maxFeePerBlobGas"], .string("0xc"))
        XCTAssertEqual(encoded["blobVersionedHashes"], .array([.string("0x0100")]))
        guard case let .array(authorizations) = encoded["authorizationList"],
              case let .object(authorizationPayload) = authorizations.first
        else {
            return XCTFail("Expected EIP-7702 authorization list")
        }
        XCTAssertEqual(authorizationPayload["nonce"], .integer(7))
        XCTAssertEqual(encoded["type"], .integer(4))
    }

    func testSuiSignatureMetadataRemainsAvailable() {
        let result = SignatureResult(
            signedTransaction: "sui-bcs",
            walletId: "wallet-id",
            type: "SUI",
            signature: "serialized-signature",
            bytes: "sui-bcs",
        )

        XCTAssertEqual(result.transactionData, "sui-bcs")
        XCTAssertEqual(result.signature, "serialized-signature")
        XCTAssertEqual(result.bytes, "sui-bcs")
    }

    private func encodedPayload(_ value: some Encodable) throws -> [String: BridgeJSONValue] {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(BridgeJSONValue.self, from: data)
        guard case let .object(payload) = decoded else {
            throw EncodingError.invalidValue(
                decoded,
                EncodingError.Context(codingPath: [], debugDescription: "Expected encoded object")
            )
        }
        return payload
    }
}
