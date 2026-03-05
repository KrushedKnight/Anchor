import Foundation

struct InterventionConfig {
    var softCooldown:    TimeInterval = 180
    var strongCooldown:  TimeInterval = 600
    var escalationDelay: TimeInterval = 300

    static let defaults = InterventionConfig()
}
