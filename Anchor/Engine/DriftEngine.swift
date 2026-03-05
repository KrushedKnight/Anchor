import Foundation

@Observable
final class DriftEngine {
    static let shared = DriftEngine(bus: .shared)

    private(set) var state = EngineState()
    var config = RuleConfig.defaults

    private var lastSeenId:            Int64  = -1
    private var timer:                 Timer?

    private var switchTimestamps:      [Date] = []

    private var contextStartTime:      Date   = .now
    private var offTaskAccumulator:    TimeInterval = 0
    private var highSwitchRateStart:   Date?
    private var recoveryStart:         Date?

    private let bus:                   DecisionBus?
    private var lastPublishedRiskLevel: RiskLevel?

    init(bus: DecisionBus? = nil) {
        self.bus = bus
    }

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
        classifyOffTask()
        state.riskLevel         = evaluate()
        state.totalOffTaskDwell = liveOffTaskDwell
        state.lastEvaluatedAt   = .now
        print("[DriftEngine] tick → riskLevel=\(state.riskLevel), offTask=\(state.isOffTaskContext), app=\(state.currentApp), domain=\(state.currentDomain)")
        maybePublish()
    }

    private func classifyOffTask() {
        guard let session = SessionManager.shared.activeSession else {
            state.sessionActive    = false
            state.sessionTaskTitle = ""
            state.isOffTaskContext = false
            return
        }

        state.sessionActive    = true
        state.sessionTaskTitle = session.taskTitle

        let app = state.currentApp

        if session.blockedApps.contains(app) {
            state.isOffTaskContext = true
            return
        }

        switch session.strictness {
        case .normal:
            state.isOffTaskContext = false
        case .strict:
            state.isOffTaskContext = !session.allowedApps.isEmpty && !session.allowedApps.contains(app)
        }
    }

    private func process(_ events: [AnchorEvent]) {
        for event in events {
            switch event.type {

            case "active_app":
                let newApp = event.data["appName"] ?? ""
                if !config.knownBrowsers.contains(newApp) && !state.currentDomain.isEmpty {
                    accumulateOffTask()
                    state.currentDomain = ""
                    print("[DriftEngine] domain cleared, recovery started")
                }
                state.currentApp = newApp
                contextStartTime = .now

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
        state.switchesPerMinute     = Double(switchTimestamps.count)
        state.dwellInCurrentContext = Date().timeIntervalSince(contextStartTime)
    }

    private var liveOffTaskDwell: TimeInterval {
        guard config.distractingDomains.contains(state.currentDomain) else { return offTaskAccumulator }
        return offTaskAccumulator + Date().timeIntervalSince(contextStartTime)
    }

    private func accumulateOffTask() {
        guard config.distractingDomains.contains(state.currentDomain) else { return }
        offTaskAccumulator += Date().timeIntervalSince(contextStartTime)
    }

    private func pruneOldSwitches() {
        let cutoff = Date().addingTimeInterval(-60)
        switchTimestamps.removeAll { $0 < cutoff }
    }

    private func evaluate() -> RiskLevel {
        var level: RiskLevel = .stable

        if state.isIdle && !state.currentApp.isEmpty {
            level = max(level, .atRisk)
        }

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

        if config.distractingDomains.contains(state.currentDomain),
           state.dwellInCurrentContext >= config.distractingDwellThreshold {
            level = max(level, .drift)
        }

        if liveOffTaskDwell >= config.totalOffTaskDwellThreshold {
            level = max(level, .drift)
        }

        if !state.isIdle {
            let onDistractingContext = config.distractingDomains.contains(state.currentDomain)
            if onDistractingContext {
                recoveryStart = nil
                state.recoveryProgress = 0
            } else {
                if recoveryStart == nil { recoveryStart = .now }
                let elapsed = Date().timeIntervalSince(recoveryStart!)
                if elapsed >= config.recoveryWindow {
                    offTaskAccumulator = 0
                    recoveryStart = nil
                    state.recoveryProgress = 0
                    print("[DriftEngine] recovery complete, accumulator reset")
                } else {
                    state.recoveryProgress = elapsed / config.recoveryWindow
                }
            }
        }

        return level
    }

    private func maybePublish() {
        guard let bus else { print("[DriftEngine] maybePublish: no bus, skipping"); return }
        if state.riskLevel == .stable && lastPublishedRiskLevel == .stable { return }
        print("[DriftEngine] publishing decision: \(state.riskLevel)")
        lastPublishedRiskLevel = state.riskLevel

        let severity: EngineDecision.Severity = switch state.riskLevel {
            case .stable: .low
            case .atRisk: .medium
            case .drift:  .high
        }

        let riskState: EngineDecision.RiskState = switch state.riskLevel {
            case .stable: .stable
            case .atRisk: .atRisk
            case .drift:  .drift
        }

        let reason: EngineDecision.Reason = switch state.riskLevel {
            case .stable: .unknown
            case .atRisk: state.isIdle ? .idle : .highSwitching
            case .drift:  .offContextDwell
        }

        let ctx: EngineDecision.ContextSnapshot? = {
            if !state.currentDomain.isEmpty {
                return .init(key: "domain:\(state.currentDomain)", label: state.currentDomain)
            } else if !state.currentApp.isEmpty {
                return .init(key: "app:\(state.currentApp)", label: state.currentApp)
            }
            return nil
        }()

        let metrics = EngineDecision.MetricsSnapshot(
            switchesPerMin:             state.switchesPerMinute,
            offContextSeconds:          liveOffTaskDwell,
            idleSeconds:                0,
            currentContextDwellSeconds: state.dwellInCurrentContext
        )

        let decisionType: EngineDecision.DecisionType = switch state.riskLevel {
            case .stable: .none
            case .atRisk: .nudge
            case .drift:  .escalate
        }

        let decision = EngineDecision(
            id:          0,
            ts:          0,
            type:        decisionType,
            severity:    severity,
            reason:      reason,
            riskState:   riskState,
            task:        nil,
            context:     ctx,
            metrics:     metrics,
            actions:     [.return, .snooze5m, .dismiss],
            channelHint: severity == .high ? .overlay : .notification
        )

        bus.publish(decision)
    }
}
