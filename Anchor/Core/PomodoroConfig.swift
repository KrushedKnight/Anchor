import Foundation

struct PomodoroConfig {
    var workDuration: TimeInterval       = 25 * 60
    var shortBreakDuration: TimeInterval = 5 * 60
    var longBreakDuration: TimeInterval  = 15 * 60
    var cyclesBeforeLongBreak: Int       = 4
}

enum PomodoroPhase: String {
    case work       = "Work"
    case shortBreak = "Short Break"
    case longBreak  = "Long Break"

    var isBreak: Bool {
        self != .work
    }
}
