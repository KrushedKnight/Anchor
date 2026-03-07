import AppKit
import ApplicationServices

final class WindowTitleObserver {
    private var timer: Timer?
    private var lastTitle: String = ""
    private var lastApp:   String = ""

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }

        let appName = frontApp.localizedName ?? ""
        let pid     = frontApp.processIdentifier

        let axApp = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return }

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return }

        guard title != lastTitle || appName != lastApp else { return }

        let sessionId = SessionManager.shared.activeSession?.id.uuidString ?? ""
        EventStore.shared.append(
            type: "foreground_window_changed",
            data: [
                "session_id":           sessionId,
                "app_name":             appName,
                "previous_window_title": lastTitle,
                "new_window_title":     title
            ]
        )

        lastTitle = title
        lastApp   = appName
    }
}
