import Foundation

struct SessionSummary: Codable, Identifiable {
    struct DistractionEntry: Codable {
        var context: String
        var seconds: Double
    }

    var id:         UUID
    var sessionId:  UUID
    var taskTitle:  String
    var strictness: String

    var startedAt: Date
    var endedAt:   Date

    var focusScoreAvg:   Double
    var focusScoreFinal: Double
    var focusScoreMin:   Double
    var focusScoreMax:   Double

    var timeStable:          TimeInterval
    var timeAtRisk:          TimeInterval
    var timeDrift:           TimeInterval
    var offTaskTime:         TimeInterval
    var longestFocusStreak:  TimeInterval

    var interventionCount: Int
    var escalationCount:   Int

    var topDistractions: [DistractionEntry]

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}
