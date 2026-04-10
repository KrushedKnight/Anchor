import Foundation

struct InterventionConfig {
    var ambientCooldown:       TimeInterval = 10
    var softCooldown:          TimeInterval = 15
    var strongCooldown:        TimeInterval = 20
    var ambientToSoftDelay:    TimeInterval = 12
    var softToStrongDelay:     TimeInterval = 20
    var assertiveDisplayTime:  TimeInterval = 10

    static let defaults = InterventionConfig()
}
