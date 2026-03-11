import Foundation

@Observable
final class BehaviorAnalyzer {
    static let shared = BehaviorAnalyzer()

    private(set) var snapshot = BehaviorSnapshot()

    private var lastSeenId:          Int64  = -1
    private var appSwitchTimestamps: [Date] = []
    private var tabSwitchTimestamps: [Date] = []
    private var idlePeriods:         [(start: Date, end: Date)] = []

    private var currentApp:       String = ""
    private var currentDomain:    String = ""
    private var isIdle:           Bool   = false
    private var idleStart:        Date?
    private var contextStartTime: Date   = .now
    private var focusStreakStart: Date?

    private let store:         EventStore
    private let knownBrowsers: Set<String>

    init(store: EventStore = .shared, knownBrowsers: Set<String> = RuleConfig.defaults.knownBrowsers) {
        self.store         = store
        self.knownBrowsers = knownBrowsers
    }

    func update() {
        let newEvents = store.slice(after: lastSeenId)
        if let last = newEvents.last { lastSeenId = last.id }
        processEvents(newEvents)
        buildSnapshot()
    }

    private func processEvents(_ events: [AnchorEvent]) {
        for event in events {
            switch event.type {

            case "active_app":
                let newApp = event.data["appName"] ?? ""
                if newApp != currentApp {
                    appSwitchTimestamps.append(.now)
                    contextStartTime = .now
                    if !isIdle { focusStreakStart = .now }
                    if !knownBrowsers.contains(newApp) { currentDomain = "" }
                }
                currentApp = newApp

            case "browser_domain":
                let domain = event.data["domain"] ?? ""
                if domain != currentDomain {
                    tabSwitchTimestamps.append(.now)
                    contextStartTime = .now
                }
                currentDomain = domain

            case "idle_start":
                isIdle        = true
                idleStart     = .now
                focusStreakStart = nil

            case "idle_end":
                isIdle           = false
                contextStartTime = .now
                focusStreakStart  = .now
                if let start = idleStart {
                    idlePeriods.append((start: start, end: .now))
                    idleStart = nil
                }

            default:
                break
            }
        }

        pruneOld()
    }

    private func pruneOld() {
        let now      = Date()
        let cutoff30 = now.addingTimeInterval(-30)
        let cutoff60 = now.addingTimeInterval(-60)
        let cutoff120 = now.addingTimeInterval(-120)
        appSwitchTimestamps.removeAll { $0 < cutoff30 }
        tabSwitchTimestamps.removeAll { $0 < cutoff60 }
        idlePeriods.removeAll         { $0.end < cutoff120 }
    }

    private func buildSnapshot() {
        let now       = Date()
        let cutoff30  = now.addingTimeInterval(-30)
        let cutoff120 = now.addingTimeInterval(-120)

        var totalIdle: TimeInterval = 0
        for period in idlePeriods {
            let clampedStart = max(period.start, cutoff120)
            if period.end > cutoff120 {
                totalIdle += period.end.timeIntervalSince(clampedStart)
            }
        }
        if isIdle, let start = idleStart {
            totalIdle += now.timeIntervalSince(max(start, cutoff120))
        }

        snapshot = BehaviorSnapshot(
            computedAt:            now,
            currentApp:            currentApp,
            currentDomain:         currentDomain,
            isIdle:                isIdle,
            appSwitchRate30s:      Double(appSwitchTimestamps.count),
            tabSwitchRate30s:      Double(tabSwitchTimestamps.filter { $0 > cutoff30 }.count),
            switchesPerMinute:     Double(tabSwitchTimestamps.count),
            dwellInCurrentContext: now.timeIntervalSince(contextStartTime),
            currentFocusStreak:    focusStreakStart.map { now.timeIntervalSince($0) } ?? 0,
            idleRatio120s:         min(totalIdle / 120.0, 1.0)
        )
    }
}
