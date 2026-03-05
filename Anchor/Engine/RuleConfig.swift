import Foundation

struct RuleConfig {
    var knownBrowsers:               Set<String>
    var distractingDomains:          Set<String>
    var switchRateThreshold:         Double           // switches/min → atRisk
    var switchRateSustainedWindow:   TimeInterval     // how long rate must stay high
    var distractingDwellThreshold:   TimeInterval     // single-domain dwell → drift
    var totalOffTaskDwellThreshold:  TimeInterval     // cumulative off-task → drift
    var recoveryWindow:              TimeInterval     // clean work needed to reset accumulator
    var evaluationInterval:          TimeInterval     // engine tick rate

    static let defaults = RuleConfig(
        knownBrowsers: ["Google Chrome", "Firefox", "Safari"],
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
        switchRateThreshold:        2,
        switchRateSustainedWindow:  5,
        distractingDwellThreshold:  5,
        totalOffTaskDwellThreshold: 10,
        recoveryWindow:             15,
        evaluationInterval:         2
    )
}
