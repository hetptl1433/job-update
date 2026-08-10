import Foundation
import Security

/// Minimal Keychain wrapper for sensitive values (tokens, passwords).
/// Sensitive data must live here — never in UserDefaults.
enum KeychainStore {
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        set(Data(value.utf8), for: key)
    }

    /// Stores opaque credentials such as an archived Google user. These values
    /// receive the same device-only Keychain protection as string secrets.
    @discardableResult
    static func set(_ data: Data, for key: String) -> Bool {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ] as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func data(for key: String) -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func remove(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}
