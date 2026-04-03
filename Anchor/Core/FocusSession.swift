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

struct FocusSession {
    var id:             UUID         = UUID()
    var startedAt:      Date         = .now
    var taskTitle:      String

    var appClassifications: [String: ContextFitLevel] = [:]

    func fitForApp(_ app: String) -> ContextFitLevel? {
        appClassifications[app]
    }

    mutating func classifyApp(_ app: String, as level: ContextFitLevel) {
        appClassifications[app] = level
    }
}
