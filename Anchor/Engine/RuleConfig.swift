import Foundation

struct RuleConfig {
    var knownBrowsers:              Set<String>
    var evaluationInterval:         TimeInterval    // engine tick rate

    var scatterAppsThreshold:       Int             // distinct apps in 5m before scatter state triggers
    var dwellSkimmingThreshold:     TimeInterval    // avg dwell below this = short dwells (used by state inference)
    var recoveryDecayRate:          Double          // accumulator seconds removed per on-task second

    var stuckCyclingAtRisk:         TimeInterval    // seconds in stuckCycling before atRisk
    var stuckCyclingDrift:          TimeInterval    // seconds in stuckCycling before drift
    var noveltySeekingAtRisk:       TimeInterval    // seconds in noveltySeeking before atRisk
    var noveltySeekingDrift:        TimeInterval    // seconds in noveltySeeking before drift
    var passiveDriftAtRisk:         TimeInterval    // seconds in passiveDrift before atRisk
    var passiveDriftDrift:          TimeInterval    // seconds in passiveDrift before drift
    var idleAtRisk:                 TimeInterval    // seconds idle before atRisk
    var idleDrift:                  TimeInterval    // seconds idle before drift
    var highDwellThreshold:         TimeInterval    // seconds before dwell counts as "high"
    var scoreDecayWindow:           TimeInterval    // seconds over which score decays from base to floor
    var republishInterval:          TimeInterval    // seconds between re-publishing when user hasn't recovered
    var recoveryConfirmationTime:   TimeInterval    // seconds contextFit must stay good to confirm recovery
    var recoveryFitThreshold:       Double          // contextFit above this = "recovered"
    var distractionPressureDecay:   TimeInterval    // seconds of on-task needed to fully reset pressure

    static let defaults = RuleConfig(
        knownBrowsers: ["Google Chrome", "Firefox", "Safari"],
        evaluationInterval:         2,
        scatterAppsThreshold:       3,
        dwellSkimmingThreshold:     8,
        recoveryDecayRate:          1.5,
        stuckCyclingAtRisk:         45,
        stuckCyclingDrift:          120,
        noveltySeekingAtRisk:       20,
        noveltySeekingDrift:        60,
        passiveDriftAtRisk:         45,
        passiveDriftDrift:          120,
        idleAtRisk:                 30,
        idleDrift:                  120,
        highDwellThreshold:         25,
        scoreDecayWindow:           300,
        republishInterval:          30,
        recoveryConfirmationTime:   15,
        recoveryFitThreshold:       0.7,
        distractionPressureDecay:   60
    )
}
