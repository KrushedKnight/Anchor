import Foundation

struct NudgeCopy {
    var title: String
    var body:  String
}

protocol NudgeCopyProviding {
    func copy(decision: EngineDecision, level: Intervention.Level) -> NudgeCopy
}
