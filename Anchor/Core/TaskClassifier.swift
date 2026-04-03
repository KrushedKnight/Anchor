import Foundation

struct AppClassification {
    var onTask:    Set<String>
    var ambiguous: Set<String>
    var offTask:   Set<String>
}

final class TaskClassifier {
    static let shared = TaskClassifier()
    private init() {}

    func classify(task: String, apps: [String]) async throws -> AppClassification {
        guard !task.isEmpty, !apps.isEmpty else {
            return AppClassification(onTask: [], ambiguous: [], offTask: [])
        }

        switch APIKeyStore.shared.activeProvider {
        case .anthropic: return try await classifyWithAnthropic(task: task, apps: apps)
        case .openAI:    return try await classifyWithOpenAI(task: task, apps: apps)
        case .ollama:    return try await classifyWithOllama(task: task, apps: apps)
        }
    }

    private func classifyWithAnthropic(task: String, apps: [String]) async throws -> AppClassification {
        guard let apiKey = APIKeyStore.shared.retrieve(for: .anthropic) else {
            throw ClassifierError.noAPIKey
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey,          forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",    forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let system = """
        You classify macOS apps for a focus session into three groups. \
        Return only valid JSON: {"on_task": [...], "ambiguous": [...], "off_task": [...]}. \
        on_task = core tools for this task. \
        ambiguous = plausibly useful (browser, Slack, Finder, Terminal, docs, GitHub, search). \
        off_task = clear distractors (social, entertainment, games, shopping). \
        Only include app names from the provided list. No other text.
        """
        let prompt = "Task: \(task)\nApps: \(apps.joined(separator: ", "))"

        let body: [String: Any] = [
            "model":    "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "system":   system,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let response  = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)

        guard let text = response.content.first?.text else {
            throw ClassifierError.emptyResponse
        }
        return try parse(text, known: Set(apps))
    }

    private func classifyWithOpenAI(task: String, apps: [String]) async throws -> AppClassification {
        guard let apiKey = APIKeyStore.shared.retrieve(for: .openAI) else {
            throw ClassifierError.noAPIKey
        }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let system = """
        You classify macOS apps for a focus session into three groups. \
        Return only valid JSON: {"on_task": [...], "ambiguous": [...], "off_task": [...]}. \
        on_task = core tools for this task. \
        ambiguous = plausibly useful (browser, Slack, Finder, Terminal, docs, GitHub, search). \
        off_task = clear distractors (social, entertainment, games, shopping). \
        Only include app names from the provided list. No other text.
        """
        let prompt = "Task: \(task)\nApps: \(apps.joined(separator: ", "))"

        let body: [String: Any] = [
            "model":    "gpt-4o-mini",
            "max_tokens": 256,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let response  = try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)

        guard let text = response.choices.first?.message.content else {
            throw ClassifierError.emptyResponse
        }
        return try parse(text, known: Set(apps))
    }

    private func classifyWithOllama(task: String, apps: [String]) async throws -> AppClassification {
        let endpoint = APIKeyStore.shared.ollamaConfig.endpoint
        let modelName = APIKeyStore.shared.ollamaConfig.modelName

        let urlString = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat"
        guard let url = URL(string: urlString) else {
            throw ClassifierError.invalidEndpoint
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let system = """
        You classify macOS apps for a focus session into three groups. \
        Return only valid JSON: {"on_task": [...], "ambiguous": [...], "off_task": [...]}. \
        on_task = core tools for this task. \
        ambiguous = plausibly useful (browser, Slack, Finder, Terminal, docs, GitHub, search). \
        off_task = clear distractors (social, entertainment, games, shopping). \
        Only include app names from the provided list. No other text.
        """
        let prompt = "Task: \(task)\nApps: \(apps.joined(separator: ", "))"

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        let response  = try JSONDecoder().decode(OllamaChatResponse.self, from: data)

        guard !response.message.content.isEmpty else {
            throw ClassifierError.emptyResponse
        }
        return try parse(response.message.content, known: Set(apps))
    }

    private func parse(_ text: String, known: Set<String>) throws -> AppClassification {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}")
        else { throw ClassifierError.parseError }

        let slice = String(text[start...end])
        guard let jsonData = slice.data(using: .utf8),
              let json     = try? JSONSerialization.jsonObject(with: jsonData) as? [String: [String]]
        else { throw ClassifierError.parseError }

        return AppClassification(
            onTask:    Set(json["on_task"]    ?? []).intersection(known),
            ambiguous: Set(json["ambiguous"]  ?? []).intersection(known),
            offTask:   Set(json["off_task"]   ?? []).intersection(known)
        )
    }
}

enum ClassifierError: Error {
    case emptyResponse
    case parseError
    case noProviderConfigured
    case noAPIKey
    case invalidEndpoint
    case networkError(String)
}

// Anthropic API response format
private struct AnthropicMessagesResponse: Decodable {
    struct Block: Decodable { var text: String }
    var content: [Block]
}

// OpenAI API response format
private struct OpenAICompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}

// Ollama API response format
private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        var content: String
    }
    var message: Message
}
