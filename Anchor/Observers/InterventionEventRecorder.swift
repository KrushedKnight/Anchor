import Foundation

final class InterventionEventRecorder {
    private var subscriptionId: UUID?
    private var task: Task<Void, Never>?

    func start() {
        let (id, stream) = InterventionBus.shared.subscribe()
        subscriptionId = id
        task = Task { @MainActor in
            for await intervention in stream {
                record(intervention)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let id = subscriptionId {
            InterventionBus.shared.unsubscribe(id)
            subscriptionId = nil
        }
    }

    private func record(_ intervention: Intervention) {
        let sessionId = SessionManager.shared.activeSession?.id.uuidString ?? ""
        let level = switch intervention.level {
            case .soft:   "soft"
            case .strong: "strong"
        }
        let triggeringState = switch intervention.sourceDecision.riskState {
            case .stable: "stable"
            case .atRisk: "at_risk"
            case .drift:  "drift"
        }

        EventStore.shared.append(
            type: "intervention_shown",
            data: [
                "session_id":        sessionId,
                "intervention_id":   intervention.id.uuidString,
                "intervention_level": level,
                "triggering_state":  triggeringState
            ]
        )
    }
}
