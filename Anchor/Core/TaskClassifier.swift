import Foundation

struct AppClassification {
    var onTask:  Set<String>
    var offTask: Set<String>
}

final class TaskClassifier {
    static let shared = TaskClassifier()
    private init() {}

    func classify(task: String, apps: [String]) async throws -> AppClassification {
        guard let apiKey = APIKeyStore.shared.retrieve(for: .anthropic),
              !task.isEmpty, !apps.isEmpty
        else { return AppClassification(onTask: [], offTask: []) }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey,          forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",    forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let system = """
        You classify macOS apps as on-task or off-task for a focus session. \
        Return only valid JSON: {"on_task": [...], "off_task": [...]}. \
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
        let response  = try JSONDecoder().decode(MessagesResponse.self, from: data)

        guard let text = response.content.first?.text else {
            throw ClassifierError.emptyResponse
        }
        return try parse(text, known: Set(apps))
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
            onTask:  Set(json["on_task"]  ?? []).intersection(known),
            offTask: Set(json["off_task"] ?? []).intersection(known)
        )
    }
}

enum ClassifierError: Error {
    case emptyResponse
    case parseError
}

private struct MessagesResponse: Decodable {
    struct Block: Decodable { var text: String }
    var content: [Block]
}
