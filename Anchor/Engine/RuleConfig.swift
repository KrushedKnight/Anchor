import Foundation

struct RuleConfig {
    var distractingDomains:          Set<String>
    var switchRateThreshold:         Double           // switches/min → atRisk
    var switchRateSustainedWindow:   TimeInterval     // how long rate must stay high
    var distractingDwellThreshold:   TimeInterval     // single-domain dwell → drift
    var totalOffTaskDwellThreshold:  TimeInterval     // cumulative off-task → drift
    var evaluationInterval:          TimeInterval     // engine tick rate

    static let defaults = RuleConfig(
        distractingDomains: [
            "youtube.com",
            "reddit.com",
            "twitter.com",
            "x.com",
            "instagram.com",
            "tiktok.com",
            "twitch.tv",
            "facebook.com",
            "netflix.com",
            "hulu.com"
        ],
        switchRateThreshold:        3,
        switchRateSustainedWindow:  10,
        distractingDwellThreshold:  20,
        totalOffTaskDwellThreshold: 45,
        evaluationInterval:         3
    )
}
