import Foundation

final class UserProfileStore {
    static let shared = UserProfileStore()

    private let fileURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting     = [.prettyPrinted, .sortedKeys]
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
        let dir = appSupport.appendingPathComponent("Anchor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("user_profile.json")
    }

    func load() -> UserProfile {
        guard let data = try? Data(contentsOf: fileURL),
              let profile = try? decoder.decode(UserProfile.self, from: data)
        else { return UserProfile() }
        return profile
    }

    func save(_ profile: UserProfile) {
        guard let data = try? encoder.encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
