import Foundation
import Security

public protocol SecretStore: Sendable {
    func get(account: String) -> String?
    func set(_ value: String, account: String)
    func delete(account: String)
}

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

    public func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account)
            q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
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
    public func set(_ value: String, account: String) { lock.lock(); defer { lock.unlock() }; values[account] = value }
    public func delete(account: String) { lock.lock(); defer { lock.unlock() }; values[account] = nil }
}
