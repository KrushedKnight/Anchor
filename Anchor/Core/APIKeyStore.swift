import Foundation
import Security

@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    private(set) var isSet: Bool = false

    private let service = "com.krushedknight.Anchor"
    private let account = "anthropic-api-key"

    private init() {
        isSet = retrieve() != nil
    }

    func save(_ key: String) {
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        let attrs: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData:   data
        ]
        SecItemAdd(attrs as CFDictionary, nil)
        isSet = true
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        isSet = false
    }

    func retrieve() -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key  = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }
}
