@testable import ParaSwift
import XCTest

/// A MetaMask reply only counts when it answers the pending request, and a `personal_sign` result must come from
/// the requested account.
@MainActor
final class MetaMaskCallbackTests: XCTestCase {
    // Signatures made with well-known test keys (0x11…11 and 0x22…22), produced with viem.
    private let account = "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"
    private let message = "Approve login to host"
    private let signature = "0x11106abec82a4614ca8221d5e50560f55cbaaa85361cfeac872fc0b3e0f4d478001dbd39db6a2a0bd941be258af5fcea92a16109db2b504b73d636808cd542371b"
    private let otherKeySignature = "0x7e327f37648abf55af8c1dbd242c9a485306dd57d3b451f1764ee9c5e56aef5b38468ad6ec86e2bce361be399577eb7cd6559b3661da839a9ba4b6c659bf57561b"
    private let rawBytesMessage = "0xdeadbeef"
    private let rawBytesSignature = "0x0a4ee10cbf4152a3270bb891f40a779f380dfe9e16436abb06ea67d9810a1b672c574216577cd2ee9e42908e48649452457ae675e4b3dacda70c720ed03bb8311c"

    private var connector: MetaMaskConnector!
    private var opened: [URL] = []

    override func setUp() async throws {
        let para = ParaManager(
            environment: .dev(relyingPartyId: "test", jsBridgeUrl: URL(string: "about:blank")),
            apiKey: "test",
            appScheme: "myapp"
        )
        connector = MetaMaskConnector(
            para: para,
            appUrl: "https://host.example",
            config: MetaMaskConfig(appName: "Host", appId: "com.host")
        )
        opened = []
        connector.urlOpener = { [weak self] url in self?.opened.append(url) }
    }

    // MARK: - Helpers

    private func reply(_ data: [String: Any]) throws -> URL {
        let json = try JSONSerialization.data(withJSONObject: ["data": data])
        var components = URLComponents()
        components.scheme = "myapp"
        components.host = "mmsdk"
        components.queryItems = [URLQueryItem(name: "message", value: json.base64EncodedString())]
        return try XCTUnwrap(components.url)
    }

