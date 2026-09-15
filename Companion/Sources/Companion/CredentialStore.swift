import Foundation
import Security

protocol CredentialBackend {
    func read(_ account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func remove(_ account: String) throws
}

struct KeychainCredentialBackend: CredentialBackend {
    let service: String

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func read(_ account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CredentialError.storage }
        return value
    }

    func write(_ value: String, account: String) throws {
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CredentialError.storage }
        } else if status != errSecSuccess { throw CredentialError.storage }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.storage }
    }
}

enum CredentialError: LocalizedError {
    case storage
    var errorDescription: String? { "Couldn't save or read a provider key in Keychain. Unlock your Mac and try again. Existing keys were not removed." }
}

// Preview and unit tests must never touch production credentials.
final class MemoryCredentialBackend: CredentialBackend {
    var values: [String: String] = [:]
    func read(_ account: String) throws -> String? { values[account] }
    func write(_ value: String, account: String) throws { values[account] = value }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
}

final class CredentialStore {
    private let backend: CredentialBackend
    init(backend: CredentialBackend) { self.backend = backend }

    func value(for account: String) throws -> String { try backend.read(account) ?? "" }

    func set(_ value: String, for account: String) throws {
        if value.isEmpty {
            try backend.remove(account)
            guard try backend.read(account) == nil else { throw CredentialError.storage }
        } else {
            try backend.write(value, account: account)
            guard try backend.read(account) == value else { throw CredentialError.storage }
        }
    }

    func migrate(accounts: [String], from defaults: UserDefaults) throws {
        for account in accounts {
            guard let oldValue = defaults.string(forKey: account) else { continue }
            if try value(for: account).isEmpty, !oldValue.isEmpty {
                try set(oldValue, for: account)
            }
            // Only remove plaintext after successful storage/read-back (or an empty old value).
            defaults.removeObject(forKey: account)
        }
    }
}
