import Foundation

final class SessionStatsAccumulator {
    static let shared = SessionStatsAccumulator()

    private var focusScoreSamples:     [Double]                    = []
    private var timeInLevel:           [RiskLevel: TimeInterval]   = [:]
    private var offTaskDwellByContext: [String: TimeInterval]      = [:]
    private var longestFocusStreak:    TimeInterval                = 0
    private(set) var interventionCount: Int                        = 0
    private(set) var escalationCount:   Int                        = 0

    private var interventionTimestamps: [(date: Date, level: Intervention.Level)] = []
    private var focusScoreTimeline:     [(date: Date, score: Double)]             = []

    func reset() {
        focusScoreSamples      = []
        timeInLevel            = [:]
        offTaskDwellByContext  = [:]
        longestFocusStreak     = 0
        interventionCount      = 0
        escalationCount        = 0
        interventionTimestamps = []
        focusScoreTimeline     = []
    }

    func record(state: EngineState, interval: TimeInterval) {
        focusScoreSamples.append(state.focusScore)
        focusScoreTimeline.append((.now, state.focusScore))
        timeInLevel[state.riskLevel, default: 0] += interval

        if state.isOffTaskContext {
            let ctx = state.currentDomain.isEmpty ? state.currentApp : state.currentDomain
            if !ctx.isEmpty {
                offTaskDwellByContext[ctx, default: 0] += interval
            }
        }

        if state.focusStreakSeconds > longestFocusStreak {
            longestFocusStreak = state.focusStreakSeconds
        }
    }

    func recordIntervention(level: Intervention.Level) {
        interventionCount += 1
        if level == .strong { escalationCount += 1 }
        interventionTimestamps.append((.now, level))
    }

    func evaluateInterventionOutcomes(
        recoveryWindow:    TimeInterval = 120,
        recoveryThreshold: Double       = 0.7
    ) -> [InterventionOutcome] {
        interventionTimestamps.map { (date, level) in
            let windowEnd = date.addingTimeInterval(recoveryWindow)
            let recovered = focusScoreTimeline.contains { sample in
                sample.date > date && sample.date <= windowEnd && sample.score >= recoveryThreshold
            }
            return InterventionOutcome(level: level, recovered: recovered)
        }
    }

    func finalize(session: FocusSession, finalState: EngineState) -> SessionSummary {
        let samples = focusScoreSamples
        let avg     = samples.isEmpty ? 1.0 : samples.reduce(0, +) / Double(samples.count)

        let topDistractions = offTaskDwellByContext
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { SessionSummary.DistractionEntry(context: $0.key, seconds: $0.value) }

        return SessionSummary(
            id:              UUID(),
            sessionId:       session.id,
            taskTitle:       session.taskTitle,
            startedAt:       session.startedAt,
            endedAt:         .now,
            focusScoreAvg:   avg,
            focusScoreFinal: finalState.focusScore,
            focusScoreMin:   samples.min() ?? 1.0,
            focusScoreMax:   samples.max() ?? 1.0,
            timeStable:      timeInLevel[.stable] ?? 0,
            timeAtRisk:      timeInLevel[.atRisk] ?? 0,
            timeDrift:       timeInLevel[.drift]  ?? 0,
            offTaskTime:     finalState.totalOffTaskDwell,
            longestFocusStreak: longestFocusStreak,
            interventionCount:  interventionCount,
            escalationCount:    escalationCount,
            topDistractions:    Array(topDistractions)
        )
    }
}
