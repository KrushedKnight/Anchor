import Foundation

enum ContextFitLevel: String {
    case onTask    = "on_task"
    case ambiguous = "ambiguous"
    case offTask   = "off_task"

    var contextFit: Double {
        switch self {
        case .onTask:    1.0
        case .ambiguous: 0.55
        case .offTask:   0.15
        }
    }
}

enum DistractionPriority: String {
    case low    = "low"       // Lenient; task allows flexibility
    case normal = "normal"    // Standard thresholds
    case high   = "high"      // Aggressive; minimize any drift
}

struct TaskProfile {
    var switchingMultiplier: Double = 1.0          // 0.5–1.5; adjusts expected switching rate
    var distractionPriority: DistractionPriority = .normal
}

struct FocusSession {
    var id:             UUID         = UUID()
    var startedAt:      Date         = .now
    var taskTitle:      String
    var taskProfile:    TaskProfile  = .init()

    var appClassifications:    [String: ContextFitLevel] = [:]
    var domainClassifications: [String: ContextFitLevel] = [:]

    func fitForApp(_ app: String) -> ContextFitLevel? {
        appClassifications[app]
    }

    mutating func classifyApp(_ app: String, as level: ContextFitLevel) {
        appClassifications[app] = level
    }

    func fitForDomain(_ domain: String) -> ContextFitLevel? {
        domainClassifications[domain]
    }

    mutating func classifyDomain(_ domain: String, as level: ContextFitLevel) {
        domainClassifications[domain] = level
    }
}
