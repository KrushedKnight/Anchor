import Foundation
import Security

enum APIProvider: String, CaseIterable, Identifiable {
    case anthropic = "anthropic"
    case openAI    = "openai"
    case ollama    = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI:    "OpenAI"
        case .ollama:    "Ollama (Local)"
        }
    }

    var placeholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openAI:    "sk-…"
        case .ollama:    "not needed for local"
        }
    }

    var usesAPIKey: Bool {
        switch self {
        case .anthropic, .openAI: true
        case .ollama: false
        }
    }
}

struct OllamaConfig: Codable {
    var endpoint: String = "http://localhost:11434"
    var modelName: String = "mistral"
}

@Observable
final class APIKeyStore {
    static let shared = APIKeyStore()

    private(set) var configured: Set<APIProvider> = []
    private(set) var ollamaConfig: OllamaConfig = OllamaConfig()
    var activeProvider: APIProvider {
        didSet { userDefaults.set(activeProvider.rawValue, forKey: activeProviderKey) }
    }

    private let service = "com.krushedknight.Anchor"
    private let userDefaults = UserDefaults.standard
    private let ollamaConfigKey = "com.krushedknight.Anchor.ollama.config"
    private let activeProviderKey = "com.krushedknight.Anchor.activeProvider"

    private init() {
        let saved = UserDefaults.standard.string(forKey: "com.krushedknight.Anchor.activeProvider")
        activeProvider = saved.flatMap { APIProvider(rawValue: $0) } ?? .ollama
        configured = Set(APIProvider.allCases.filter { canUse($0) })
        loadOllamaConfig()
    }

    func isSet(for provider: APIProvider) -> Bool {
        configured.contains(provider)
    }

    private func canUse(_ provider: APIProvider) -> Bool {
        if provider == .ollama {
            return true // Ollama is always available if configured
        }
        return retrieve(for: provider) != nil
    }

    static func validate(_ key: String, for provider: APIProvider) -> String? {
        switch provider {
        case .anthropic:
            guard key.hasPrefix("sk-ant-") else { return "Anthropic keys must start with sk-ant-" }
            guard key.count >= 40 else { return "Key looks too short" }
            return nil
        case .openAI:
            guard key.hasPrefix("sk-") else { return "OpenAI keys must start with sk-" }
            guard key.count >= 20 else { return "Key looks too short" }
            return nil
        case .ollama:
            return nil
        }
    }

    @discardableResult
    func save(_ key: String, for provider: APIProvider) -> String? {
        guard !key.isEmpty else { return "Key cannot be empty" }

        if provider == .ollama {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                ollamaConfig.endpoint = parts[0]
                ollamaConfig.modelName = parts[1]
                saveOllamaConfig()
                configured.insert(provider)
            }
            return nil
        }

        guard let data = key.data(using: .utf8) else { return "Key contains invalid characters" }
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
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            return "Keychain error (\(status)). Try again or restart the app."
        }
        configured.insert(provider)
        return nil
    }

    func saveOllamaConfig(_ config: OllamaConfig) {
        ollamaConfig = config
        saveOllamaConfig()
        configured.insert(.ollama)
    }

    func clear(for provider: APIProvider) {
        if provider == .ollama {
            ollamaConfig = OllamaConfig()
            userDefaults.removeObject(forKey: ollamaConfigKey)
            configured.remove(provider)
            return
        }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        configured.remove(provider)
    }

    func retrieve(for provider: APIProvider) -> String? {
        if provider == .ollama {
            return "\(ollamaConfig.endpoint)|\(ollamaConfig.modelName)"
        }

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

    private func saveOllamaConfig() {
        if let encoded = try? JSONEncoder().encode(ollamaConfig) {
            userDefaults.set(encoded, forKey: ollamaConfigKey)
        }
    }

    private func loadOllamaConfig() {
        if let data = userDefaults.data(forKey: ollamaConfigKey),
           let config = try? JSONDecoder().decode(OllamaConfig.self, from: data) {
            ollamaConfig = config
        }
    }
}
