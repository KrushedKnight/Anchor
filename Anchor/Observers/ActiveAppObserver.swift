import AppKit

final class ActiveAppObserver {
    private var token: NSObjectProtocol?
    private var previousApp: String = ""
    private var previousPolicyState: String = "unknown"

    func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleId = app.bundleIdentifier ?? "unknown"
            let appName  = app.localizedName   ?? "unknown"
            Task { @MainActor in
                let sessionId = SessionManager.shared.activeSession?.id.uuidString ?? ""
                let prev      = self.previousApp

                EventStore.shared.append(
                    type: "active_app",
                    data: ["bundleId": bundleId, "appName": appName]
                )

                if !prev.isEmpty {
                    EventStore.shared.append(
                        type: "window_focus_lost",
                        data: ["session_id": sessionId, "previous_app": prev]
                    )
                }

                EventStore.shared.append(
                    type: "foreground_app_changed",
                    data: ["session_id": sessionId, "previous_app": prev, "new_app": appName]
                )

                EventStore.shared.append(
                    type: "window_focus_gained",
                    data: ["session_id": sessionId, "new_app": appName]
                )

                if let session = SessionManager.shared.activeSession {
                    self.emitPolicyEvents(
                        session:   session,
                        prevApp:   prev,
                        newApp:    appName,
                        sessionId: sessionId
                    )
                }

                self.previousApp = appName
            }
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
    }

    private func emitPolicyEvents(
        session:   FocusSession,
        prevApp:   String,
        newApp:    String,
        sessionId: String
    ) {
        if !prevApp.isEmpty && session.allowedApps.contains(prevApp) {
            EventStore.shared.append(
                type: "context_exited_allowed_app",
                data: ["session_id": sessionId, "app_name": prevApp]
            )
        }

        if session.blockedApps.contains(newApp) {
            EventStore.shared.append(
                type: "context_entered_blocked_app",
                data: ["session_id": sessionId, "app_name": newApp]
            )
        } else if session.allowedApps.contains(newApp) {
            EventStore.shared.append(
                type: "context_entered_allowed_app",
                data: ["session_id": sessionId, "app_name": newApp]
            )
        }

        let oldState = previousPolicyState
        let newState = policyState(app: newApp, session: session)

        if oldState != newState {
            EventStore.shared.append(
                type: "policy_match_state_changed",
                data: [
                    "session_id": sessionId,
                    "old_state":  oldState,
                    "new_state":  newState,
                    "source":     "app"
                ]
            )
            previousPolicyState = newState
        }
    }

    private func policyState(app: String, session: FocusSession) -> String {
        if session.blockedApps.contains(app) { return "off_policy" }
        switch session.strictness {
        case .normal: return "on_policy"
        case .strict:
            if session.allowedApps.isEmpty { return "on_policy" }
            return session.allowedApps.contains(app) ? "on_policy" : "off_policy"
        }
    }
}
