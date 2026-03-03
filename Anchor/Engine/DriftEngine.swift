import Foundation

@Observable
final class DriftEngine {
    static let shared = DriftEngine()

    private(set) var state = EngineState()
    var config = RuleConfig.defaults

    private var lastSeenId:          Int64  = -1
    private var timer:               Timer?

    // switch-rate tracking
    private var switchTimestamps:    [Date] = []

    // dwell tracking
    private var contextStartTime:    Date   = .now
    private var offTaskAccumulator:  TimeInterval = 0
    private var highSwitchRateStart: Date?

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: config.evaluationInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let newEvents = EventStore.shared.slice(after: lastSeenId)
        if let last = newEvents.last { lastSeenId = last.id }
        process(newEvents)
        state.riskLevel         = evaluate()
        state.lastEvaluatedAt   = .now
    }

    private func process(_ events: [AnchorEvent]) {
        for event in events {
            switch event.type {

            case "active_app":
                state.currentApp    = event.data["appName"] ?? ""
                contextStartTime    = .now

            case "browser_domain":
                let domain = event.data["domain"] ?? ""
                if domain != state.currentDomain {
                    accumulateOffTask()
                    state.currentDomain = domain
                    contextStartTime    = .now
                }
                switchTimestamps.append(.now)

            case "idle_start":
                state.isIdle = true

            case "idle_end":
                state.isIdle = false
                contextStartTime = .now

            default:
                break
            }
        }

        pruneOldSwitches()
        state.switchesPerMinute    = Double(switchTimestamps.count)
        state.dwellInCurrentContext = Date().timeIntervalSince(contextStartTime)
    }

    private func accumulateOffTask() {
        guard config.distractingDomains.contains(state.currentDomain) else { return }
        offTaskAccumulator += Date().timeIntervalSince(contextStartTime)
        state.totalOffTaskDwell = offTaskAccumulator
    }

    private func pruneOldSwitches() {
        let cutoff = Date().addingTimeInterval(-60)
        switchTimestamps.removeAll { $0 < cutoff }
    }

    private func evaluate() -> RiskLevel {
        var level: RiskLevel = .stable

        // Rule 1 — idle during an active (non-empty) session
        if state.isIdle && !state.currentApp.isEmpty {
            level = max(level, .atRisk)
        }

        // Rule 2 — high tab-switch rate sustained for the configured window
        let switchRate = state.switchesPerMinute
        if switchRate >= config.switchRateThreshold {
            if highSwitchRateStart == nil { highSwitchRateStart = .now }
            let sustained = Date().timeIntervalSince(highSwitchRateStart!)
            if sustained >= config.switchRateSustainedWindow {
                level = max(level, .atRisk)
            }
        } else {
            highSwitchRateStart = nil
        }

        // Rule 3 — dwelling on a distracting domain too long
        if config.distractingDomains.contains(state.currentDomain),
           state.dwellInCurrentContext >= config.distractingDwellThreshold {
            level = max(level, .drift)
        }

        // Rule 4 — total off-task dwell exceeds threshold
        accumulateOffTask()
        if state.totalOffTaskDwell >= config.totalOffTaskDwellThreshold {
            level = max(level, .drift)
        }

        return level
    }
}
