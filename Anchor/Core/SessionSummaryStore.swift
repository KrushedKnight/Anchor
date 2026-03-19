import Foundation

final class SessionSummaryStore {
    static let shared = SessionSummaryStore()

    private let directory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting    = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = appSupport.appendingPathComponent("Anchor/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ summary: SessionSummary) {
        let url = directory.appendingPathComponent("\(summary.sessionId.uuidString).json")
        guard let data = try? encoder.encode(summary) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load() -> [SessionSummary] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SessionSummary.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
