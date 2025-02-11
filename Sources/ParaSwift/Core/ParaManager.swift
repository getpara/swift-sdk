import SwiftUI
import AuthenticationServices
import WebKit
import os

#if os(iOS)
@available(iOS 16.4,*)
@MainActor
public class ParaManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.paraSwift", category: "ParaManager")
    
    @Published public var wallets: [Wallet] = []
    @Published public var sessionState: ParaSessionState = .unknown
    
    public var isReady: Bool {
        return paraWebView.isReady
    }
    
    public static let packageVersion = "1.0.0"
    public var environment: ParaEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    public var apiKey: String
    
    private let passkeysManager: PasskeysManager
    private let paraWebView: ParaWebView
    
    public init(environment: ParaEnvironment, apiKey: String) {
        self.environment = environment
        self.apiKey = apiKey
        self.passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        self.paraWebView = ParaWebView(environment: environment, apiKey: apiKey)
        super.init()
        Task {
            await waitForParaReady()
        }
    }
    
    private func waitForParaReady() async {
        let startTime = Date()
        let maxWaitDuration: TimeInterval = 30.0
        while !paraWebView.isReady && paraWebView.initializationError == nil && paraWebView.lastError == nil {
            if Date().timeIntervalSince(startTime) > maxWaitDuration {
                sessionState = .inactive
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if paraWebView.initializationError != nil || paraWebView.lastError != nil {
            sessionState = .inactive
            return
        }

        if let active = try? await isSessionActive(), active {
            if let loggedIn = try? await isFullyLoggedIn(), loggedIn {
                sessionState = .activeLoggedIn
            } else {
                sessionState = .active
            }
        } else {
            sessionState = .inactive
        }
    }
    
    internal func postMessage(method: String, arguments: [Encodable]) async throws -> Any? {
        return try await paraWebView.postMessage(method: method, arguments: arguments)
    }
    
    internal func decodeResult<T>(_ result: Any?, expectedType: T.Type, method: String) throws -> T {
        guard let value = result as? T else {
            throw ParaError.bridgeError("METHOD_ERROR<\(method)>: Invalid result format expected \(T.self), but got \(String(describing: result))")
        }
        return value
    }
    
    internal func decodeDictionaryResult<T>(_ result: Any?, expectedType: T.Type, method: String, key: String) throws -> T {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)
        guard let value = dict[key] as? T else {
            throw ParaError.bridgeError("KEY_ERROR<\(method)-\(key)>: Missing or invalid key result")
        }
        return value
    }
}

@available(iOS 16.4,*)
extension ParaManager {
    public func checkIfUserExists(email: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExists", arguments: [email])
        return try decodeResult(result, expectedType: Bool.self, method: "checkIfUserExists")
    }
    
    public func checkIfUserExistsByPhone(phoneNumber: String, countryCode: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExistsByPhone", arguments: [phoneNumber, countryCode])
        return try decodeResult(result, expectedType: Bool.self, method: "checkIfUserExistsByPhone")
    }
    
    public func createUser(email: String) async throws {
        _ = try await postMessage(method: "createUser", arguments: [email])
    }
    
    public func createUserByPhone(phoneNumber: String, countryCode: String) async throws {
        _ = try await postMessage(method: "createUserByPhone", arguments: [phoneNumber, countryCode])
    }
    
    @available(macOS 13.3, iOS 16.4, *)
    @MainActor
    public func login(authorizationController: AuthorizationController) async throws {
        let getWebChallengeResult = try await postMessage(method: "getWebChallenge", arguments: [])
        let challenge = try decodeDictionaryResult(getWebChallengeResult, expectedType: String.self, method: "getWebChallenge", key: "challenge")
        
        let signIntoPasskeyAccountResult = try await passkeysManager.signIntoPasskeyAccount(authorizationController: authorizationController, challenge: challenge)
        
        let id = signIntoPasskeyAccountResult.credentialID.base64URLEncodedString()
        let authenticatorData = signIntoPasskeyAccountResult.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = signIntoPasskeyAccountResult.rawClientDataJSON.base64URLEncodedString()
        let signature = signIntoPasskeyAccountResult.signature.base64URLEncodedString()
        
        let verifyWebChallengeResult = try await postMessage(method: "verifyWebChallenge", arguments: [id, authenticatorData, clientDataJSON, signature])
        let userId = try decodeResult(verifyWebChallengeResult, expectedType: String.self, method: "verifyWebChallenge")
        
        _ = try await postMessage(method: "loginV2", arguments: [userId, id, signIntoPasskeyAccountResult.userID.base64URLEncodedString()])
        self.wallets = try await fetchWallets()
        sessionState = .activeLoggedIn
    }
    
    public func verify(verificationCode: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "verifyEmail", arguments: [verificationCode])
        let resultString = try decodeResult(result, expectedType: String.self, method: "verifyEmail")
        
        let paths = resultString.split(separator: "/")
        guard let lastPath = paths.last,
              let biometricsId = lastPath.split(separator: "?").first else {
            throw ParaError.bridgeError("Invalid path format in result")
        }
        
