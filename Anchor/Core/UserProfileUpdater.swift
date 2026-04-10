import Foundation

struct InterventionOutcome {
    var level:     Intervention.Level
    var recovered: Bool
}

enum UserProfileUpdater {

    static func update(
        profile:               inout UserProfile,
        with summary:          SessionSummary,
        interventionOutcomes:  [InterventionOutcome]
    ) {
        // Lifetime counters
        profile.totalSessions      += 1
        profile.totalDuration      += summary.duration
        profile.totalFocusScoreSum += summary.focusScoreAvg
        profile.totalTimeStable    += summary.timeStable
        profile.totalTimeAtRisk    += summary.timeAtRisk
        profile.totalTimeDrift     += summary.timeDrift
        profile.totalOffTaskTime   += summary.offTaskTime
        profile.totalInterventions += summary.interventionCount
        profile.totalEscalations   += summary.escalationCount

        // Behavior baselines
        for (state, time) in summary.timeByWorkState {
            profile.totalTimeByWorkState[state, default: 0] += time
        }
        profile.totalSwitchesPerMinuteSum += summary.averageSwitchesPerMinute

        // Distraction patterns
        for entry in summary.topDistractions {
            profile.distractionDwellByContext[entry.context, default: 0] += entry.seconds
        }

        // Intervention effectiveness
        for outcome in interventionOutcomes {
            switch outcome.level {
            case .ambient:
                break
            case .soft:
                profile.softInterventionsFired += 1
                if outcome.recovered { profile.softInterventionsRecovered += 1 }
            case .strong:
                profile.strongInterventionsFired += 1
                if outcome.recovered { profile.strongInterventionsRecovered += 1 }
            }
        }

        // Hourly focus distribution
        distributeHourly(
            profile: &profile,
            start:   summary.startedAt,
            end:     summary.endedAt,
            focusScore: summary.focusScoreAvg
        )

        // Recent session snapshot
        let snapshot = UserProfile.SessionSnapshot(
            date:              summary.startedAt,
            durationMinutes:   summary.duration / 60,
            focusScoreAvg:     summary.focusScoreAvg,
            offTaskFraction:   summary.duration > 0 ? summary.offTaskTime / summary.duration : 0,
            interventionCount: summary.interventionCount
        )
        profile.recentSessions.append(snapshot)
        if profile.recentSessions.count > UserProfile.maxRecentSessions {
            profile.recentSessions.removeFirst(
                profile.recentSessions.count - UserProfile.maxRecentSessions
            )
        }

        // Prune distraction map if it grows too large
        if profile.distractionDwellByContext.count > 50 {
            let threshold: Double = 30
            profile.distractionDwellByContext = profile.distractionDwellByContext
                .filter { $0.value >= threshold }
        }

        profile.lastUpdated = .now
    }

    private static func distributeHourly(
        profile:    inout UserProfile,
        start:      Date,
        end:        Date,
        focusScore: Double
    ) {
        let cal = Calendar.current
        var cursor = start

        while cursor < end {
            let hour = cal.component(.hour, from: cursor)
            let nextHour = cal.nextDate(
                after: cursor,
                matching: DateComponents(minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? end
            let sliceEnd = min(nextHour, end)
            let minutes  = sliceEnd.timeIntervalSince(cursor) / 60.0

            profile.hourlyFocusMinutes[hour]  += minutes
            profile.hourlyFocusScoreSum[hour] += minutes * focusScore

            cursor = sliceEnd
        }
    }
}
