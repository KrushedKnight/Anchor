import Foundation

@Observable
final class SessionManager {
    static let shared = SessionManager()

    private(set) var activeSession: FocusSession?
    private(set) var isPaused:      Bool            = false
    private(set) var lastSummary:   SessionSummary? = nil
    private(set) var breakTracker                   = BreakTracker()
    private(set) var pomodoroTimer: PomodoroTimer?

    var isActive: Bool { activeSession != nil }
    var isPomodoro: Bool { pomodoroTimer != nil }

    var activeWorkTime: TimeInterval {
        guard let start = activeSession?.startedAt else { return 0 }
        return Date.now.timeIntervalSince(start) - breakTracker.totalBreakTime
    }

    var totalElapsed: TimeInterval {
        guard let start = activeSession?.startedAt else { return 0 }
        return Date.now.timeIntervalSince(start)
    }

    private init() {}

    func start(
        taskTitle:          String,
        appClassifications: [String: ContextFitLevel] = [:],
        taskProfile:        TaskProfile?               = nil,
        pomodoroConfig:     PomodoroConfig?            = nil
    ) {
        let profile = taskProfile ?? TaskProfile()
        let session = FocusSession(
            taskTitle:          taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            taskProfile:        profile,
            appClassifications: appClassifications
        )
        activeSession = session
        isPaused = false
        breakTracker = BreakTracker()

        if let config = pomodoroConfig {
            let timer = PomodoroTimer(config: config)
            pomodoroTimer = timer
            timer.start()
        } else {
            pomodoroTimer = nil
        }

        EventStore.shared.append(
            type: "session_started",
            data: [
                "session_id": session.id.uuidString,
                "task_title": session.taskTitle,
                "mode": pomodoroConfig != nil ? "pomodoro" : "freeform",
                "on_task":    session.appClassifications.filter { $0.value == .onTask }.keys.sorted().joined(separator: ","),
                "ambiguous":  session.appClassifications.filter { $0.value == .ambiguous }.keys.sorted().joined(separator: ","),
                "off_task":   session.appClassifications.filter { $0.value == .offTask }.keys.sorted().joined(separator: ",")
            ]
        )
    }

    func classifyApp(_ app: String, as level: ContextFitLevel) {
        activeSession?.classifyApp(app, as: level)
    }

    func classifyDomain(_ domain: String, as level: ContextFitLevel) {
        activeSession?.classifyDomain(domain, as: level)
    }

    func classifyTaskProfile() {
        guard let session = activeSession, TaskClassifier.isConfigured else { return }

        Task {
            do {
                let profile = try await TaskClassifier.shared.classifyTaskProfile(task: session.taskTitle)
                activeSession?.taskProfile = profile
                print("[SessionManager] classified task profile: switching=\(String(format: "%.1fx", profile.switchingMultiplier)) priority=\(profile.distractionPriority.rawValue)")
            } catch {
                print("[SessionManager] task profile classification failed: \(error)")
            }
        }
    }

    func pause(reason: String = "manual") {
        guard let session = activeSession, !isPaused else { return }
        isPaused = true
        breakTracker.startBreak()
        EventStore.shared.append(
            type: "session_paused",
            data: [
                "session_id":   session.id.uuidString,
                "pause_reason": reason,
                "break_number": "\(breakTracker.breakCount)"
            ]
        )
    }

    func resume() {
        guard let session = activeSession, isPaused else { return }
        let breakDuration = breakTracker.intervals.last?.duration ?? 0
        breakTracker.endBreak()
        isPaused = false
        EventStore.shared.append(
            type: "session_resumed",
            data: [
                "session_id":     session.id.uuidString,
                "break_duration": "\(Int(breakDuration))"
            ]
        )
    }

    func end(reason: String = "manual") {
        guard let session = activeSession else { return }

        if isPaused {
            breakTracker.endBreak()
            isPaused = false
        }

        pomodoroTimer?.stop()

        let summary = SessionStatsAccumulator.shared.finalize(
            session:        session,
            finalState:     DriftEngine.shared.state,
            totalBreakTime: breakTracker.totalBreakTime,
            breakCount:     breakTracker.breakCount,
            pomodoroCompletedCycles: pomodoroTimer?.completedCycles
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
            data: [
                "session_id":       session.id.uuidString,
                "end_reason":       reason,
                "total_break_time": "\(Int(breakTracker.totalBreakTime))",
                "break_count":      "\(breakTracker.breakCount)",
                "active_work_time": "\(Int(Date.now.timeIntervalSince(session.startedAt) - breakTracker.totalBreakTime))"
            ]
        )

        activeSession  = nil
        pomodoroTimer  = nil
        breakTracker   = BreakTracker()
    }

    func dismissSummary() {
        lastSummary = nil
    }
}
