import Foundation

@Observable
final class DriftEngine {
    static let shared = DriftEngine(bus: .shared)

    private(set) var state = EngineState()
    var config = RuleConfig.defaults

    private var timer:               Timer?
    private var offTaskAccumulator:  TimeInterval = 0
    private var highSwitchRateStart: Date?
    private var recoveryStart:       Date?
    private var lastOffTaskContext:  Bool = false
    private var lastSessionId:       UUID?

    private let bus:                     DecisionBus?
    private let analyzer:                BehaviorAnalyzer
    private var lastPublishedRiskLevel:  RiskLevel?

    init(bus: DecisionBus? = nil, analyzer: BehaviorAnalyzer = .shared) {
        self.bus      = bus
        self.analyzer = analyzer
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
        analyzer.update()
        let snap = analyzer.snapshot

        syncState(from: snap)
        classifyOffTask()
        accumulateAndRecover()
        state.riskLevel         = evaluate(snap)
        state.totalOffTaskDwell = liveOffTaskDwell(snap)
        state.lastEvaluatedAt   = .now
        print("[DriftEngine] tick → riskLevel=\(state.riskLevel), offTask=\(state.isOffTaskContext), app=\(state.currentApp), domain=\(state.currentDomain)")
        maybePublish(snap)
    }

    private func syncState(from snap: BehaviorSnapshot) {
        if snap.currentApp != state.currentApp || snap.currentDomain != state.currentDomain {
            if state.isOffTaskContext {
                offTaskAccumulator += state.dwellInCurrentContext
            }
        }
        state.currentApp            = snap.currentApp
        state.currentDomain         = snap.currentDomain
        state.isIdle                = snap.isIdle
        state.switchesPerMinute     = snap.switchesPerMinute
        state.dwellInCurrentContext = snap.dwellInCurrentContext
    }

    private func classifyOffTask() {
        let currentSessionId = SessionManager.shared.activeSession?.id
        if currentSessionId != lastSessionId {
            offTaskAccumulator     = 0
            recoveryStart          = nil
            state.recoveryProgress = 0
            lastSessionId          = currentSessionId
        }

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

    private func accumulateAndRecover() {
        guard !state.isIdle else { return }

        if state.isOffTaskContext {
            recoveryStart          = nil
            state.recoveryProgress = 0
        } else {
            if recoveryStart == nil { recoveryStart = .now }
            let elapsed = Date().timeIntervalSince(recoveryStart!)
            if elapsed >= config.recoveryWindow {
                offTaskAccumulator = 0
                recoveryStart      = nil
                state.recoveryProgress = 0
                print("[DriftEngine] recovery complete, accumulator reset")
            } else {
                state.recoveryProgress = elapsed / config.recoveryWindow
            }
        }
    }

    private func liveOffTaskDwell(_ snap: BehaviorSnapshot) -> TimeInterval {
        guard state.isOffTaskContext else { return offTaskAccumulator }
        return offTaskAccumulator + snap.dwellInCurrentContext
    }

    private func evaluate(_ snap: BehaviorSnapshot) -> RiskLevel {
        guard SessionManager.shared.isActive else { return .stable }

        var level: RiskLevel = .stable

        if snap.isIdle && !snap.currentApp.isEmpty {
            level = max(level, .atRisk)
        }

        if snap.switchesPerMinute >= config.switchRateThreshold {
            if highSwitchRateStart == nil { highSwitchRateStart = .now }
            let sustained = Date().timeIntervalSince(highSwitchRateStart!)
            if sustained >= config.switchRateSustainedWindow {
                level = max(level, .atRisk)
            }
        } else {
            highSwitchRateStart = nil
        }

        if state.isOffTaskContext && snap.dwellInCurrentContext >= config.distractingDwellThreshold {
            level = max(level, .drift)
        }

        if liveOffTaskDwell(snap) >= config.totalOffTaskDwellThreshold {
            level = max(level, .drift)
        }

        return level
    }

    private func maybePublish(_ snap: BehaviorSnapshot) {
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
            case .atRisk: snap.isIdle ? .idle : .highSwitching
            case .drift:  .offTask
        }

        let task: EngineDecision.TaskSnapshot? = SessionManager.shared.activeSession.map {
            .init(id: $0.id.uuidString, name: $0.taskTitle)
        }

        let ctx: EngineDecision.ContextSnapshot? = {
            if !snap.currentDomain.isEmpty {
                return .init(key: "domain:\(snap.currentDomain)", label: snap.currentDomain)
            } else if !snap.currentApp.isEmpty {
                return .init(key: "app:\(snap.currentApp)", label: snap.currentApp)
            }
            return nil
        }()

        let metrics = EngineDecision.MetricsSnapshot(
            switchesPerMin:             snap.switchesPerMinute,
            offContextSeconds:          liveOffTaskDwell(snap),
            idleSeconds:                0,
            currentContextDwellSeconds: snap.dwellInCurrentContext
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
            task:        task,
            context:     ctx,
            metrics:     metrics,
            actions:     [.return, .snooze5m, .dismiss],
            channelHint: severity == .high ? .overlay : .notification
        )

        bus.publish(decision)
    }
}
