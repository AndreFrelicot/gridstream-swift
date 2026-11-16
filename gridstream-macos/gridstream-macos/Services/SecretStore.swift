import Foundation
import Security

/// String values that must not sit in plaintext preferences (token signing
/// secret, PIN hash, generated PIN). Setting `nil` removes the value.
nonisolated protocol SecretStore: Sendable {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String?, forKey key: String) throws
}

nonisolated struct SecretStoreError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Generic-password items in the login Keychain, one per key, under `service`.
nonisolated struct KeychainSecretStore: SecretStore {
    static let defaultService = "com.gridstream.macos.server-auth"

    let service: String

    init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    func string(forKey key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError(status: status)
        }
    }

    func setString(_ value: String?, forKey key: String) throws {
        guard let value else {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecretStoreError(status: status)
            }
            return
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = baseQuery(for: key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError(status: addStatus) }
        default:
            throw SecretStoreError(status: updateStatus)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

/// Process-local secret store for tests and previews.
nonisolated final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    // `@unchecked Sendable`: `values` is only touched while holding `lock`.
    private let lock = NSLock()
    private var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(forKey key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func setString(_ value: String?, forKey key: String) throws {
        lock.withLock { values[key] = value }
    }
}
