import Foundation

final class InterventionEngine {
    static let shared = InterventionEngine()

    private let decisionBus:     DecisionBus
    private let interventionBus: InterventionBus
    var config:                  InterventionConfig
    private let copyProvider:    NudgeCopyProviding

    private var driftCycleStart: Date?
    private var lastFiredAt:     [Intervention.Level: Date] = [:]
    private var currentLevel:    Intervention.Level = .ambient

    private var task: Task<Void, Never>?

    init(
        decisionBus:     DecisionBus        = .shared,
        interventionBus: InterventionBus    = .shared,
        config:          InterventionConfig = .defaults,
        copyProvider:    NudgeCopyProviding = TemplateCopyProvider()
    ) {
        self.decisionBus     = decisionBus
        self.interventionBus = interventionBus
        self.config          = config
        self.copyProvider    = copyProvider
    }

    func start() {
        task = Task { @MainActor in
            for await decision in decisionBus.stream {
                handle(decision)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func handle(_ decision: EngineDecision) {
        if decision.riskState == .stable {
            resetCycle()
            return
        }

        if decision.type == .none { return }

        let now = Date.now

        if driftCycleStart == nil {
            driftCycleStart = now
        }

        let elapsed = now.timeIntervalSince(driftCycleStart!)
        currentLevel = resolveLevel(elapsed: elapsed)

        let cooldown = cooldownFor(currentLevel)
        if let last = lastFiredAt[currentLevel], now.timeIntervalSince(last) < cooldown {
            return
        }

        let channel: Intervention.Channel = currentLevel == .strong ? .notification : .widget
        let copy = copyProvider.copy(decision: decision, level: currentLevel)

        let intervention = Intervention(
            id:             UUID(),
            ts:             now,
            level:          currentLevel,
            channel:        channel,
            title:          copy.title,
            body:           copy.body,
            actions:        decision.actions,
            sourceDecision: decision
        )

        lastFiredAt[currentLevel] = now
        SessionStatsAccumulator.shared.recordIntervention(level: currentLevel)
        interventionBus.publish(intervention)
    }

    private func resolveLevel(elapsed: TimeInterval) -> Intervention.Level {
        if elapsed >= config.ambientToSoftDelay + config.softToStrongDelay {
            return .strong
        } else if elapsed >= config.ambientToSoftDelay {
            return .soft
        }
        return .ambient
    }

    private func cooldownFor(_ level: Intervention.Level) -> TimeInterval {
        switch level {
        case .ambient: config.ambientCooldown
        case .soft:    config.softCooldown
        case .strong:  config.strongCooldown
        }
    }

    private func resetCycle() {
        driftCycleStart = nil
        lastFiredAt     = [:]
        currentLevel    = .ambient
    }
}
