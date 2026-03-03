import Foundation

struct EngineState {
    var riskLevel:               RiskLevel        = .stable
    var currentApp:              String           = ""
    var currentDomain:           String           = ""
    var isIdle:                  Bool             = false
    var switchesPerMinute:       Double           = 0
    var dwellInCurrentContext:   TimeInterval     = 0
    var totalOffTaskDwell:       TimeInterval     = 0
    var lastInterventionTime:    Date?            = nil
    var lastEvaluatedAt:         Date             = .distantPast
}
