@testable import ParaSwift
import XCTest

final class PersonalSignVerifierTests: XCTestCase {
    // Signatures made with well-known test keys (0x11…11 and 0x22…22), produced with viem.
    private let account = "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"
    private let otherAccount = "0x1563915e194D8CfBA1943570603F7606A3115508"
    private let message = "Approve login to host"
    private let signature = "0x11106abec82a4614ca8221d5e50560f55cbaaa85361cfeac872fc0b3e0f4d478001dbd39db6a2a0bd941be258af5fcea92a16109db2b504b73d636808cd542371b"
    private let otherSignature = "0x7e327f37648abf55af8c1dbd242c9a485306dd57d3b451f1764ee9c5e56aef5b38468ad6ec86e2bce361be399577eb7cd6559b3661da839a9ba4b6c659bf57561b"

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func testKeccak256MatchesKnownDigests() {
        XCTAssertEqual(hex(Keccak256.hash(Data())), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        XCTAssertEqual(hex(Keccak256.hash(Data("abc".utf8))), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // Longer than one 136-byte block.
        XCTAssertEqual(
            hex(Keccak256.hash(Data(repeating: 0x61, count: 200))),
            "96ea54061def936c4be90b518992fdc6f12f535068a256229aca54267b4d084d"
        )
    }

    func testRecoversTheSigningAccount() {
        XCTAssertEqual(
            PersonalSignVerifier.recoverSigner(payload: Data(message.utf8), signature: signature).map(hex),
            String(account.dropFirst(2)).lowercased()
        )
        XCTAssertEqual(
            PersonalSignVerifier.recoverSigner(payload: Data(message.utf8), signature: otherSignature).map(hex),
            String(otherAccount.dropFirst(2)).lowercased()
        )
    }

    func testAcceptsOnlyTheRequestedAccountAndMessage() {
        XCTAssertTrue(PersonalSignVerifier.isValid(signature: signature, message: message, account: account))
        XCTAssertTrue(PersonalSignVerifier.isValid(signature: signature, message: message, account: account.lowercased()))
        XCTAssertFalse(PersonalSignVerifier.isValid(signature: otherSignature, message: message, account: account))
        XCTAssertFalse(PersonalSignVerifier.isValid(signature: signature, message: message + "!", account: account))
        XCTAssertFalse(PersonalSignVerifier.isValid(signature: signature, message: message, account: otherAccount))
    }

    func testAcceptsARecoveryIdOfZeroOrOne() {
        let normalized = String(signature.dropLast(2)) + "00"
        XCTAssertTrue(PersonalSignVerifier.isValid(signature: normalized, message: message, account: account))
    }

    func testRejectsMalformedInput() {
        let zeros = "0x" + String(repeating: "00", count: 64) + "1b"
        for bad in ["", "0x", "not-hex", String(signature.dropLast(2)), signature + "00", String(signature.dropLast(2)) + "02", zeros] {
            XCTAssertFalse(PersonalSignVerifier.isValid(signature: bad, message: message, account: account), bad)
        }
        XCTAssertFalse(PersonalSignVerifier.isValid(signature: signature, message: message, account: "0x1234"))
        XCTAssertFalse(PersonalSignVerifier.isAddress("19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"))
        XCTAssertTrue(PersonalSignVerifier.isAddress(account))
    }

    func testVerificationIsFastEnoughForTheMainThread() {
        let started = Date()
        XCTAssertTrue(PersonalSignVerifier.isValid(signature: signature, message: message, account: account))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }
}
