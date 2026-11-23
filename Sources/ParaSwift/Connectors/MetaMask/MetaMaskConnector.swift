// swiftformat:disable:redundantSelf

//
//  MetaMaskConnector.swift
//  ParaSwift
//
//  Created by Tyson Williams on 2/8/25.
//

import BigInt
import Foundation
import os
import UIKit

/// Main connector class for interacting with MetaMask
public class MetaMaskConnector: ObservableObject {
    private let logger = Logger(subsystem: "com.paraSwift", category: "MetaMaskConnector")

    /// Shared instance for deep link handling
    private static var activeInstance: MetaMaskConnector?

    // MARK: - Properties

    private let para: ParaManager
    private let appUrl: String
    private let config: MetaMaskConfig
    private let channelId = UUID().uuidString

    /// Whether MetaMask is currently connected
    @Published public private(set) var isConnected = false
    /// Connected MetaMask accounts
    @Published public private(set) var accounts: [String] = []
    /// Current chain ID (e.g., "0x1" for Ethereum mainnet)
    @Published public private(set) var chainId: String?

    private var currentMessageType: MetaMaskMessageType?
    /// JSON-RPC id of the pending sign or send request. Any app can open `<appScheme>://mmsdk`, so a reply only
    /// counts when it echoes this id, which MetaMask does for the request it answers.
    private var pendingRequestId: String?
    /// The pending `personal_sign` request, kept so the returned signature can be checked against its account.
    private var pendingSignRequest: (message: String, account: String)?
    /// Opens a MetaMask URL. Tests replace it; nil uses `UIApplication`.
    var urlOpener: ((URL) throws -> Void)?
    private lazy var originatorInfo: OriginatorInfo = .init(url: appUrl, apiVersion: config.apiVersion, platform: "ios", title: config.appName, dappId: config.appId)

    // MARK: - Continuation Management

    private var continuation: Any? {
        didSet {
            guard continuation == nil else { return }
            currentMessageType = nil
            pendingRequestId = nil
            pendingSignRequest = nil
        }
    }

