import CoreGraphics
import Foundation

final class IdleMonitor {
    var threshold: TimeInterval = 30
    private var timer: Timer?
    private var isIdle = false
    private var idleStartTime: Date?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let secondsIdle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )

        if !isIdle && secondsIdle > threshold {
            isIdle = true
            idleStartTime = Date()
            let sessionId = SessionManager.shared.activeSession?.id.uuidString ?? ""
            EventStore.shared.append(
                type: "idle_start",
                data: ["thresholdSec": String(Int(threshold))]
            )
            EventStore.shared.append(
                type: "user_became_idle",
                data: ["session_id": sessionId, "idle_threshold_seconds": String(Int(threshold))]
            )
        } else if isIdle && secondsIdle <= threshold {
            let duration = idleStartTime.map { Date().timeIntervalSince($0) } ?? 0
            isIdle = false
            idleStartTime = nil
            let sessionId = SessionManager.shared.activeSession?.id.uuidString ?? ""
            EventStore.shared.append(
                type: "idle_end",
                data: ["idleDurationSec": String(Int(duration))]
            )
            EventStore.shared.append(
                type: "user_became_active",
                data: ["session_id": sessionId]
            )
        }
    }
}
