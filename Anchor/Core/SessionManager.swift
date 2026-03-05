import Foundation

@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var activeSession: FocusSession?

    var isActive: Bool { activeSession != nil }

    private init() {}

    func start(taskTitle: String, strictness: FocusSession.Strictness) {
        activeSession = FocusSession(
            taskTitle:  taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            strictness: strictness
        )
    }

    func end() {
        activeSession = nil
    }
}