    /// The JSON-RPC request in the last URL the connector opened.
    private func lastRequest() throws -> [String: Any] {
        let url = try XCTUnwrap(opened.last)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let encoded = try XCTUnwrap(items?.first { $0.name == "message" }?.value)
        let data = try XCTUnwrap(Data(base64Encoded: encoded))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func lastRequestId() throws -> String {
        try XCTUnwrap(lastRequest()["id"] as? String, "The request carries no JSON-RPC id")
    }

    /// Starts a request and waits until the connector has opened MetaMask.
    private func start(_ operation: @escaping @MainActor (MetaMaskConnector) async throws -> String) async throws -> Task<String, Error> {
        let connector = try XCTUnwrap(connector)
        let alreadyOpened = opened.count
        let task = Task { try await operation(connector) }
        for _ in 0 ..< 200 where opened.count == alreadyOpened {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(opened.count, alreadyOpened + 1, "The connector did not open MetaMask")
        return task
    }

    private func startSign(_ text: String? = nil) async throws -> Task<String, Error> {
        let text = text ?? message
        let account = account
        return try await start { try await $0.signMessage(text, account: account) }
    }

    private func startSend() async throws -> Task<String, Error> {
        let account = account
        return try await start { try await $0.sendTransaction(["to": account, "value": "0x1"], account: account) }
    }

    /// Whether `task` is still waiting after a short pause.
    private func isPending(_ task: Task<String, Error>) async throws -> Bool {
        let finished = Finished()
        Task {
            _ = await task.result
            await finished.set()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        return await !finished.value
    }

    private func assertInvalidResponse(_ task: Task<String, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let value = try await task.value
            XCTFail("Expected the request to fail, got \(value)", file: file, line: line)
        } catch MetaMaskError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: - signMessage

    func testEachRequestCarriesAFreshId() async throws {
        let first = try await startSign()
        let firstId = try lastRequestId()
        XCTAssertFalse(firstId.contains("_"))
        XCTAssertEqual(try lastRequest()["method"] as? String, "personal_sign")

        XCTAssertTrue(connector.handleURL(try reply(["id": firstId, "result": signature])))
        _ = try await first.value

        let second = try await startSign()
        XCTAssertNotEqual(try lastRequestId(), firstId)
        second.cancel()
    }

    func testSignIgnoresAReplyWithoutTheRequestId() async throws {
        let task = try await startSign()

        XCTAssertFalse(connector.handleURL(try reply(["result": otherKeySignature])))
        let stillPending = try await isPending(task)
        XCTAssertTrue(stillPending, "A reply without the request id must not complete the request")

        // The genuine reply still completes it.
        XCTAssertTrue(connector.handleURL(try reply(["id": try lastRequestId(), "result": signature])))
        let value = try await task.value
        XCTAssertEqual(value, signature)
    }

    func testSignIgnoresAReplyWithAnotherRequestId() async throws {
        let task = try await startSign()

        XCTAssertFalse(connector.handleURL(try reply(["id": "another-request", "result": signature])))
        XCTAssertFalse(connector.handleURL(try reply(["id": 7, "result": signature])))
        let stillPending = try await isPending(task)
        XCTAssertTrue(stillPending, "A reply with another request id must not complete the request")
        task.cancel()
    }

    func testSignIgnoresALinkWithoutAMessage() async throws {
        let task = try await startSign()

        XCTAssertFalse(connector.handleURL(try XCTUnwrap(URL(string: "myapp://mmsdk"))))
        XCTAssertFalse(connector.handleURL(try XCTUnwrap(URL(string: "myapp://mmsdk?message=not-base64"))))
        let stillPending = try await isPending(task)
        XCTAssertTrue(stillPending, "A link that cannot be matched must not cancel the request")
        task.cancel()
    }

    func testSignRejectsASignatureFromAnotherAccount() async throws {
        let task = try await startSign()

        connector.handleURL(try reply(["id": try lastRequestId(), "result": otherKeySignature]))
        await assertInvalidResponse(task)
    }

    func testSignCompletesOnceWithTheGenuineReply() async throws {
        let task = try await startSign()
        let id = try lastRequestId()
        let genuine = try reply(["id": id, "result": signature, "chainId": "0x1", "accounts": [account]])

        XCTAssertTrue(connector.handleURL(genuine))
        let value = try await task.value
        XCTAssertEqual(value, signature)

        // A replay has nothing left to complete and does not answer the next request.
        connector.handleURL(genuine)
        let next = try await startSign()
        connector.handleURL(genuine)
        let stillPending = try await isPending(next)
        XCTAssertTrue(stillPending, "A replayed reply must not complete a later request")
        next.cancel()
    }

    func testSignAcceptsAHexMessageSignedAsRawBytes() async throws {
        let task = try await startSign(rawBytesMessage)

        connector.handleURL(try reply(["id": try lastRequestId(), "result": rawBytesSignature]))
        let value = try await task.value
        XCTAssertEqual(value, rawBytesSignature)
    }

    func testAMetaMaskErrorFailsTheRequestAndFreesTheConnector() async throws {
        let task = try await startSign()

        // MetaMask sends an error without an id when it cannot read a request.
        connector.handleURL(try reply(["error": ["code": 4001, "message": "User rejected the request."]]))
        do {
            _ = try await task.value
            XCTFail("Expected the request to fail")
        } catch let error as MetaMaskError {
            XCTAssertTrue(error.isUserRejected)
        }

        let next = try await startSign()
        connector.handleURL(try reply(["id": try lastRequestId(), "result": signature]))
        let value = try await next.value
        XCTAssertEqual(value, signature)
    }

    // MARK: - sendTransaction

    func testSendIgnoresAReplyThatDoesNotAnswerTheRequest() async throws {
        let task = try await startSend()
        let hash = "0x" + String(repeating: "ab", count: 32)
        XCTAssertEqual(try lastRequest()["method"] as? String, "eth_sendTransaction")

        XCTAssertFalse(connector.handleURL(try reply(["result": "0x" + String(repeating: "00", count: 32)])))
        XCTAssertFalse(connector.handleURL(try reply(["id": "another-request", "result": hash])))
        let stillPending = try await isPending(task)
        XCTAssertTrue(stillPending, "A reply that does not answer the request must not complete it")

        XCTAssertTrue(connector.handleURL(try reply(["id": try lastRequestId(), "result": hash])))
        let value = try await task.value
        XCTAssertEqual(value, hash)
    }

    func testSendFailsWhenTheMatchingReplyHasNoHash() async throws {
        let task = try await startSend()

        connector.handleURL(try reply(["id": try lastRequestId(), "result": ["unexpected": true]]))
        await assertInvalidResponse(task)
    }

    // MARK: - connect

    func testConnectRejectsAReplyWithoutAValidAccount() async throws {
        let connector = try XCTUnwrap(connector)
        let task = Task { try await connector.connect() }
        for _ in 0 ..< 200 where opened.isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(opened.count, 1)

        connector.handleURL(try reply(["chainId": "0x1", "accounts": ["not-an-address"]]))
        do {
            try await task.value
            XCTFail("Expected connect to fail")
        } catch MetaMaskError.invalidResponse {
            // expected
        }
        XCTAssertFalse(connector.isConnected)
        XCTAssertTrue(connector.accounts.isEmpty)
    }
}

private actor Finished {
    private(set) var value = false
    func set() { value = true }
}
