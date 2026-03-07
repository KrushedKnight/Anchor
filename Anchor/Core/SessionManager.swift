import Foundation

@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var activeSession: FocusSession?
    private(set) var isPaused: Bool = false

    var isActive: Bool { activeSession != nil }

    private init() {}

    func start(
        taskTitle:      String,
        strictness:     FocusSession.Strictness,
        allowedApps:    Set<String> = [],
        blockedApps:    Set<String> = [],
        allowedDomains: Set<String> = [],
        blockedDomains: Set<String> = []
    ) {
        let session = FocusSession(
            taskTitle:      taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            strictness:     strictness,
            allowedApps:    allowedApps,
            blockedApps:    blockedApps,
            allowedDomains: allowedDomains,
            blockedDomains: blockedDomains
        )
        activeSession = session
        isPaused = false

        EventStore.shared.append(
            type: "session_started",
            data: [
                "session_id":      session.id.uuidString,
                "task_title":      session.taskTitle,
                "strictness":      session.strictness.rawValue,
                "allowed_apps":    session.allowedApps.sorted().joined(separator: ","),
                "blocked_apps":    session.blockedApps.sorted().joined(separator: ","),
                "allowed_domains": session.allowedDomains.sorted().joined(separator: ","),
                "blocked_domains": session.blockedDomains.sorted().joined(separator: ",")
            ]
        )
    }

    func pause(reason: String = "manual") {
        guard let session = activeSession, !isPaused else { return }
        isPaused = true
        EventStore.shared.append(
            type: "session_paused",
            data: ["session_id": session.id.uuidString, "pause_reason": reason]
        )
    }

    func resume() {
        guard let session = activeSession, isPaused else { return }
        isPaused = false
        EventStore.shared.append(
            type: "session_resumed",
            data: ["session_id": session.id.uuidString]
        )
    }

    func end(reason: String = "canceled") {
        guard let session = activeSession else { return }
        EventStore.shared.append(
            type: "session_ended",
            data: ["session_id": session.id.uuidString, "end_reason": reason]
        )
        activeSession = nil
        isPaused = false
    }
}
