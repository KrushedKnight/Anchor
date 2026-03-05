import Foundation

struct EngineDecision: Identifiable {
    enum DecisionType   { case none, nudge, escalate }
    enum Severity: Int, Comparable {
        case low = 0, medium = 1, high = 2
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
    }
    enum Reason         { case offContextDwell, offTask, highSwitching, idle, unknown }
    enum RiskState      { case stable, atRisk, drift }
    enum Action         { case `return`, snooze5m, endSession, dismiss }
    enum ChannelHint    { case notification, overlay, either }

    struct TaskSnapshot {
        var id:   String
        var name: String
    }

    struct ContextSnapshot {
        var key:   String
        var label: String?
    }

    struct MetricsSnapshot {
        var switchesPerMin:              Double
        var offContextSeconds:           Double
        var idleSeconds:                 Double
        var currentContextDwellSeconds:  Double
    }

    var id:       Int64
    var ts:       Double
    var type:     DecisionType
    var severity: Severity
    var reason:   Reason
    var riskState: RiskState

    var task:     TaskSnapshot?
    var context:  ContextSnapshot?
    var metrics:  MetricsSnapshot?

    var actions:     [Action]
    var channelHint: ChannelHint
}