        return String(biometricsId)
    }
    
    public func verifyByPhone(verificationCode: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "verifyPhone", arguments: [verificationCode])
        let resultString = try decodeResult(result, expectedType: String.self, method: "verifyPhone")
        
        let paths = resultString.split(separator: "/")
        guard let lastPath = paths.last,
              let biometricsId = lastPath.split(separator: "?").first else {
            throw ParaError.bridgeError("Invalid path format in result")
        }
        
        return String(biometricsId)
    }
    
    @available(macOS 13.3, iOS 16.4, *)
    public func generatePasskey(identifier: String, biometricsId: String, authorizationController: AuthorizationController) async throws {
        try await ensureWebViewReady()
        var userHandle = Data(count: 32)
        _ = userHandle.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        let userHandleEncoded = userHandle.base64URLEncodedString()
        let result = try await passkeysManager.createPasskeyAccount(authorizationController: authorizationController,
                                                                    username: identifier, userHandle: userHandle)

        guard let rawAttestation = result.rawAttestationObject else {
            throw ParaError.bridgeError("Missing attestation object")
        }
        let rawClientData = result.rawClientDataJSON
        let credID = result.credentialID

        let attestationObjectEncoded = rawAttestation.base64URLEncodedString()
        let clientDataJSONEncoded = rawClientData.base64URLEncodedString()
        let credentialIDEncoded = credID.base64URLEncodedString()

        _ = try await postMessage(method: "generatePasskeyV2",
                                arguments: [attestationObjectEncoded, clientDataJSONEncoded, credentialIDEncoded, userHandleEncoded, biometricsId])
    }
    
    public func setup2FA() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "setup2FA", arguments: [])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "setup2FA", key: "uri")
    }
    
    public func enable2FA() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "enable2FA", arguments: [])
    }
    
    public func is2FASetup() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "check2FAStatus", arguments: [])
        return try decodeDictionaryResult(result, expectedType: Bool.self, method: "check2FAStatus", key: "isSetup")
    }
    
    public func resendVerificationCode() async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "resendVerificationCode", arguments: [])
    }
    
    public func isFullyLoggedIn() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isFullyLoggedIn", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isFullyLoggedIn")
    }
    
    public func isSessionActive() async throws -> Bool {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "isSessionActive", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isSessionActive")
    }
    
    public func exportSession() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "exportSession", arguments: [])
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }
    
    public func logout() async throws {
        _ = try await postMessage(method: "logout", arguments: [])
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        wallets = []
        self.sessionState = .inactive
    }
}

@available(iOS 16.4,*)
extension ParaManager {
    @MainActor
    public func createWallet(type: WalletType, skipDistributable: Bool) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "createWallet", arguments: [type.rawValue, skipDistributable])
        self.wallets = try await fetchWallets()
        self.sessionState = .activeLoggedIn
    }
    
    public func fetchWallets() async throws -> [Wallet] {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "fetchWallets", arguments: [])
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }
    
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await ensureWebViewReady()
        _ = try await postMessage(method: "distributeNewWalletShare", arguments: [walletId, userShare])
    }
    
    public func getEmail() async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "getEmail", arguments: [])
        return try decodeResult(result, expectedType: String.self, method: "getEmail")
    }
}

@available(iOS 16.4,*)
extension ParaManager {
    public func signMessage(walletId: String, message: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "signMessage", arguments: [walletId, message.toBase64()])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signMessage", key: "signature")
    }
    
    public func signTransaction(walletId: String, rlpEncodedTx: String, chainId: String) async throws -> String {
        try await ensureWebViewReady()
        let result = try await postMessage(method: "signTransaction", arguments: [walletId, rlpEncodedTx, chainId])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signTransaction", key: "signature")
    }
}

@available(iOS 16.4,*)
extension ParaManager {
    private func ensureWebViewReady() async throws {
        if !paraWebView.isReady {
            logger.debug("Waiting for WebView initialization...")
            await waitForParaReady()
            guard paraWebView.isReady else {
                throw ParaError.bridgeError("WebView failed to initialize")
            }
        }
    }

    /// Logs in with an external wallet address
    /// - Parameters:
    ///   - externalAddress: The external wallet address
    ///   - type: The type of wallet (e.g. "EVM")
    internal func externalWalletLogin(externalAddress: String, type: String) async throws {
        try await ensureWebViewReady()
        
        _ = try await postMessage(method: "externalWalletLogin", arguments: [externalAddress, type])
        self.sessionState = .activeLoggedIn
        
        logger.debug("External wallet login completed for address: \(externalAddress)")
    }
}

public enum ParaError: Error, CustomStringConvertible {
    case bridgeError(String)
    case bridgeTimeoutError
    
    public var description: String {
        switch self {
        case .bridgeError(let info):
            return "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            return "The javascript bridge did not respond in time and the continuation has been cancelled."
        }
    }
}
#endif
