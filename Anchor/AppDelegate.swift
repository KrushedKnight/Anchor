import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appObserver = ActiveAppObserver()
    let idleMonitor = IdleMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appObserver.start()
        idleMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appObserver.stop()
        idleMonitor.stop()
    }
}
