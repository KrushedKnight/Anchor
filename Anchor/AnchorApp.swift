import SwiftUI

@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultLaunchBehavior(.presented)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
    }
}
