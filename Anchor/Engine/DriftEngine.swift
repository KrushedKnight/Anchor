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
    private var currentWorkState:    WorkState    = .idle
    private var workStateEnteredAt:  Date         = .now

    private let bus:                     DecisionBus?
    private let analyzer:                BehaviorAnalyzer
    private let accumulator:             SessionStatsAccumulator
    private var lastPublishedRiskLevel:  RiskLevel?
    private var lastPublishedAt:         Date?
    private var pendingClassifications:  Set<String> = []
    private var distractionPressure:     TimeInterval = 0
    private var onTaskSinceLastDistraction: TimeInterval = 0
    private var sustainedRecoveryStart:  Date?
    private var isRecoverySuppressed:    Bool = false
    private var browserOffTaskDwell:     TimeInterval = 0
    private var lastDomainWasOffTask:    Bool = false

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
        guard !SessionManager.shared.isPaused else { return }

        analyzer.update()
        let snap = analyzer.snapshot

        syncState(from: snap)
        computeContextFit()
        decayAccumulator()
        updateWorkState(snap)
        updateDistractionPressure()
        updateFocusScore(snap)

        state.totalOffTaskDwell  = liveOffTaskDwell(snap)
        state.accumulatorSeconds = offTaskAccumulator
        state.focusStreakSeconds  = snap.currentFocusStreak
        state.lastEvaluatedAt    = .now

        accumulator.record(state: state, interval: config.evaluationInterval)

        print("[DriftEngine] score=\(String(format: "%.2f", focusScore)) risk=\(state.riskLevel) state=\(state.workState.rawValue) (\(Int(state.workStateDuration))s) pressure=\(state.dominantPressureSource) dp=\(Int(distractionPressure))s")
        maybePublish(snap)
    }

    private func syncState(from snap: BehaviorSnapshot) {
        let appChanged    = snap.currentApp != state.currentApp
        let domainChanged = snap.currentDomain != state.currentDomain

        if appChanged || domainChanged {
            let offTaskWeight = 1.0 - state.contextFit
            if offTaskWeight > 0 {
                offTaskAccumulator += state.dwellInCurrentContext * offTaskWeight
            }
        }

        let isBrowser = config.knownBrowsers.contains(snap.currentApp)

        if appChanged && !isBrowser {
            browserOffTaskDwell  = 0
            lastDomainWasOffTask = false
        }

        if isBrowser && domainChanged {
            if lastDomainWasOffTask {
                browserOffTaskDwell += state.dwellInCurrentContext
            }
            lastDomainWasOffTask = state.contextFit < 0.5
        }

        state.currentApp            = snap.currentApp
        state.currentDomain         = snap.currentDomain
        state.isIdle                = snap.isIdle
        state.switchesPerMinute     = snap.switchesPerMinute
        state.dwellInCurrentContext = snap.dwellInCurrentContext
    }

    private func computeContextFit() {
        let currentSessionId = SessionManager.shared.activeSession?.id
        if currentSessionId != lastSessionId {
            offTaskAccumulator     = 0
            focusScore             = 1.0
            pendingLevel           = .stable
            pendingTicks           = 0
            currentWorkState       = .idle
            workStateEnteredAt     = .now
            lastSessionId          = currentSessionId
            pendingClassifications = []
            distractionPressure    = 0
            onTaskSinceLastDistraction = 0
            lastPublishedAt        = nil
            lastPublishedRiskLevel = nil
            sustainedRecoveryStart = nil
            isRecoverySuppressed   = false
            browserOffTaskDwell    = 0
            lastDomainWasOffTask   = false
            accumulator.reset()
            applyProfileTuning()
        }

        guard let session = SessionManager.shared.activeSession else {
            state.sessionActive    = false
            state.sessionTaskTitle = ""
            state.contextFit       = 1.0
            return
        }

        state.sessionActive    = true
        state.sessionTaskTitle = session.taskTitle

        let app    = state.currentApp
        let domain = state.currentDomain
        let task   = session.taskTitle

        guard !app.isEmpty else {
            state.contextFit = 1.0
            return
        }

        let isBrowser = config.knownBrowsers.contains(app)

        if isBrowser && !domain.isEmpty {
            if let level = session.fitForDomain(domain) {
                state.contextFit = level.contextFit
                return
            }

            if let heuristic = ContextHeuristics.heuristicForDomain(domain) {
                state.contextFit = heuristic.contextFit
                lazyClassifyDomain(domain: domain, task: task)
                return
            }
        }

        if let level = session.fitForApp(app) {
            state.contextFit = level.contextFit
            return
        }

        if let heuristic = ContextHeuristics.heuristicForApp(app) {
            state.contextFit = heuristic.contextFit
            lazyClassify(app: app, task: task)
            return
        }

        state.contextFit = 0.55
        lazyClassify(app: app, task: task)
    }

    private func lazyClassify(app: String, task: String) {
        guard !pendingClassifications.contains(app) else { return }
        pendingClassifications.insert(app)

        Task {
            do {
                let level = try await TaskClassifier.shared.classifySingle(task: task, app: app)
                SessionManager.shared.classifyApp(app, as: level)
                print("[DriftEngine] lazy classified '\(app)' → \(level.rawValue)")
            } catch {
                print("[DriftEngine] lazy classify failed for '\(app)': \(error)")
            }
            pendingClassifications.remove(app)
        }
    }

    private func lazyClassifyDomain(domain: String, task: String) {
        let key = "domain:\(domain)"
        guard !pendingClassifications.contains(key) else { return }
        pendingClassifications.insert(key)

        Task {
            do {
                let level = try await TaskClassifier.shared.classifyDomainSingle(task: task, domain: domain)
                SessionManager.shared.classifyDomain(domain, as: level)
                print("[DriftEngine] lazy classified domain '\(domain)' → \(level.rawValue)")
            } catch {
                print("[DriftEngine] lazy classify domain failed for '\(domain)': \(error)")
            }
            pendingClassifications.remove(key)
        }
    }

    private func applyProfileTuning() {
        let profile = UserProfileStore.shared.load()
        config = UserProfileTuner.tunedRuleConfig(from: profile, base: .defaults)
        InterventionEngine.shared.config = UserProfileTuner.tunedInterventionConfig(from: profile)
        print("[DriftEngine] applied profile tuning (sessions=\(profile.totalSessions))")
    }

    private func decayAccumulator() {
        guard !state.isIdle && state.contextFit > 0.7 && offTaskAccumulator > 0 else { return }
        offTaskAccumulator = max(0, offTaskAccumulator - config.recoveryDecayRate * state.contextFit * config.evaluationInterval)
    }

    private func updateDistractionPressure() {
        let isBadState = currentWorkState == .stuckCycling
            || currentWorkState == .noveltySeeking
            || currentWorkState == .passiveDrift

        if isBadState {
            distractionPressure += config.evaluationInterval
            onTaskSinceLastDistraction = 0
        } else if currentWorkState == .deepFocus || currentWorkState == .productiveSwitching {
            onTaskSinceLastDistraction += config.evaluationInterval
            if onTaskSinceLastDistraction >= config.distractionPressureDecay {
                distractionPressure = max(0, distractionPressure - config.evaluationInterval)
            }
        }
    }

    private func updateWorkState(_ snap: BehaviorSnapshot) {
        let inferred = inferWorkState(from: snap, contextFit: state.contextFit)

        if inferred != currentWorkState {
            currentWorkState   = inferred
            workStateEnteredAt = .now
        }

        state.workState         = currentWorkState
        state.workStateDuration = Date.now.timeIntervalSince(workStateEnteredAt)
    }

    private func inferWorkState(from snap: BehaviorSnapshot, contextFit: Double) -> WorkState {
        if snap.isIdle { return .idle }

        let highDwell    = snap.dwellInCurrentContext > config.highDwellThreshold
        let lowSwitching = snap.switchesPerMinute < 3
        let onTask       = contextFit > 0.7
        let offTask      = contextFit < 0.3

        let highScatter  = snap.distinctApps5m >= config.scatterAppsThreshold + 2
        let shortDwells  = averageDwell(snap) < config.dwellSkimmingThreshold

        if highDwell && lowSwitching && onTask {
            return .deepFocus
        }

        if highDwell && lowSwitching && offTask {
            return .passiveDrift
        }

        if snap.isBouncing {
            return .stuckCycling
        }

        if highScatter && shortDwells {
            return .noveltySeeking
        }

        if onTask {
            return .productiveSwitching
        }

        if offTask {
            return shortDwells ? .noveltySeeking : .passiveDrift
        }

        return .productiveSwitching
    }

    private func averageDwell(_ snap: BehaviorSnapshot) -> TimeInterval {
        guard !snap.recentAppDwells.isEmpty else { return snap.dwellInCurrentContext }
        return snap.recentAppDwells.map(\.duration).reduce(0, +) / Double(snap.recentAppDwells.count)
    }

    private func updateFocusScore(_ snap: BehaviorSnapshot) {
        guard state.sessionActive else {
            focusScore = 1.0
            state.focusScore             = 1.0
            state.focusQuality           = 1.0
            state.riskLevel              = .stable
            state.dominantPressureSource = .none
            return
        }

        let ws       = state.workState
        let duration = state.workStateDuration
        let quality  = focusQuality(for: ws, snap: snap)

        state.focusQuality = quality

        let desiredLevel = assessRisk(state: ws, duration: duration)
        state.riskLevel  = applyHysteresis(desired: desiredLevel)

        let target = targetScore(for: ws, duration: duration, quality: quality)
        let diff   = target - focusScore
        if diff < 0 {
            focusScore += max(diff, -0.06)
        } else {
            focusScore += min(diff, 0.06)
        }
        focusScore = max(0.0, min(1.0, focusScore))
        state.focusScore = focusScore

        state.dominantPressureSource = pressureSource(for: ws)
    }

    private func assessRisk(state ws: WorkState, duration: TimeInterval) -> RiskLevel {
        let effectiveDuration = duration + distractionPressure + browserOffTaskDwell

        let compoundMultiplier: Double = {
            let sessionInterventions = SessionStatsAccumulator.shared.interventionCount
            let scoreLow = focusScore < 0.5
            let alreadyWarned = sessionInterventions > 0

            if scoreLow && alreadyWarned {
                return 0.5
            }
            if scoreLow || alreadyWarned {
                return 0.75
            }
            return 1.0
        }()

        switch ws {
        case .deepFocus, .productiveSwitching:
            return .stable

        case .stuckCycling:
            if effectiveDuration >= config.stuckCyclingDrift * compoundMultiplier  { return .drift }
            if effectiveDuration >= config.stuckCyclingAtRisk * compoundMultiplier { return .atRisk }
            return .stable

        case .noveltySeeking:
            if effectiveDuration >= config.noveltySeekingDrift * compoundMultiplier  { return .drift }
            if effectiveDuration >= config.noveltySeekingAtRisk * compoundMultiplier { return .atRisk }
            return .stable

        case .passiveDrift:
            if effectiveDuration >= config.passiveDriftDrift * compoundMultiplier  { return .drift }
            if effectiveDuration >= config.passiveDriftAtRisk * compoundMultiplier { return .atRisk }
            return .stable

        case .idle:
            if duration >= config.idleDrift  { return .drift }
            if duration >= config.idleAtRisk { return .atRisk }
            return .stable
        }
    }

    private func focusQuality(for ws: WorkState, snap: BehaviorSnapshot) -> Double {
        switch ws {
        case .deepFocus:
            let dwellFactor  = min(snap.dwellInCurrentContext / 300.0, 1.0)
            let switchFactor = max(0, 1.0 - snap.switchesPerMinute / 6.0)
            return dwellFactor * 0.5 + switchFactor * 0.5

        case .productiveSwitching:
            let fitFactor    = state.contextFit
            let streakFactor = min(snap.currentFocusStreak / 300.0, 1.0)
            return fitFactor * 0.6 + streakFactor * 0.4

        case .stuckCycling:
            return max(0, 1.0 - snap.switchesPerMinute / 10.0)

        case .noveltySeeking:
            let scatterFactor = max(0, 1.0 - Double(snap.distinctApps5m) / 8.0)
            let dwellFactor   = min(averageDwell(snap) / 30.0, 1.0)
            return scatterFactor * 0.5 + dwellFactor * 0.5

        case .passiveDrift:
            return state.contextFit

        case .idle:
            return 0.5
        }
    }

    private func targetScore(for ws: WorkState, duration: TimeInterval, quality: Double) -> Double {
        let base  = ws.baseTargetScore
        let floor = ws.decayFloor
        guard base > floor, config.scoreDecayWindow > 0 else { return base }
        let timeFactor = min(duration / config.scoreDecayWindow, 1.0)
        let decay      = timeFactor * (1.0 - quality * 0.6)
        return base - (base - floor) * min(decay, 1.0)
    }

    private func pressureSource(for ws: WorkState) -> PressureSource {
        switch ws {
        case .deepFocus, .productiveSwitching: .none
        case .stuckCycling:                    .scatter
        case .noveltySeeking:                  .scatter
        case .passiveDrift:                    .offTaskContext
        case .idle:                            .idleRatio
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
        let required     = gettingWorse ? 1 : (desired == .stable ? 3 : 4)

        return pendingTicks >= required ? desired : state.riskLevel
    }

    private func liveOffTaskDwell(_ snap: BehaviorSnapshot) -> TimeInterval {
        guard state.isOffTaskContext else { return offTaskAccumulator }
        return offTaskAccumulator + snap.dwellInCurrentContext
    }

    private func updateRecoveryWatch() {
        guard lastPublishedAt != nil, state.riskLevel != .stable else {
            sustainedRecoveryStart = nil
            isRecoverySuppressed   = false
            return
        }

        if state.contextFit >= config.recoveryFitThreshold {
            if sustainedRecoveryStart == nil {
                sustainedRecoveryStart = .now
            }
            if let start = sustainedRecoveryStart,
               Date.now.timeIntervalSince(start) >= config.recoveryConfirmationTime {
                isRecoverySuppressed = true
                print("[DriftEngine] recovery confirmed — suppressing republish")
            }
        } else {
            if isRecoverySuppressed {
                print("[DriftEngine] recovery lost — resuming republish")
            }
            sustainedRecoveryStart = nil
            isRecoverySuppressed   = false
        }
    }

    private func maybePublish(_ snap: BehaviorSnapshot) {
        guard let bus else { print("[DriftEngine] maybePublish: no bus, skipping"); return }

        updateRecoveryWatch()

        let levelChanged = state.riskLevel != lastPublishedRiskLevel
        let stillBad = state.riskLevel != .stable
        let timeSincePublish = lastPublishedAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
        let shouldRepublish = stillBad && !isRecoverySuppressed && timeSincePublish >= config.republishInterval

        guard levelChanged || shouldRepublish else { return }

        if levelChanged {
            sustainedRecoveryStart = nil
            isRecoverySuppressed   = false
        }

        print("[DriftEngine] publishing decision: \(state.riskLevel) (changed=\(levelChanged) republish=\(shouldRepublish) suppressed=\(isRecoverySuppressed))")
        lastPublishedRiskLevel = state.riskLevel
        lastPublishedAt = .now

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
