import AppKit

final class ActiveAppObserver {
    private var token: NSObjectProtocol?

    func start() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleId = app.bundleIdentifier ?? "unknown"
            let appName = app.localizedName ?? "unknown"
            Task { @MainActor in
                EventStore.shared.append(
                    type: "active_app",
                    data: ["bundleId": bundleId, "appName": appName]
                )
            }
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
    }
}
