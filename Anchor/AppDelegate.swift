import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appObserver   = ActiveAppObserver()
    let idleMonitor   = IdleMonitor()
    let chromeMonitor = ChromeURLMonitor()

    private var widgetPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appObserver.start()
        idleMonitor.start()
        chromeMonitor.start()
        DriftEngine.shared.start()

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
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.isFloatingPanel              = true
        panel.level                        = .floating
        panel.isOpaque                     = false
        panel.backgroundColor              = .clear
        panel.hasShadow                    = true
        panel.titleVisibility              = .hidden
        panel.titlebarAppearsTransparent   = true
        panel.isMovableByWindowBackground  = true
        panel.collectionBehavior           = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: WidgetView())
        hosting.setFrameSize(hosting.fittingSize)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)

        if let screen = NSScreen.main {
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - size.width - 16,
                y: screen.visibleFrame.maxY - size.height - 16
            ))
        }

        panel.orderFront(nil)
        widgetPanel = panel
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
        DriftEngine.shared.stop()
    }
}
