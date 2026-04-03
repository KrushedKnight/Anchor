import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appObserver              = ActiveAppObserver()
    let idleMonitor              = IdleMonitor()
    let chromeMonitor            = ChromeURLMonitor()
    let windowTitleObserver      = WindowTitleObserver()
    let heartbeatMonitor         = ActivityHeartbeatMonitor()
    let interventionRecorder     = InterventionEventRecorder()
    let interventionEngine       = InterventionEngine.shared
    let notificationHandler      = NotificationHandler.shared

    private var widgetPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appObserver.start()
        if UserDefaults.standard.object(forKey: "observer.idle") as? Bool ?? true {
            idleMonitor.start()
        }
        if UserDefaults.standard.object(forKey: "observer.chrome") as? Bool ?? true {
            chromeMonitor.start()
        }
        if UserDefaults.standard.object(forKey: "observer.windowTitle") as? Bool ?? true {
            windowTitleObserver.start()
        }
        heartbeatMonitor.start()
        interventionRecorder.start()
        DriftEngine.shared.start()
        interventionEngine.start()
        notificationHandler.start()

        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            self.setupWidgetPanel()
        }
    }

    private func setupWidgetPanel() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isFloatingPanel              = true
        panel.level                        = .floating
        panel.isOpaque                     = false
        panel.backgroundColor              = .clear
        panel.hasShadow                    = true
        panel.isMovableByWindowBackground  = true
        panel.collectionBehavior           = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: WidgetView())
        hosting.setFrameSize(hosting.fittingSize)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        if let screen = NSScreen.main {
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - size.width - 16,
                y: screen.visibleFrame.maxY - size.height - 16
            ))
        }

        widgetPanel = panel
        updateWidgetVisibility()
        observeSessionState()
    }

    private func observeSessionState() {
        withObservationTracking {
            _ = SessionManager.shared.isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateWidgetVisibility()
                self?.observeSessionState()
            }
        }
    }

    private func updateWidgetVisibility() {
        if SessionManager.shared.isActive {
            widgetPanel?.orderFront(nil)
        } else {
            widgetPanel?.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appObserver.stop()
        idleMonitor.stop()
        chromeMonitor.stop()
        windowTitleObserver.stop()
        heartbeatMonitor.stop()
        interventionRecorder.stop()
        DriftEngine.shared.stop()
        interventionEngine.stop()
        notificationHandler.stop()
    }
}
