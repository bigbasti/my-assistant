import Foundation
import Security

public protocol SecretStore: Sendable {
    func get(account: String) -> String?
    func set(_ value: String, account: String) throws
    func delete(account: String)
}

public struct KeychainError: Error, Equatable { public let status: OSStatus }

public struct KeychainSecretStore: SecretStore {
    public static let service = "de.sebastiangross.MyAssistant"
    public init() {}

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }

    public func get(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        var status = SecItemUpdate(query(account) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let q = query(account).merging(attrs) { $1 }
            status = SecItemAdd(q as CFDictionary, nil)
        }
        if status != errSecSuccess { throw KeychainError(status: status) }
    }

    public func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func get(account: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    public func set(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    public func delete(account: String) { lock.lock(); defer { lock.unlock() }; values[account] = nil }
}
