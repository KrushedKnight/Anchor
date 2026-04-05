import Foundation

@Observable
final class PomodoroTimer {
    let config: PomodoroConfig

    private(set) var phase: PomodoroPhase = .work
    private(set) var phaseElapsed: TimeInterval = 0
    private(set) var completedCycles: Int = 0
    private(set) var isWaitingForUser: Bool = false

    private var timer: Timer?

    var phaseDuration: TimeInterval {
        switch phase {
        case .work:       config.workDuration
        case .shortBreak: config.shortBreakDuration
        case .longBreak:  config.longBreakDuration
        }
    }

    var phaseRemaining: TimeInterval {
        max(0, phaseDuration - phaseElapsed)
    }

    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, phaseElapsed / phaseDuration)
    }

    init(config: PomodoroConfig) {
        self.config = config
    }

    func start() {
        phase = .work
        phaseElapsed = 0
        completedCycles = 0
        isWaitingForUser = false
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func advancePhase() {
        isWaitingForUser = false
        phaseElapsed = 0

        if phase == .work {
            completedCycles += 1
            let isLongBreak = completedCycles > 0
                && completedCycles % config.cyclesBeforeLongBreak == 0
            phase = isLongBreak ? .longBreak : .shortBreak
            SessionManager.shared.pause(reason: "pomodoro_break")
        } else {
            phase = .work
            SessionManager.shared.resume()
        }

        startTimer()
    }

    func skipBreak() {
        guard phase.isBreak else { return }
        isWaitingForUser = false
        phaseElapsed = 0
        phase = .work
        SessionManager.shared.resume()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    private func timerTick() {
        guard !isWaitingForUser else { return }
        phaseElapsed += 1

        if phaseElapsed >= phaseDuration {
            phaseExpired()
        }
    }

    private func phaseExpired() {
        timer?.invalidate()
        timer = nil
        isWaitingForUser = true
        print("[PomodoroTimer] phase \(phase.rawValue) expired — waiting for user (cycle \(completedCycles))")
    }
}
