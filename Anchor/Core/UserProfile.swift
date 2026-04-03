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
