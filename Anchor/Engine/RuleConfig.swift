import Foundation

struct RuleConfig {
    var knownBrowsers:              Set<String>
    var distractingDomains:         Set<String>
    var ambiguousDomains:           Set<String>
    var evaluationInterval:         TimeInterval    // engine tick rate

    var scatterAppsThreshold:       Int             // distinct apps in 5m before scatter state triggers
    var dwellSkimmingThreshold:     TimeInterval    // avg dwell below this = short dwells (used by state inference)
    var recoveryDecayRate:          Double          // accumulator seconds removed per on-task second

    var stuckCyclingAtRisk:         TimeInterval    // seconds in stuckCycling before atRisk
    var noveltySeekingAtRisk:       TimeInterval    // seconds in noveltySeeking before atRisk
    var noveltySeekingDrift:        TimeInterval    // seconds in noveltySeeking before drift
    var passiveDriftAtRisk:         TimeInterval    // seconds in passiveDrift before atRisk
    var passiveDriftDrift:          TimeInterval    // seconds in passiveDrift before drift
    var idleAtRisk:                 TimeInterval    // seconds idle before atRisk
    var scoreDecayWindow:           TimeInterval    // seconds over which score decays from base to floor

    static let defaults = RuleConfig(
        knownBrowsers: ["Google Chrome", "Firefox", "Safari"],
        distractingDomains: [
            "youtube.com", "reddit.com", "twitter.com", "x.com",
            "instagram.com", "tiktok.com", "twitch.tv", "facebook.com",
            "netflix.com", "hulu.com"
        ],
        ambiguousDomains: [
            "github.com", "stackoverflow.com", "docs.swift.org",
            "developer.apple.com", "google.com", "notion.so", "linear.app",
            "chat.openai.com", "claude.ai", "docs.google.com"
        ],
        evaluationInterval:         2,
        scatterAppsThreshold:       3,
        dwellSkimmingThreshold:     8,
        recoveryDecayRate:          3.0,
        stuckCyclingAtRisk:         180,
        noveltySeekingAtRisk:       30,
        noveltySeekingDrift:        90,
        passiveDriftAtRisk:         120,
        passiveDriftDrift:          300,
        idleAtRisk:                 30,
        scoreDecayWindow:           300
    )
}
