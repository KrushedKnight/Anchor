import CoreGraphics
import Foundation

final class ActivityHeartbeatMonitor {
    var interval: TimeInterval = 60.0

    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let session = SessionManager.shared.activeSession else { return }

        let secondsIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        let activityPresent = secondsIdle < 60

        let engineState = DriftEngine.shared.state

        EventStore.shared.append(
            type: "activity_heartbeat",
            data: [
                "session_id":        session.id.uuidString,
                "foreground_app":    engineState.currentApp,
                "foreground_domain": engineState.currentDomain,
                "activity_present":  activityPresent ? "true" : "false"
            ]
        )
    }
}
