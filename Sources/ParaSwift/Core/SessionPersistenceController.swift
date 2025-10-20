import Foundation
import os
import Security

struct SessionSnapshot: Codable {
    let session: String
    let savedAt: Date
    let environmentName: String
    let apiKey: String
    let userId: String?
}

protocol SessionPersistenceStoring: AnyObject {
    func update(environment: ParaEnvironment, apiKey: String)
    func save(snapshot: SessionSnapshot) async throws
    func load() async throws -> SessionSnapshot?
    func clear() async throws
}

enum SessionPersistenceError: Error {
    case misconfigured
    case keychainError(OSStatus)
    case decoding(Error)
}

final class SessionPersistenceController: SessionPersistenceStoring {
    private let logger = Logger(subsystem: "com.paraSwift", category: "SessionPersistence")
    private let serviceIdentifier: String
    private var accountIdentifier: String?

    init(serviceSuffix: String = "session") {
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            serviceIdentifier = "\(bundleId).para.\(serviceSuffix)"
        } else {
            serviceIdentifier = "com.paraSwift.\(serviceSuffix)"
        }
    }

    func update(environment: ParaEnvironment, apiKey: String) {
        let envName = environment.name.lowercased()
        accountIdentifier = "para.\(envName).\(apiKey)"
    }

    func save(snapshot: SessionSnapshot) async throws {
        let data = try JSONEncoder().encode(snapshot)
        let query = try keychainQuery()
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            logger.debug("Session snapshot saved to Keychain")
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Keychain update failed: \(updateStatus, privacy: .public)")
                throw SessionPersistenceError.keychainError(updateStatus)
            }
            logger.debug("Session snapshot updated in Keychain")
        default:
            logger.error("Keychain save failed: \(status, privacy: .public)")
            throw SessionPersistenceError.keychainError(status)
        }
    }

    func load() async throws -> SessionSnapshot? {
        var query = try keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Keychain read failed: \(status, privacy: .public)")
            throw SessionPersistenceError.keychainError(status)
        }

        guard let data = result as? Data else {
            logger.error("Keychain returned unexpected payload")
            throw SessionPersistenceError.decoding(NSError(domain: "SessionPersistence", code: -1))
        }

        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            logger.error("Failed to decode session snapshot: \(error.localizedDescription, privacy: .public)")
            try await clear()
            throw SessionPersistenceError.decoding(error)
        }
    }

    func clear() async throws {
        let query = try keychainQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status, privacy: .public)")
            throw SessionPersistenceError.keychainError(status)
        }
        logger.debug("Session snapshot cleared from Keychain")
    }

    private func keychainQuery() throws -> [String: Any] {
        guard let accountIdentifier else {
            logger.error("SessionPersistenceController misconfigured: missing account identifier")
            throw SessionPersistenceError.misconfigured
        }

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountIdentifier,
        ]
    }
}
