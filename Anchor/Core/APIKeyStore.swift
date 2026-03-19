import Foundation
import Security

enum APIProvider: String, CaseIterable, Identifiable {
    case anthropic = "anthropic"
    case openAI    = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI:    "OpenAI"
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openAI:    "sk-…"
        }
    }
}

@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    private(set) var configured: Set<APIProvider> = []

    private let service = "com.krushedknight.Anchor"

    private init() {
        configured = Set(APIProvider.allCases.filter { retrieve(for: $0) != nil })
    }

    func isSet(for provider: APIProvider) -> Bool {
        configured.contains(provider)
    }

    func save(_ key: String, for provider: APIProvider) {
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        let attrs: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue,
            kSecValueData:   data
        ]
        SecItemAdd(attrs as CFDictionary, nil)
        configured.insert(provider)
    }

    func clear(for provider: APIProvider) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        configured.remove(provider)
    }

    func retrieve(for provider: APIProvider) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  provider.rawValue,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key  = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }
}
