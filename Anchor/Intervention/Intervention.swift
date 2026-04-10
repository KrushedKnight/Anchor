import Foundation

struct Intervention {
    enum Level: Int, Comparable {
        case ambient = 0, soft = 1, strong = 2
        static func < (l: Level, r: Level) -> Bool { l.rawValue < r.rawValue }
    }
    enum Channel { case widget, notification, overlay }

    var id:             UUID
    var ts:             Date
    var level:          Level
    var channel:        Channel
    var title:          String
    var body:           String
    var actions:        [EngineDecision.Action]
    var sourceDecision: EngineDecision
}
