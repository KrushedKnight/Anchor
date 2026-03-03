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
            EventStore.shared.append(
                type: "idle_start",
                data: ["thresholdSec": String(Int(threshold))]
            )
        } else if isIdle && secondsIdle <= threshold {
            let duration = idleStartTime.map { Date().timeIntervalSince($0) } ?? 0
            isIdle = false
            idleStartTime = nil
            EventStore.shared.append(
                type: "idle_end",
                data: ["idleDurationSec": String(Int(duration))]
            )
        }
    }
}
