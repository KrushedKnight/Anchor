import Foundation

private struct StoredOverrides: Codable {
    var apps:    [String: String] = [:]
    var domains: [String: String] = [:]
}

@Observable
final class ClassificationOverrideStore {
    static let shared = ClassificationOverrideStore()

    private(set) var appOverrides:    [String: ContextFitLevel] = [:]
    private(set) var domainOverrides: [String: ContextFitLevel] = [:]

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Anchor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("classification_overrides.json")
        load()
    }

    func overrideForApp(_ app: String) -> ContextFitLevel? { appOverrides[app] }
    func overrideForDomain(_ domain: String) -> ContextFitLevel? { domainOverrides[domain] }

    func setApp(_ app: String, to level: ContextFitLevel) {
        appOverrides[app] = level
        save()
    }

    func removeApp(_ app: String) {
        appOverrides.removeValue(forKey: app)
        save()
    }

    func setDomain(_ domain: String, to level: ContextFitLevel) {
        domainOverrides[domain] = level
        save()
    }

    func removeDomain(_ domain: String) {
        domainOverrides.removeValue(forKey: domain)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredOverrides.self, from: data)
        else { return }
        appOverrides    = stored.apps.compactMapValues    { ContextFitLevel(rawValue: $0) }
        domainOverrides = stored.domains.compactMapValues { ContextFitLevel(rawValue: $0) }
    }

    private func save() {
        let stored = StoredOverrides(
            apps:    appOverrides.mapValues(\.rawValue),
            domains: domainOverrides.mapValues(\.rawValue)
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
