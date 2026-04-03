import Foundation

enum PressureSource {
    case none, offTaskContext, scatter, skimming, idleRatio, accumulator
}

struct PressureBreakdown {
    var offTask:     Double = 0
    var scatter:     Double = 0
    var skimming:    Double = 0
    var idleRatio:   Double = 0
    var accumulator: Double = 0
    var streakBonus: Double = 0
    var target:      Double = 1
}

struct EngineState {
    var riskLevel:              RiskLevel       = .stable
    var currentApp:             String          = ""
    var currentDomain:          String          = ""
    var isIdle:                 Bool            = false
    var switchesPerMinute:      Double          = 0
    var dwellInCurrentContext:  TimeInterval    = 0
    var totalOffTaskDwell:      TimeInterval    = 0
    var lastInterventionTime:   Date?           = nil
    var lastEvaluatedAt:        Date            = .distantPast
    var sessionActive:          Bool            = false
    var sessionTaskTitle:       String          = ""
    var contextFit:             Double          = 1.0
    var isOffTaskContext:       Bool            { contextFit < 0.5 }
    var focusScore:             Double          = 1.0
    var focusStreakSeconds:     TimeInterval    = 0
    var accumulatorSeconds:     TimeInterval    = 0
    var dominantPressureSource: PressureSource  = .none
    var pressures:              PressureBreakdown = .init()
    var workState:              WorkState       = .idle
    var workStateDuration:      TimeInterval    = 0
}
