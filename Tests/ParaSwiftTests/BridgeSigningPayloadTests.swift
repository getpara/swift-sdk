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

    func testChainBasedWalletCreationIsAdditiveToTheExistingMethod() {
        let contract: (ParaManager) async throws -> Void = Self.acceptsLegacyAndChainWalletCreation

        XCTAssertNotNil(contract as Any)
    }

    func testSuiDecodesWithoutWideningTheExistingWalletTypeEnum() {
        XCTAssertEqual(existingWalletTypeDescription(.evm), "EVM")
        XCTAssertEqual(existingWalletTypeDescription(.solana), "SOLANA")
        XCTAssertEqual(existingWalletTypeDescription(.cosmos), "COSMOS")
        XCTAssertEqual(existingWalletTypeDescription(.stellar), "STELLAR")

        let suiAddress = "0x1111111111111111111111111111111111111111111111111111111111111111"
        let wallet = Wallet(result: [
            "id": "sui-wallet",
            "type": "SUI",
            "address": "11111111111111111111111111111111",
            "addressSui": suiAddress,
        ])

        XCTAssertNil(wallet.type)
        XCTAssertEqual(wallet.chainType, .sui)
        XCTAssertEqual(wallet.addressSui, suiAddress)
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

    func testChainSpecificMessagesEncodeCanonicalBridgePayloads() throws {
        XCTAssertEqual(
            try encodedPayload(EVMAuthorizationMessage(
                address: "0x0000000000000000000000000000000000007702",
                chainId: 11_155_111,
                nonce: 7,
            )),
            [
                "type": .string("authorization"),
                "data": .object([
                    "address": .string("0x0000000000000000000000000000000000007702"),
                    "chainId": .integer(11_155_111),
                    "nonce": .integer(7),
                ]),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(StellarAuthEntryMessage(data: "stellar-auth-xdr")),
            [
                "type": .string("authEntry"),
                "data": .string("stellar-auth-xdr"),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(SuiPersonalMessage(data: "sui-message-bytes")),
            [
                "type": .string("suiPersonalMessage"),
                "data": .string("sui-message-bytes"),
            ],
        )
    }

    func testSerializedTransactionsEncodeChainAndSignMode() throws {
        XCTAssertEqual(
            try encodedPayload(SerializedTransaction.solana("solana-bytes")),
            [
                "type": .string("serialized"),
                "chainType": .string("SOLANA"),
                "data": .string("solana-bytes"),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(SerializedTransaction.cosmos("sign-doc", signMode: .direct)),
            [
                "type": .string("serialized"),
                "chainType": .string("COSMOS"),
                "data": .string("sign-doc"),
                "format": .string("proto"),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(SerializedTransaction.cosmos("amino-sign-doc", signMode: .amino)),
            [
                "type": .string("serialized"),
                "chainType": .string("COSMOS"),
                "data": .string("amino-sign-doc"),
                "format": .string("amino"),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(SerializedTransaction.stellar(
                "stellar-envelope-xdr",
                networkPassphrase: StellarNetwork.testnetPassphrase,
            )),
            [
                "type": .string("serialized"),
                "chainType": .string("STELLAR"),
                "data": .string("stellar-envelope-xdr"),
                "networkPassphrase": .string(StellarNetwork.testnetPassphrase),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(SerializedTransaction.sui("sui-bcs")),
            [
                "type": .string("serialized"),
                "chainType": .string("SUI"),
                "data": .string("sui-bcs"),
            ],
        )
    }

    func testEVMTransactionTypesZeroThroughTwoEncodeCanonicalKeysAndValues() throws {
        let address = "0x0000000000000000000000000000000000000770"

        XCTAssertEqual(
            try encodedPayload(EVMTransaction(
                to: address,
                value: 0,
                gasLimit: 21000,
                gasPrice: 1_000_000_000,
                nonce: 0,
                chainId: 11_155_111,
                type: 0,
            )),
            [
                "to": .string(address),
                "value": .string("0x0"),
                "gasLimit": .string("0x5208"),
                "gasPrice": .string("0x3b9aca00"),
                "nonce": .string("0x0"),
                "chainId": .string("0xaa36a7"),
                "type": .integer(0),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(EVMTransaction(
                to: address,
                gasLimit: 21000,
                gasPrice: 1_000_000_000,
                chainId: 11_155_111,
                accessList: [EVMAccessListEntry(address: address, storageKeys: [])],
                type: 1,
            )),
            [
                "to": .string(address),
                "gasLimit": .string("0x5208"),
                "gasPrice": .string("0x3b9aca00"),
                "chainId": .string("0xaa36a7"),
                "accessList": .array([
                    .object([
                        "address": .string(address),
                        "storageKeys": .array([]),
                    ]),
                ]),
                "type": .integer(1),
            ],
        )
        XCTAssertEqual(
            try encodedPayload(EVMTransaction(
                to: address,
                gasLimit: 21000,
                maxPriorityFeePerGas: 1_000_000_000,
                maxFeePerGas: 2_000_000_000,
                chainId: 11_155_111,
                type: 2,
            )),
            [
                "to": .string(address),
                "gasLimit": .string("0x5208"),
                "maxPriorityFeePerGas": .string("0x3b9aca00"),
                "maxFeePerGas": .string("0x77359400"),
                "chainId": .string("0xaa36a7"),
                "type": .integer(2),
            ],
        )
    }

    func testEVMTransactionRejectsUnsupportedTypesAndIncompatibleFeeFields() {
        assertEncodingError(EVMTransaction(type: 3), contains: "between 0 and 2")
        assertEncodingError(EVMTransaction(type: 4), contains: "between 0 and 2")
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

    @MainActor
    private static func acceptsLegacyAndChainWalletCreation(manager: ParaManager) async throws {
        try await manager.createWallet(type: .evm, skipDistributable: false)
        try await manager.createWallet(chainType: .sui, skipDistributable: false)
    }
}

private func existingWalletTypeDescription(_ type: WalletType) -> String {
    switch type {
    case .evm: "EVM"
    case .solana: "SOLANA"
    case .cosmos: "COSMOS"
    case .stellar: "STELLAR"
    }
}
