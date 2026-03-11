import Foundation

struct BehaviorSnapshot {
    var computedAt:            Date                                   = .distantPast
    var currentApp:            String                                 = ""
    var currentDomain:         String                                 = ""
    var isIdle:                Bool                                   = false
    var appSwitchRate30s:      Double                                 = 0
    var tabSwitchRate30s:      Double                                 = 0
    var switchesPerMinute:     Double                                 = 0
    var distinctApps5m:        Int                                    = 0
    var isBouncing:            Bool                                   = false
    var recentAppDwells:       [(app: String, duration: TimeInterval)] = []
    var dwellInCurrentContext: TimeInterval                           = 0
    var currentFocusStreak:    TimeInterval                           = 0
    var idleRatio120s:         Double                                 = 0
}