    private func withContinuation<T>(type: MetaMaskMessageType, _ body: (CheckedContinuation<T, Error>) throws -> Void) async throws -> T {
        guard currentMessageType == nil else {
            logger.error("Already processing message of type: \(String(describing: self.currentMessageType))")
            throw MetaMaskError.alreadyProcessing
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.currentMessageType = type
            do {
                try body(cont)
            } catch {
                self.continuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func complete<T>(with result: T) {
        logger.debug("Operation completed successfully.")
        guard let continuation = continuation as? CheckedContinuation<T, Error> else { return }
        self.continuation = nil
        continuation.resume(returning: result)

        // Clear active instance after successful operation
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
    }

    private func complete(with error: Error) {
        logger.error("Operation completed with error: \(error.localizedDescription)")
        guard let continuation else { return }
        self.continuation = nil

        switch continuation {
        case let cont as CheckedContinuation<Void, Error>:
            cont.resume(throwing: error)
        case let cont as CheckedContinuation<String, Error>:
            cont.resume(throwing: error)
        default:
            break
        }

        // Clear active instance after error
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
    }

    // MARK: - Initialization

    /// Initialize a new MetaMask connector
    /// - Parameters:
    ///   - para: The Para manager instance
    ///   - appUrl: Your application's URL
    ///   - config: MetaMask configuration
    public init(para: ParaManager, appUrl: String, config: MetaMaskConfig) {
        self.para = para
        self.appUrl = appUrl
        self.config = config
        logger.debug("Initialized MetaMaskConnector with appUrl: \(appUrl) and appScheme: \(para.appScheme)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Deep Link Handling

    /// Static method to handle deep link URLs from MetaMask
    /// - Parameter url: The URL to handle
    /// - Returns: Whether the URL was handled successfully
    @discardableResult
    public static func handleDeepLink(_ url: URL) -> Bool {
        guard let instance = activeInstance else {
            return false
        }
        return instance.handleURL(url)
    }

    /// Handles deep link URLs from MetaMask
    /// - Parameter url: The URL to handle
    /// - Returns: Whether the URL was handled successfully
    @discardableResult
    public func handleURL(_ url: URL) -> Bool {
        guard url.host == "mmsdk" else {
            logger.debug("Received deep link with invalid URL: \(url)")
            return false
        }

        logger.debug("Handling deep link: \(url.absoluteString)")
        do {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let messageParam = components.queryItems?.first(where: { $0.name == "message" })?.value,
                  let messageData = Data(base64Encoded: messageParam)
            else {
                logger.error("Deep link is missing required parameters.")
                if currentMessageType == .signMessage || currentMessageType == .sendTransaction {
                    // It cannot be matched to the pending request, so it must not cancel it either.
                    return false
                }
                throw MetaMaskError.invalidResponse
            }

            switch currentMessageType {
            case .connect:
                let response = try JSONDecoder().decode(ConnectResponse.self, from: messageData)
                logger.debug("Decoded connect response: chainId=\(response.data.chainId), accounts=\(response.data.accounts)")
                handleConnectResult(response)
            case .signMessage, .sendTransaction:
                guard let header = try? JSONDecoder().decode(MetaMaskReplyHeader.self, from: messageData),
                      isReplyToPendingRequest(header)
                else {
                    logger.debug("Ignoring deep link that does not answer the pending request.")
                    return false
                }
                let response = try JSONDecoder().decode(MetaMaskResponse<String>.self, from: messageData)
                logger.debug("Decoded signMessage/transaction response successfully.")
                handleResponse(response)
            case .none:
                logger.debug("No active message type for deep link handling.")
            }
            return true
        } catch {
            logger.error("Error handling deep link: \(error.localizedDescription)")
            complete(with: MetaMaskError.invalidResponse)
            return false
        }
    }

    /// Whether a reply answers the pending sign or send request. MetaMask echoes the request id as `data.id`.
    /// A reply with another id, or with none, is not the answer and is ignored. The one exception is an error
    /// without an id, which MetaMask sends when it cannot read a request; accepting it only cancels the request.
    private func isReplyToPendingRequest(_ header: MetaMaskReplyHeader) -> Bool {
        guard let pendingRequestId else { return false }
        guard let replyId = header.data.id else {
            return header.data.hasError && !header.data.hasResult
        }
        return replyId == pendingRequestId
    }

    private func handleResponse<T>(_ response: MetaMaskResponse<T>) {
        if let error = response.data.error {
            complete(with: MetaMaskError.metaMaskError(code: error.code, message: error.message))
            return
        }

        guard let result = response.data.result else {
            complete(with: MetaMaskError.invalidResponse)
            return
        }

        switch (currentMessageType, result) {
        case let (.connect, connectResponse as ConnectResponse):
            handleConnectResult(connectResponse)
        case let (.signMessage, signature as String):
            guard let request = pendingSignRequest,
                  PersonalSignVerifier.isValid(signature: signature, message: request.message, account: request.account)
            else {
                logger.error("Signature does not match the requested account.")
                complete(with: MetaMaskError.invalidResponse)
                return
            }
            complete(with: signature as! T)
        case let (.sendTransaction, txHash as String):
            complete(with: txHash as! T)
        default:
            complete(with: MetaMaskError.invalidResponse)
        }
    }

    private func handleConnectResult(_ response: ConnectResponse) {
        logger.debug("Handling connect result: chainId=\(response.data.chainId), accounts=\(response.data.accounts)")
        guard let account = response.data.accounts.first, PersonalSignVerifier.isAddress(account) else {
            logger.error("No valid address found in connect response")
            complete(with: MetaMaskError.invalidResponse)
            return
        }

        chainId = response.data.chainId
        accounts = response.data.accounts
        isConnected = true

        Task {
            do {
                guard let address = accounts.first, !address.isEmpty else {
                    logger.error("No valid address found in connect response")
                    complete(with: MetaMaskError.invalidResponse)
                    return
                }

                logger.debug("Attempting external wallet login: address=\(address)")
                try await para.loginExternalWallet(wallet: ExternalWalletInfo(
                    address: address,
                    type: .evm,
                    provider: "metamask",
                ))
                logger.debug("External wallet login completed")
                complete(with: ())
            } catch {
                logger.error("External wallet login failed: \(error.localizedDescription)")
                complete(with: error)
            }
        }
    }

    // MARK: - Public Methods

    /// Initiates a connection request to MetaMask.
    public func connect() async throws {
        logger.debug("Initiating MetaMask connection")
        // Set this as the active instance for deep link handling
        Self.activeInstance = self

        try await withContinuation(type: .connect) { (_: CheckedContinuation<Void, Error>) in
            do {
                let originatorData = try originatorInfo.encode()
                let url = try makeMetaMaskURL(host: "connect", originatorInfo: originatorData)
                logger.debug("Opening MetaMask URL: \(url.absoluteString)")
                try self.openMetaMaskURL(url)
            } catch {
                logger.error("Failed to construct connect URL: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Initiates a personal sign request.
    /// - Parameters:
    ///   - message: The message to sign
    ///   - account: The account to sign with
    /// - Returns: The signature
    public func signMessage(_ message: String, account: String) async throws -> String {
        logger.debug("Initiating signMessage for account: \(account)")
        // Set this as the active instance for deep link handling
        Self.activeInstance = self

        let requestId = Self.makeRequestId()
        let request = SignMessageRequest(id: requestId, params: [message, account])
        let encodedMessage = try request.encode()

        return try await withContinuation(type: .signMessage) { (_: CheckedContinuation<String, Error>) in
            self.pendingRequestId = requestId
            self.pendingSignRequest = (message, account)
            do {
                let url = try makeMetaMaskURL(host: "mmsdk", message: encodedMessage, account: "\(account)@\(chainId ?? "")")
                logger.debug("SignMessage URL: \(url.absoluteString)")
                try self.openMetaMaskURL(url)
            } catch {
                logger.error("Error constructing signMessage URL: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Internal implementation for sending transactions.
    /// This method handles the low-level communication with MetaMask.
    /// For general usage, prefer the EVMTransaction-based overload.
    /// - Parameters:
    ///   - transaction: The transaction details in MetaMask's expected format
    ///   - account: The account to send from
    /// - Returns: The transaction hash
    func sendTransaction(_ transaction: [String: String], account: String) async throws -> String {
        logger.debug("Initiating sendTransaction for account: \(account)")
        // Set this as the active instance for deep link handling
        Self.activeInstance = self

        let requestId = Self.makeRequestId()
        let request = SendTransactionRequest(id: requestId, params: [transaction])
        let encodedMessage = try request.encode()

        return try await withContinuation(type: .sendTransaction) { (_: CheckedContinuation<String, Error>) in
            self.pendingRequestId = requestId
            do {
                let url = try makeMetaMaskURL(host: "mmsdk", message: encodedMessage, account: "\(account)@\(chainId ?? "")")
                logger.debug("SendTransaction URL: \(url.absoluteString)")
                try self.openMetaMaskURL(url)
            } catch {
                logger.error("Error constructing sendTransaction URL: \(error.localizedDescription)")
                throw error
            }
        }
    }

    /// Initiates a transaction request using an EVMTransaction.
    /// This is the recommended method for sending transactions.
    /// - Parameters:
    ///   - transaction: The EVMTransaction object containing the transaction details
    ///   - account: The account to send from
    /// - Returns: The transaction hash
    public func sendTransaction(_ transaction: EVMTransaction, account: String) async throws -> String {
        let metaMaskTx = transaction.toMetaMaskFormat(from: account)
        return try await sendTransaction(metaMaskTx, account: account)
    }
}

// MARK: - URL Construction

private extension MetaMaskConnector {
    /// A fresh, unguessable JSON-RPC id. No underscore: MetaMask treats ids containing `_` as parts of a batch
    /// and does not send those replies back over the deep link.
    static func makeRequestId() -> String {
        UUID().uuidString
    }

    private func openMetaMaskURL(_ url: URL) throws {
        if let urlOpener {
            try urlOpener(url)
            return
        }
        if !UIApplication.shared.canOpenURL(url) {
            logger.debug("MetaMask is not installed. Opening App Store...")
            let appStoreURL = URL(string: "https://apps.apple.com/us/app/metamask-blockchain-wallet/id1438144202")!
            DispatchQueue.main.async {
                UIApplication.shared.open(appStoreURL)
            }
            throw MetaMaskError.notInstalled
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    /// Constructs a URL for MetaMask communication
    func makeMetaMaskURL(
        host: String,
        message: String? = nil,
        account: String? = nil,
        originatorInfo: String? = nil
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "metamask"
        components.host = host

        var queryItems = [
            URLQueryItem(name: "scheme", value: para.appScheme),
            URLQueryItem(name: "channelId", value: channelId),
        ]

        if let message {
            queryItems.append(URLQueryItem(name: "message", value: message))
        }
        if let account {
            queryItems.append(URLQueryItem(name: "account", value: account))
        }
        if let originatorInfo {
            queryItems.append(URLQueryItem(name: "comm", value: "deeplinking"))
            queryItems.append(URLQueryItem(name: "originatorInfo", value: originatorInfo))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw MetaMaskError.invalidURL
        }
        return url
    }
}

// MARK: - EVMTransaction Extension

extension EVMTransaction {
    /// Converts the transaction to MetaMask format
    /// - Parameter from: The sender address
    /// - Returns: Transaction in MetaMask format
    func toMetaMaskFormat(from: String) -> [String: String] {
        var tx: [String: String] = ["from": from]

        // Helper function to convert BigUInt to hex string
        func toHexString(_ value: BigUInt?) -> String? {
            value.map { "0x" + String($0, radix: 16) }
        }

        if let to { tx["to"] = to }
        if let value = toHexString(value) { tx["value"] = value }
        if let gasLimit = toHexString(gasLimit) { tx["gas"] = gasLimit }
        if let gasPrice = toHexString(gasPrice) { tx["gasPrice"] = gasPrice }
        if let maxPriorityFeePerGas = toHexString(maxPriorityFeePerGas) { tx["maxPriorityFeePerGas"] = maxPriorityFeePerGas }
        if let maxFeePerGas = toHexString(maxFeePerGas) { tx["maxFeePerGas"] = maxFeePerGas }
        // Note: Nonce is intentionally excluded to let MetaMask handle it automatically
        // This prevents "nonce too low" errors when the external wallet has transaction history
        if let type { tx["type"] = "0x" + String(type, radix: 16) }
        if let chainId = toHexString(chainId) { tx["chainId"] = chainId }

        return tx
    }
}
