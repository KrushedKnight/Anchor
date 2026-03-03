import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appObserver = ActiveAppObserver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appObserver.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appObserver.stop()
    }
}
