import Foundation

struct UserProfile: Codable {

    // MARK: - Lifetime counters

    var totalSessions:      Int           = 0
    var totalDuration:      TimeInterval  = 0
    var totalFocusScoreSum: Double        = 0
    var totalTimeStable:    TimeInterval  = 0
    var totalTimeAtRisk:    TimeInterval  = 0
    var totalTimeDrift:     TimeInterval  = 0
    var totalOffTaskTime:   TimeInterval  = 0
    var totalInterventions: Int           = 0
    var totalEscalations:   Int           = 0

    // MARK: - Distraction patterns

    var distractionDwellByContext: [String: Double] = [:]

    // MARK: - Behavior baselines

    var totalTimeByWorkState:        [String: Double] = [:]
    var totalSwitchesPerMinuteSum:   Double           = 0

    // MARK: - Intervention effectiveness

    var softInterventionsFired:      Int = 0
    var softInterventionsRecovered:  Int = 0
    var strongInterventionsFired:    Int = 0
    var strongInterventionsRecovered: Int = 0

    // MARK: - Time-of-day focus (24 hourly buckets)

    var hourlyFocusMinutes:  [Double]
    var hourlyFocusScoreSum: [Double]

    // MARK: - Session-over-session trends (rolling window)

    var recentSessions: [SessionSnapshot] = []

    struct SessionSnapshot: Codable {
        var date:              Date
        var durationMinutes:   Double
        var focusScoreAvg:     Double
        var offTaskFraction:   Double
        var interventionCount: Int
    }

    // MARK: - Metadata

    var lastUpdated:    Date = .distantPast
    var profileVersion: Int  = 1

    static let maxRecentSessions = 20

    init() {
        hourlyFocusMinutes  = Array(repeating: 0, count: 24)
        hourlyFocusScoreSum = Array(repeating: 0, count: 24)
    }
}

// MARK: - Computed properties

extension UserProfile {

    var averageFocusScore: Double {
        totalSessions > 0 ? totalFocusScoreSum / Double(totalSessions) : 1.0
    }

    var averageSessionMinutes: Double {
        totalSessions > 0 ? (totalDuration / 60) / Double(totalSessions) : 0
    }

    var softRecoveryRate: Double {
        softInterventionsFired > 0
            ? Double(softInterventionsRecovered) / Double(softInterventionsFired)
            : 0
    }

    var strongRecoveryRate: Double {
        strongInterventionsFired > 0
            ? Double(strongInterventionsRecovered) / Double(strongInterventionsFired)
            : 0
    }

    var averageSwitchesPerMinute: Double {
        totalSessions > 0 ? totalSwitchesPerMinuteSum / Double(totalSessions) : 0
    }

    var workStateDistribution: [String: Double] {
        guard totalDuration > 0 else { return [:] }
        return totalTimeByWorkState.mapValues { $0 / totalDuration }
    }

    var baselineFocusScore: Double {
        guard recentSessions.count >= 3 else { return averageFocusScore }
        let sorted = recentSessions.map(\.focusScoreAvg).sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2.0
            : sorted[mid]
    }

    var topDistractions: [(context: String, seconds: Double)] {
        distractionDwellByContext
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ($0.key, $0.value) }
    }

    func bestFocusHours(top: Int = 3) -> [Int] {
        (0..<24)
            .filter { hourlyFocusMinutes[$0] > 10 }
            .sorted {
                hourlyFocusScoreSum[$0] / hourlyFocusMinutes[$0]
                    > hourlyFocusScoreSum[$1] / hourlyFocusMinutes[$1]
            }
            .prefix(top)
            .map { $0 }
    }

    var focusArchetype: FocusArchetype {
        let dist       = workStateDistribution
        let focusAvg   = averageFocusScore
        let switchAvg  = averageSwitchesPerMinute
        let atRiskFrac = totalDuration > 0 ? totalTimeAtRisk / totalDuration : 0

        let productiveSwitchFrac = dist[WorkState.productiveSwitching.rawValue] ?? 0
        if focusAvg > 0.65 && switchAvg > 4.0 && productiveSwitchFrac > 0.3 {
            return .productiveSwitcher
        }

        let deepFocusFrac = dist[WorkState.deepFocus.rawValue] ?? 0
        if deepFocusFrac > 0.4 && switchAvg < 2.0 {
            return .deepFocuser
        }

        if focusAvg < 0.5 && atRiskFrac > 0.20 {
            return .driftProne
        }

        return .balanced
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        let sessionDays = Set(recentSessions.map { calendar.startOfDay(for: $0.date) })
        guard !sessionDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: .now)
        var checkDay = today
        if !sessionDays.contains(checkDay) {
            checkDay = calendar.date(byAdding: .day, value: -1, to: checkDay)!
            if !sessionDays.contains(checkDay) { return 0 }
        }

        var streak = 0
        while sessionDays.contains(checkDay) {
            streak += 1
            checkDay = calendar.date(byAdding: .day, value: -1, to: checkDay)!
        }
        return streak
    }

    var recentTrend: Double? {
        guard recentSessions.count >= 3 else { return nil }
        let n = Double(recentSessions.count)
        let xs = (0..<recentSessions.count).map { Double($0) }
        let ys = recentSessions.map(\.focusScoreAvg)
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let den = xs.map { ($0 - xMean) * ($0 - xMean) }.reduce(0, +)
        return den > 0 ? num / den : nil
    }
}

// MARK: - Focus Archetype

enum FocusArchetype: String {
    case productiveSwitcher = "Productive Switcher"
    case deepFocuser        = "Deep Focuser"
    case driftProne         = "Drift-Prone"
    case balanced           = "Balanced"

    var icon: String {
        switch self {
        case .productiveSwitcher: "bolt.circle"
        case .deepFocuser:        "scope"
        case .driftProne:         "wind"
        case .balanced:           "equal.circle"
        }
    }

    var description: String {
        switch self {
        case .productiveSwitcher:
            "You switch between tasks often but stay focused. Your brain likes variety — lean into it."
        case .deepFocuser:
            "You thrive in long, uninterrupted stretches. Protect those blocks — they're your superpower."
        case .driftProne:
            "You tend to wander when focus dips. Shorter sessions with clear goals can help build momentum."
        case .balanced:
            "You have a balanced focus style. No single pattern dominates — keep experimenting to find your groove."
        }
    }
}
