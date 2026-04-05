import Foundation

enum UserProfileTuner {

    // MARK: - Minimum session thresholds

    private static let minSessionsForInterventions = 5
    private static let minSessionsForRecovery      = 10
    private static let minSessionsForRiskThresholds = 15

    // MARK: - 1. Intervention cooldowns

    static func tunedInterventionConfig(
        from profile: UserProfile,
        base: InterventionConfig = .defaults
    ) -> InterventionConfig {
        guard profile.totalSessions >= minSessionsForInterventions else { return base }

        var config = base

        let softRate   = profile.softRecoveryRate
        let strongRate = profile.strongRecoveryRate

        // Soft cooldown: if soft works well, space them out (user self-corrects).
        // If soft rarely works, nudge sooner so they notice.
        if softRate > 0.65 {
            config.softCooldown = clamp(base.softCooldown * 1.5, min: 3, max: 60)
        } else if softRate < 0.3 && profile.softInterventionsFired >= 10 {
            config.softCooldown = clamp(base.softCooldown * 0.7, min: 2, max: 60)
        }

        // Strong cooldown: if strong doesn't work either, slow down to avoid
        // notification fatigue — the user is ignoring them.
        if strongRate < 0.3 && profile.strongInterventionsFired >= 5 {
            config.strongCooldown = clamp(base.strongCooldown * 1.5, min: 10, max: 120)
        } else if strongRate > 0.6 {
            config.strongCooldown = clamp(base.strongCooldown * 0.8, min: 8, max: 120)
        }

        // Escalation delay: if soft works well, wait longer before escalating.
        // If soft fails but strong works, escalate faster.
        if softRate > 0.6 {
            config.escalationDelay = clamp(base.escalationDelay * 1.5, min: 5, max: 90)
        } else if softRate < 0.3 && strongRate > 0.5 && profile.softInterventionsFired >= 10 {
            config.escalationDelay = clamp(base.escalationDelay * 0.7, min: 3, max: 90)
        }

        return config
    }

    // MARK: - 2. Recovery threshold

    static func tunedRecoveryThreshold(from profile: UserProfile) -> Double {
        let defaultThreshold = 0.7

        guard profile.totalSessions >= minSessionsForRecovery else { return defaultThreshold }

        // Use the user's median focus score as their baseline, then set recovery
        // threshold slightly above it. This means "recovered" = "back to your
        // personal normal or better," not an arbitrary absolute number.
        let baseline = profile.baselineFocusScore
        let threshold = baseline + 0.10

        return clamp(threshold, min: 0.45, max: 0.90)
    }

    // MARK: - 3. Risk thresholds

    static func tunedRuleConfig(
        from profile: UserProfile,
        base: RuleConfig = .defaults
    ) -> RuleConfig {
        guard profile.totalSessions >= minSessionsForRiskThresholds else { return base }

        var config = base

        let dist       = profile.workStateDistribution
        let focusAvg   = profile.averageFocusScore
        let switchAvg  = profile.averageSwitchesPerMinute
        let atRiskFrac = profile.totalDuration > 0
            ? profile.totalTimeAtRisk / profile.totalDuration
            : 0

        // Productive multi-tasker: high focus despite frequent switching.
        // Signal: good focus score + lots of time in productiveSwitching +
        // above-average switching rate. Give them more runway before flagging
        // noveltySeeking or stuckCycling as risky.
        let productiveSwitchFrac = dist[WorkState.productiveSwitching.rawValue] ?? 0
        let isProductiveSwitcher = focusAvg > 0.65
            && switchAvg > 4.0
            && productiveSwitchFrac > 0.3

        if isProductiveSwitcher {
            config.noveltySeekingAtRisk = clamp(base.noveltySeekingAtRisk * 1.8, min: 8, max: 120)
            config.noveltySeekingDrift  = clamp(base.noveltySeekingDrift * 1.5,  min: 30, max: 300)
            config.stuckCyclingAtRisk   = clamp(base.stuckCyclingAtRisk * 1.5,   min: 20, max: 300)
            config.stuckCyclingDrift    = clamp(base.stuckCyclingDrift * 1.5,     min: 60, max: 600)
        }

        // Drift-prone user: low focus, high atRisk fraction.
        // Signal: average focus below 0.5 + spends >20% of time at risk.
        // Tighten thresholds so warnings come earlier.
        let isDriftProne = focusAvg < 0.5 && atRiskFrac > 0.20

        if isDriftProne {
            config.noveltySeekingAtRisk = clamp(base.noveltySeekingAtRisk * 0.6, min: 5, max: 60)
            config.noveltySeekingDrift  = clamp(base.noveltySeekingDrift * 0.6,  min: 15, max: 120)
            config.passiveDriftAtRisk   = clamp(base.passiveDriftAtRisk * 0.7,   min: 10, max: 120)
            config.passiveDriftDrift    = clamp(base.passiveDriftDrift * 0.7,     min: 30, max: 240)
            config.stuckCyclingAtRisk   = clamp(base.stuckCyclingAtRisk * 0.7,   min: 10, max: 120)
            config.stuckCyclingDrift    = clamp(base.stuckCyclingDrift * 0.7,     min: 30, max: 240)
        }

        // Deep focus user: mostly in deepFocus state, low switching.
        // These users are highly sensitive to any interruption, so the default
        // thresholds are fine — but give passive drift more room since they
        // might just be reading/thinking for long stretches.
        let deepFocusFrac = dist[WorkState.deepFocus.rawValue] ?? 0
        let isDeepFocuser = deepFocusFrac > 0.4 && switchAvg < 2.0

        if isDeepFocuser {
            config.passiveDriftAtRisk = clamp(base.passiveDriftAtRisk * 1.4, min: 30, max: 300)
            config.passiveDriftDrift  = clamp(base.passiveDriftDrift * 1.3,  min: 60, max: 600)
        }

        return config
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, value))
    }
}
