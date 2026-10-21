import Foundation
import Security

/// Stores one password per camera.
package protocol CredentialStore {
    func password(for id: UUID) -> String
    /// An empty password removes the entry.
    func setPassword(_ password: String, for id: UUID)
}

package struct KeychainCredentialStore: CredentialStore {
    private let service: String

    package init(service: String = "CamBar") { self.service = service }

    package func password(for id: UUID) -> String {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    package func setPassword(_ password: String, for id: UUID) {
        let query = baseQuery(for: id)
        guard !password.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}

/// In-memory store for checks and previews.
package final class InMemoryCredentialStore: CredentialStore {
    private var passwords: [UUID: String] = [:]

    package init() {}

    package func password(for id: UUID) -> String { passwords[id] ?? "" }

    package func setPassword(_ password: String, for id: UUID) {
        passwords[id] = password.isEmpty ? nil : password
    }
}
