import BigInt
@testable import ParaSwift
import XCTest

final class BridgeSigningPayloadTests: XCTestCase {
    func testExistingSigningMethodsAcceptLegacyAndTypedPayloads() {
        let contract: (
            ParaManager,
            EVMTypedDataMessage,
            EVMAuthorizationMessage,
            EVMTransaction
        ) async throws -> Void = Self.acceptsLegacyAndTypedSigningInputs

        XCTAssertNotNil(contract as Any)
    }

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

    func testTypedDataPreservesLargeIntegerStringsAndRejectsUnsafeNumbers() throws {
        let largeUInt = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        let stringPayload = EVMTypedDataMessage(
            domain: [:],
            types: [:],
            primaryType: "Order",
            message: ["amount": .string(largeUInt)],
        )

        let encoded = try encodedPayload(stringPayload)
        guard case let .object(data) = encoded["data"],
              case let .object(message) = data["message"]
        else {
            return XCTFail("Expected typed-data message")
        }
        XCTAssertEqual(message["amount"], .string(largeUInt))

        assertEncodingError(BridgeJSONValue.integer(9_007_199_254_740_992), contains: "use .string")
        assertEncodingError(BridgeJSONValue.decimal(.infinity), contains: "finite")
        assertEncodingError(BridgeJSONValue.decimal(9_007_199_254_740_992), contains: "use .string")
    }

