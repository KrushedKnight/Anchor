import Foundation

final class InterventionEngine {
    static let shared = InterventionEngine()

    private let decisionBus:     DecisionBus
    private let interventionBus: InterventionBus
    private let config:          InterventionConfig

    private var driftCycleStart: Date?
    private var lastFiredAt:     Date?
    private var currentLevel:    Intervention.Level = .soft

    private var task: Task<Void, Never>?

    init(
        decisionBus:     DecisionBus     = .shared,
        interventionBus: InterventionBus = .shared,
        config:          InterventionConfig = .defaults
    ) {
        self.decisionBus     = decisionBus
        self.interventionBus = interventionBus
        self.config          = config
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
        print("[InterventionEngine] received decision: riskState=\(decision.riskState), type=\(decision.type)")
        if decision.riskState == .stable {
            print("[InterventionEngine] stable → resetCycle")
            resetCycle()
            return
        }

        if decision.type == .none { print("[InterventionEngine] type=.none, skipping"); return }

        if driftCycleStart == nil {
            driftCycleStart = .now
        }

        let cooldown: TimeInterval = currentLevel == .soft ? config.softCooldown : config.strongCooldown
        if let last = lastFiredAt, Date().timeIntervalSince(last) < cooldown {
            print("[InterventionEngine] cooldown active, \(Int(Date().timeIntervalSince(last)))s elapsed of \(Int(cooldown))s")
            return
        }

        if let cycleStart = driftCycleStart,
           Date().timeIntervalSince(cycleStart) >= config.escalationDelay {
            currentLevel = .strong
        }

        let channel: Intervention.Channel = decision.channelHint == .overlay ? .overlay : .notification
        let title = currentLevel == .soft
            ? "Hey, you've drifted"
            : "You've been off-task for a while"

        let intervention = Intervention(
            id:             UUID(),
            ts:             .now,
            level:          currentLevel,
            channel:        channel,
            title:          title,
            body:           buildBody(from: decision),
            actions:        decision.actions,
            sourceDecision: decision
        )

        lastFiredAt = .now
        print("[InterventionEngine] firing intervention: level=\(currentLevel), title=\(intervention.title), channel=\(intervention.channel)")
        interventionBus.publish(intervention)
    }

    private func buildBody(from decision: EngineDecision) -> String {
        var parts: [String] = []

        if let task = decision.task, !task.name.isEmpty {
            parts.append("Task: \(task.name)")
        }

        if let context = decision.context, let label = context.label, !label.isEmpty {
            parts.append(label)
        }

        if let metrics = decision.metrics, metrics.offContextSeconds > 0 {
            parts.append("\(Int(metrics.offContextSeconds))s off-task")
        }

        return parts.joined(separator: " · ")
    }

    private func resetCycle() {
        driftCycleStart = nil
        lastFiredAt     = nil
        currentLevel    = .soft
    }
}
