import Foundation

struct Intervention {
    enum Level   { case soft, strong }
    enum Channel { case notification, overlay }

    var id:             UUID
    var ts:             Date
    var level:          Level
    var channel:        Channel
    var title:          String
    var body:           String
    var actions:        [EngineDecision.Action]
    var sourceDecision: EngineDecision
}
