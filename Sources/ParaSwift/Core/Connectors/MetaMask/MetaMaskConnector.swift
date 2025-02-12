//
//  MetaMaskConnector.swift
//  ParaSwift
//
//  Created by Tyson Williams on 2/8/25.
//

import Foundation
import UIKit
import os

/// Main connector class for interacting with MetaMask
@available(iOS 16.4, *)
public class MetaMaskConnector: ObservableObject {
    private let logger = Logger(subsystem: "com.paraSwift", category: "MetaMaskConnector")
    
    // MARK: - Properties
    
    private let para: ParaManager
    private let appUrl: String
    private let deepLink: String
    private let config: MetaMaskConfig
    private let channelId = UUID().uuidString
    
    /// Whether MetaMask is currently connected
    @Published public private(set) var isConnected = false
    /// Connected MetaMask accounts
    @Published public private(set) var accounts: [String] = []
    /// Current chain ID (e.g., "0x1" for Ethereum mainnet)
    @Published public private(set) var chainId: String?
    
    private var currentMessageType: MetaMaskMessageType?
    private lazy var originatorInfo: OriginatorInfo = {
        OriginatorInfo(url: appUrl, apiVersion: config.apiVersion, platform: "ios", title: config.appName, dappId: config.appId)
    }()
    
    // MARK: - Continuation Management
    
    private var continuation: Any? {
        didSet { currentMessageType = continuation != nil ? currentMessageType : nil }
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
    }
    
    private func complete(with error: Error) {
        logger.error("Operation completed with error: \(error.localizedDescription)")
        guard let continuation = continuation else { return }
        self.continuation = nil
        
        switch continuation {
        case let cont as CheckedContinuation<Void, Error>:
            cont.resume(throwing: error)
        case let cont as CheckedContinuation<String, Error>:
            cont.resume(throwing: error)
        default:
            break
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize a new MetaMask connector
    /// - Parameters:
    ///   - para: The Para manager instance
    ///   - appUrl: Your application's URL
    ///   - deepLink: Your application's deep link scheme
    ///   - config: MetaMask configuration
    public init(para: ParaManager, appUrl: String, deepLink: String, config: MetaMaskConfig) {
        self.para = para
        self.appUrl = appUrl
        self.deepLink = deepLink
        self.config = config
        logger.debug("Initialized MetaMaskConnector with appUrl: \(appUrl) and deepLink: \(deepLink)")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Deep Link Handling
    
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
                  let messageData = Data(base64Encoded: messageParam) else {
                logger.error("Deep link is missing required parameters.")
                throw MetaMaskError.invalidResponse
            }
            
            switch currentMessageType {
            case .connect:
                let response = try JSONDecoder().decode(ConnectResponse.self, from: messageData)
                logger.debug("Decoded connect response: chainId=\(response.data.chainId), accounts=\(response.data.accounts)")
                handleConnectResult(response)
            case .signMessage, .sendTransaction:
                let response = try JSONDecoder().decode(MetaMaskResponse<String>.self, from: messageData)
                logger.debug("Decoded signMessage/transaction response successfully.")
                handleResponse(response)
            case .none:
                logger.debug("No active message type for deep link handling.")
                break
            }
            return true
        } catch {
            logger.error("Error handling deep link: \(error.localizedDescription)")
            complete(with: MetaMaskError.invalidResponse)
            return false
        }
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
        case (.connect, let connectResponse as ConnectResponse):
            handleConnectResult(connectResponse)
        case (.signMessage, let signature as String):
            complete(with: signature as! T)
        case (.sendTransaction, let txHash as String):
            complete(with: txHash as! T)
        default:
            complete(with: MetaMaskError.invalidResponse)
        }
    }
    
    private func handleConnectResult(_ response: ConnectResponse) {
        logger.debug("Handling connect result: chainId=\(response.data.chainId), accounts=\(response.data.accounts)")
        self.chainId = response.data.chainId
        self.accounts = response.data.accounts
        self.isConnected = true
        
        Task {
            do {
                guard let address = accounts.first, !address.isEmpty else {
                    logger.error("No valid address found in connect response")
                    complete(with: MetaMaskError.invalidResponse)
                    return
                }
                
                logger.debug("Attempting external wallet login: address=\(address)")
                try await para.externalWalletLogin(externalAddress: address, type: "EVM")
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
        try await withContinuation(type: .connect) { (continuation: CheckedContinuation<Void, Error>) in
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
        let request = SignMessageRequest(params: [message, account])
        let encodedMessage = try request.encode()
        
        return try await withContinuation(type: .signMessage) { (continuation: CheckedContinuation<String, Error>) in
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
    internal func sendTransaction(_ transaction: [String: String], account: String) async throws -> String {
        logger.debug("Initiating sendTransaction for account: \(account)")
        let request = SendTransactionRequest(params: [transaction])
        let encodedMessage = try request.encode()
        
        return try await withContinuation(type: .sendTransaction) { (continuation: CheckedContinuation<String, Error>) in
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

@available(iOS 16.4, *)
private extension MetaMaskConnector {
    private func openMetaMaskURL(_ url: URL) throws {
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
            URLQueryItem(name: "scheme", value: deepLink),
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
