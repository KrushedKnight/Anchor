import Foundation

@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var activeSession: FocusSession?
    private(set) var isPaused:      Bool            = false
    private(set) var lastSummary:   SessionSummary? = nil

    var isActive: Bool { activeSession != nil }

    private init() {}

    func start(
        taskTitle:          String,
        appClassifications: [String: ContextFitLevel] = [:]
    ) {
        let session = FocusSession(
            taskTitle:          taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            appClassifications: appClassifications
        )
        activeSession = session
        isPaused = false

        EventStore.shared.append(
            type: "session_started",
            data: [
                "session_id": session.id.uuidString,
                "task_title": session.taskTitle,
                "on_task":    session.appClassifications.filter { $0.value == .onTask }.keys.sorted().joined(separator: ","),
                "ambiguous":  session.appClassifications.filter { $0.value == .ambiguous }.keys.sorted().joined(separator: ","),
                "off_task":   session.appClassifications.filter { $0.value == .offTask }.keys.sorted().joined(separator: ",")
            ]
        )
    }

    func classifyApp(_ app: String, as level: ContextFitLevel) {
        activeSession?.classifyApp(app, as: level)
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

    func end(reason: String = "manual") {
        guard let session = activeSession else { return }

        let summary = SessionStatsAccumulator.shared.finalize(
            session:    session,
            finalState: DriftEngine.shared.state
        )
        SessionSummaryStore.shared.save(summary)
        lastSummary = summary

        let profile           = UserProfileStore.shared.load()
        let recoveryThreshold = UserProfileTuner.tunedRecoveryThreshold(from: profile)
        let outcomes          = SessionStatsAccumulator.shared.evaluateInterventionOutcomes(
            recoveryThreshold: recoveryThreshold
        )
        var updatedProfile = profile
        UserProfileUpdater.update(profile: &updatedProfile, with: summary, interventionOutcomes: outcomes)
        UserProfileStore.shared.save(updatedProfile)

        EventStore.shared.append(
            type: "session_ended",
            data: ["session_id": session.id.uuidString, "end_reason": reason]
        )
        activeSession = nil
        isPaused      = false
    }

    func dismissSummary() {
        lastSummary = nil
    }
}
