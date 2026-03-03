import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appObserver = ActiveAppObserver()
    let idleMonitor = IdleMonitor()
    let chromeMonitor = ChromeURLMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appObserver.start()
        idleMonitor.start()
        chromeMonitor.start()
        DriftEngine.shared.start()
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
