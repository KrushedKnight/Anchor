import Foundation

struct BreakInterval {
    var startedAt: Date
    var endedAt: Date?

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }
}

struct BreakTracker {
    private(set) var intervals: [BreakInterval] = []

    var isOnBreak: Bool { !intervals.isEmpty && intervals.last?.endedAt == nil }

    var totalBreakTime: TimeInterval {
        intervals.map(\.duration).reduce(0, +)
    }

    var breakCount: Int { intervals.count }

    var currentBreakStart: Date? {
        guard isOnBreak else { return nil }
        return intervals.last?.startedAt
    }

    mutating func startBreak() {
        guard !isOnBreak else { return }
        intervals.append(BreakInterval(startedAt: .now))
    }

    mutating func endBreak() {
        guard isOnBreak else { return }
        intervals[intervals.count - 1].endedAt = .now
    }
}