    func testRawMessagesExposeOnlySolanaAndStellarFactories() throws {
        let solana = RawBridgeMessage.solana("c29sYW5h")
        let stellar = RawBridgeMessage.stellar("c3RlbGxhcg==")

        XCTAssertEqual(solana.chainType, .solana)
        XCTAssertEqual(stellar.chainType, .stellar)
        XCTAssertEqual(
            try encodedPayload(solana),
            [
                "type": .string("raw"),
                "data": .string("c29sYW5h"),
                "encoding": .string("base64"),
            ],
        )
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

    func testEVMTransactionEncodesValidTypeThreeFields() throws {
        let transaction = EVMTransaction(
            maxFeePerGas: BigUInt(10),
            chainId: BigUInt(1),
            accessList: [EVMAccessListEntry(address: "0x1234", storageKeys: ["0xabcd"])],
            maxFeePerBlobGas: BigUInt(12),
            blobVersionedHashes: ["0x0100"],
            type: 3,
        )

        let encoded = try encodedPayload(transaction)

        XCTAssertEqual(encoded["chainId"], BridgeJSONValue.string("0x1"))
        XCTAssertEqual(encoded["maxFeePerGas"], BridgeJSONValue.string("0xa"))
        XCTAssertEqual(encoded["maxFeePerBlobGas"], BridgeJSONValue.string("0xc"))
        XCTAssertEqual(
            encoded["blobVersionedHashes"],
            BridgeJSONValue.array([BridgeJSONValue.string("0x0100")]),
        )
        XCTAssertEqual(encoded["type"], BridgeJSONValue.integer(3))
    }

    func testEVMTransactionEncodesValidTypeFourFields() throws {
        let authorization = EVMSignedAuthorization(
            address: "0x0000000000000000000000000000000000000770",
            chainId: 1,
            nonce: 7,
            yParity: 0,
            r: "0x11",
            s: "0x22",
        )
        let transaction = EVMTransaction(
            maxFeePerGas: BigUInt(10),
            chainId: BigUInt(1),
            accessList: [EVMAccessListEntry(address: "0x1234", storageKeys: ["0xabcd"])],
            authorizationList: [authorization],
            type: 4,
        )

        let encoded = try encodedPayload(transaction)

        XCTAssertEqual(encoded["chainId"], BridgeJSONValue.string("0x1"))
        XCTAssertEqual(encoded["maxFeePerGas"], BridgeJSONValue.string("0xa"))
        guard case let .array(authorizations) = encoded["authorizationList"],
              case let .object(authorizationPayload) = authorizations.first
        else {
            return XCTFail("Expected EIP-7702 authorization list")
        }
        XCTAssertEqual(authorizationPayload["nonce"], BridgeJSONValue.integer(7))
        XCTAssertEqual(encoded["type"], BridgeJSONValue.integer(4))
    }

    func testEVMTransactionRejectsUnsupportedAndIncompatibleFields() {
        assertEncodingError(EVMTransaction(type: 5), contains: "between 0 and 4")
        assertEncodingError(
            EVMTransaction(
                maxFeePerBlobGas: BigUInt(12),
                blobVersionedHashes: ["0x0100"],
                type: 4,
            ),
            contains: "only valid for type 3",
        )
        assertEncodingError(
            EVMTransaction(
                authorizationList: [
                    EVMSignedAuthorization(
                        address: "0x0000000000000000000000000000000000000770",
                        chainId: 1,
                        nonce: 7,
                        yParity: 0,
                        r: "0x11",
                        s: "0x22",
                    ),
                ],
                type: 3,
            ),
            contains: "only valid for type 4",
        )
        assertEncodingError(EVMTransaction(gasPrice: BigUInt(10), type: 2), contains: "cannot include gasPrice")
    }

    func testTypedRoutingRejectsChainMismatchesAndNormalizesEVMChainIds() throws {
        XCTAssertThrowsError(
            try BridgeSigningValidation.resolveChainType(
                payloadChainType: .solana,
                explicitChainType: .evm,
            ),
        )
        XCTAssertEqual(
            try BridgeSigningValidation.resolveChainId(
                chainType: .evm,
                embeddedChainId: "0x1",
                explicitChainId: "1",
            ),
            "1",
        )
        XCTAssertThrowsError(
            try BridgeSigningValidation.resolveChainId(
                chainType: .evm,
                embeddedChainId: "0x1",
                explicitChainId: "2",
            ),
        )
        XCTAssertThrowsError(
            try BridgeSigningValidation.resolveChainId(
                chainType: .cosmos,
                embeddedChainId: "cosmoshub-4",
                explicitChainId: "COSMOSHUB-4",
            ),
        )
    }

    func testTransactionRequestEnvelopePreservesAuthorizationNumbers() throws {
        let transaction = EVMTransaction(
            chainId: BigUInt(1),
            authorizationList: [
                EVMSignedAuthorization(
                    address: "0x0000000000000000000000000000000000000770",
                    chainId: 1,
                    nonce: 0,
                    yParity: 1,
                    r: "0x11",
                    s: "0x22",
                ),
            ],
            type: 4,
        )
        let params = FormatAndSignTransactionParams(
            walletId: "wallet-id",
            transaction: transaction,
            chainId: "1",
            chainType: .evm,
            rpcUrl: nil,
        )

        let envelope = try encodedPayload(params)
        guard case let .object(encodedTransaction) = envelope["transaction"],
              case let .array(authorizations) = encodedTransaction["authorizationList"],
              case let .object(authorization) = authorizations.first
        else {
            return XCTFail("Expected an authorization request envelope")
        }
        XCTAssertEqual(authorization["chainId"], .integer(1))
        XCTAssertEqual(authorization["nonce"], .integer(0))
        XCTAssertEqual(authorization["yParity"], .integer(1))
    }

    func testSolanaLargeNumericsEncodeAsStringsAndDecodeLegacyNumbers() throws {
        let exactValue = UInt64(9_007_199_254_740_993)
        let transaction = try SolanaTransaction(
            to: "11111111111111111111111111111111",
            lamports: exactValue,
            computeUnitPrice: exactValue,
        )

        let encoded = try encodedPayload(transaction)
        XCTAssertEqual(encoded["lamports"], .string("9007199254740993"))
        XCTAssertEqual(encoded["computeUnitPrice"], .string("9007199254740993"))

        let legacy = Data(
            #"{"to":"11111111111111111111111111111111","lamports":42,"computeUnitPrice":7,"type":"transfer"}"#.utf8,
        )
        let decodedLegacy = try JSONDecoder().decode(SolanaTransaction.self, from: legacy)
        XCTAssertEqual(decodedLegacy.lamports, 42)
        XCTAssertEqual(decodedLegacy.computeUnitPrice, 7)

        let decodedStrings = try JSONDecoder().decode(SolanaTransaction.self, from: JSONEncoder().encode(transaction))
        XCTAssertEqual(decodedStrings.lamports, exactValue)
        XCTAssertEqual(decodedStrings.computeUnitPrice, exactValue)
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

    private func assertEncodingError(
        _ value: some Encodable,
        contains expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        XCTAssertThrowsError(try JSONEncoder().encode(value), file: file, line: line) { error in
            guard case let EncodingError.invalidValue(_, context) = error else {
                return XCTFail("Expected EncodingError.invalidValue but received \(error)", file: file, line: line)
            }
            XCTAssertTrue(context.debugDescription.contains(expectedMessage), file: file, line: line)
        }
    }

    private static func acceptsLegacyAndTypedSigningInputs(
        manager: ParaManager,
        message: EVMTypedDataMessage,
        authorization: EVMAuthorizationMessage,
        transaction: EVMTransaction
    ) async throws {
        _ = try await manager.signMessage(walletId: "wallet-id", message: "hello")
        _ = try await manager.signMessage(walletId: "wallet-id", message: message)
        let _: EVMSignedAuthorization = try await manager.signMessage(
            walletId: "wallet-id",
            message: authorization
        )
        _ = try await manager.signTransaction(walletId: "wallet-id", transaction: transaction)
    }
}
