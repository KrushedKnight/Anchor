import Foundation

@Observable
final class DriftEngine {
    static let shared = DriftEngine(bus: .shared)

    private(set) var state = EngineState()
    var config = RuleConfig.defaults

    private var timer:               Timer?
    private var offTaskAccumulator:  TimeInterval = 0
    private var focusScore:          Double       = 1.0
    private var pendingLevel:        RiskLevel    = .stable
    private var pendingTicks:        Int          = 0
    private var lastSessionId:       UUID?

    private let bus:                     DecisionBus?
    private let analyzer:                BehaviorAnalyzer
    private let accumulator:             SessionStatsAccumulator
    private var lastPublishedRiskLevel:  RiskLevel?

    init(bus: DecisionBus? = nil, analyzer: BehaviorAnalyzer = .shared, accumulator: SessionStatsAccumulator = .shared) {
        self.bus         = bus
        self.analyzer    = analyzer
        self.accumulator = accumulator
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
        decayAccumulator()
        updateFocusScore(snap)

        state.totalOffTaskDwell  = liveOffTaskDwell(snap)
        state.accumulatorSeconds = offTaskAccumulator
        state.focusStreakSeconds  = snap.currentFocusStreak
        state.lastEvaluatedAt    = .now

        accumulator.record(state: state, interval: config.evaluationInterval)

        print("[DriftEngine] score=\(String(format: "%.2f", focusScore)) risk=\(state.riskLevel) pressure=\(state.dominantPressureSource)")
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
            offTaskAccumulator = 0
            focusScore         = 1.0
            pendingLevel       = .stable
            pendingTicks       = 0
            lastSessionId      = currentSessionId
            accumulator.reset()
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

    private func decayAccumulator() {
        guard !state.isIdle && !state.isOffTaskContext && offTaskAccumulator > 0 else { return }
        offTaskAccumulator = max(0, offTaskAccumulator - config.recoveryDecayRate * config.evaluationInterval)
    }

    private func updateFocusScore(_ snap: BehaviorSnapshot) {
        guard state.sessionActive else {
            focusScore = 1.0
            state.focusScore             = 1.0
            state.riskLevel              = .stable
            state.dominantPressureSource = .none
            return
        }

        let (target, dominant) = computeTargetScore(snap)

        let diff = target - focusScore
        if diff < 0 {
            focusScore += max(diff, -0.05)
        } else {
            focusScore += min(diff, 0.08)
        }
        focusScore = max(0.0, min(1.0, focusScore))

        let desiredLevel         = levelFromScore(focusScore)
        state.riskLevel          = applyHysteresis(desired: desiredLevel)
        state.focusScore         = focusScore
        state.dominantPressureSource = dominant
    }

    private func computeTargetScore(_ snap: BehaviorSnapshot) -> (Double, PressureSource) {
        let offTaskPressure: Double = state.isOffTaskContext ? 0.8 : 0.0

        let scatterRaw = Double(max(0, snap.distinctApps5m - config.scatterAppsThreshold)) / 4.0
        var scatterPressure = min(scatterRaw, 1.0) * 0.35

        var dwellPressure: Double = 0
        if !snap.recentAppDwells.isEmpty {
            let avgDwell = snap.recentAppDwells.map(\.duration).reduce(0, +) / Double(snap.recentAppDwells.count)
            if avgDwell < config.dwellSkimmingThreshold {
                dwellPressure = 0.25
            } else {
                let ratio = min((avgDwell - config.dwellSkimmingThreshold) / (60.0 - config.dwellSkimmingThreshold), 1.0)
                dwellPressure = (1.0 - ratio) * 0.25
            }
        }

        if snap.isBouncing {
            scatterPressure *= (1.0 - config.bouncingSuppression)
            dwellPressure   *= (1.0 - config.bouncingSuppression)
        }

        let idleExcess   = max(0, snap.idleRatio120s - config.idleRatioPressureFloor)
        let idlePressure = min(idleExcess / config.idleRatioPressureFloor, 1.0) * 0.20

        let accumulatorPressure = min(offTaskAccumulator / config.totalOffTaskDwellThreshold, 1.0) * 0.20

        let streakBonus = min(snap.currentFocusStreak / config.focusStreakBonusWindow, 1.0) * 0.15

        let target = max(0.0, min(1.0,
            1.0
            - offTaskPressure
            - scatterPressure
            - dwellPressure
            - idlePressure
            - accumulatorPressure
            + streakBonus
        ))

        let pressures: [(PressureSource, Double)] = [
            (.offTaskContext, offTaskPressure),
            (.scatter,        scatterPressure),
            (.skimming,       dwellPressure),
            (.idleRatio,      idlePressure),
            (.accumulator,    accumulatorPressure)
        ]
        let top = pressures.max(by: { $0.1 < $1.1 })
        let dominant: PressureSource = (top?.1 ?? 0) > 0.05 ? (top?.0 ?? .none) : .none

        state.pressures = PressureBreakdown(
            offTask:     offTaskPressure,
            scatter:     scatterPressure,
            skimming:    dwellPressure,
            idleRatio:   idlePressure,
            accumulator: accumulatorPressure,
            streakBonus: streakBonus,
            target:      target
        )

        return (target, dominant)
    }

    private func levelFromScore(_ score: Double) -> RiskLevel {
        switch state.riskLevel {
        case .stable:
            return score < config.atRiskEnterThreshold ? .atRisk : .stable
        case .atRisk:
            if score < config.driftEnterThreshold { return .drift }
            if score > config.atRiskExitThreshold { return .stable }
            return .atRisk
        case .drift:
            return score > config.driftExitThreshold ? .atRisk : .drift
        }
    }

    private func applyHysteresis(desired: RiskLevel) -> RiskLevel {
        if desired == state.riskLevel {
            pendingLevel = desired
            pendingTicks = 0
            return state.riskLevel
        }

        if desired == pendingLevel {
            pendingTicks += 1
        } else {
            pendingLevel = desired
            pendingTicks = 1
        }

        let gettingWorse = desired.rawValue > state.riskLevel.rawValue
        let required     = gettingWorse ? 2 : (desired == .stable ? 3 : 4)

        return pendingTicks >= required ? desired : state.riskLevel
    }

    private func liveOffTaskDwell(_ snap: BehaviorSnapshot) -> TimeInterval {
        guard state.isOffTaskContext else { return offTaskAccumulator }
        return offTaskAccumulator + snap.dwellInCurrentContext
    }

    private func maybePublish(_ snap: BehaviorSnapshot) {
        guard let bus else { print("[DriftEngine] maybePublish: no bus, skipping"); return }
        guard state.riskLevel != lastPublishedRiskLevel else { return }

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

        let reason: EngineDecision.Reason = switch state.dominantPressureSource {
            case .offTaskContext: .offTask
            case .scatter, .skimming: .highSwitching
            case .idleRatio: .idle
            case .accumulator: .offTask
            case .none: .unknown
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
