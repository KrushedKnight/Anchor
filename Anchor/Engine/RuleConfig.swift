import Foundation

struct RuleConfig {
    var knownBrowsers:              Set<String>
    var distractingDomains:         Set<String>
    var totalOffTaskDwellThreshold: TimeInterval    // accumulator ceiling for pressure scaling
    var evaluationInterval:         TimeInterval    // engine tick rate

    var scatterAppsThreshold:       Int             // distinct apps in 5m before scatter pressure starts
    var dwellSkimmingThreshold:     TimeInterval    // avg dwell below this = skimming
    var bouncingSuppression:        Double          // fraction scatter/dwell pressure is reduced when bouncing
    var recoveryDecayRate:          Double          // accumulator seconds removed per on-task second
    var idleRatioPressureFloor:     Double          // idle ratio below this = no pressure
    var focusStreakBonusWindow:     TimeInterval    // streak duration for max recovery bonus

    var atRiskEnterThreshold:       Double          // score drops below this → atRisk (2-tick confirm)
    var atRiskExitThreshold:        Double          // score rises above this → stable (3-tick confirm)
    var driftEnterThreshold:        Double          // score drops below this → drift (2-tick confirm)
    var driftExitThreshold:         Double          // score rises above this → atRisk (4-tick confirm)

    static let defaults = RuleConfig(
        knownBrowsers: ["Google Chrome", "Firefox", "Safari"],
        distractingDomains: [
            "youtube.com", "reddit.com", "twitter.com", "x.com",
            "instagram.com", "tiktok.com", "twitch.tv", "facebook.com",
            "netflix.com", "hulu.com"
        ],
        totalOffTaskDwellThreshold: 180,
        evaluationInterval:         2,
        scatterAppsThreshold:       3,
        dwellSkimmingThreshold:     8,
        bouncingSuppression:        0.6,
        recoveryDecayRate:          3.0,
        idleRatioPressureFloor:     0.4,
        focusStreakBonusWindow:     300,
        atRiskEnterThreshold:       0.60,
        atRiskExitThreshold:        0.70,
        driftEnterThreshold:        0.30,
        driftExitThreshold:         0.40
    )
}
