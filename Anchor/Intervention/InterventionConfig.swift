import Foundation

struct InterventionConfig {
    var softCooldown:    TimeInterval = 10
    var strongCooldown:  TimeInterval = 20
    var escalationDelay: TimeInterval = 15

    static let defaults = InterventionConfig()
}
