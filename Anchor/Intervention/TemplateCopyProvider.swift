import Foundation

struct TemplateCopyProvider: NudgeCopyProviding {

    func copy(decision: EngineDecision, level: Intervention.Level) -> NudgeCopy {
        let task     = decision.task?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let context  = decision.context?.label ?? ""
        let seconds  = decision.metrics?.offContextSeconds ?? 0
        let switches = Int(decision.metrics?.switchesPerMin ?? 0)

        return NudgeCopy(
            title: makeTitle(reason: decision.reason, level: level, task: task, context: context),
            body:  makeBody(reason: decision.reason, level: level, task: task, context: context, seconds: seconds, switches: switches)
        )
    }

    // MARK: - Title

    private func makeTitle(
        reason:  EngineDecision.Reason,
        level:   Intervention.Level,
        task:    String,
        context: String
    ) -> String {
        switch (reason, level) {

        case (.offTask, .soft):
            return task.isEmpty
                ? pick(["Getting sidetracked?", "Losing focus?", "Drift check."])
                : "Back to \(task)?"

        case (.offTask, .strong):
            return context.isEmpty
                ? "You've been off-task for a while"
                : "Still on \(context)?"

        case (.highSwitching, .soft):
            return pick(["Spreading thin?", "Lots of switching.", "Staying scattered?"])

        case (.highSwitching, .strong):
            return "You've been scattered for a while"

        case (.idle, .soft):
            return pick(["Still there?", "Taking a break?", "Zoned out?"])

        case (.idle, .strong):
            return "Long break — still with it?"

        default:
            return level == .soft ? "Focus check." : "You've drifted"
        }
    }

    // MARK: - Body

    private func makeBody(
        reason:   EngineDecision.Reason,
        level:    Intervention.Level,
        task:     String,
        context:  String,
        seconds:  Double,
        switches: Int
    ) -> String {
        let timeStr = seconds > 0 ? formatDuration(seconds) : nil
        let hasTask = !task.isEmpty
        let hasCtx  = !context.isEmpty

        switch reason {

        case .offTask:
            if hasTask && hasCtx, let t = timeStr {
                return "You've been on \(context) for \(t). \(task) is waiting."
            } else if hasTask, let t = timeStr {
                return "You've been away from \(task) for \(t)."
            } else if hasCtx, let t = timeStr {
                return "You've spent \(t) on \(context)."
            } else if hasTask {
                return "\(task) is still waiting."
            }
            return "You've drifted from what you were working on."

        case .highSwitching:
            if hasTask && switches > 0 {
                return "You've switched apps \(switches) times this minute. \(task) needs your focus."
            } else if hasTask {
                return "Lots of context switching. \(task) needs your focus."
            }
            return "Lots of context switching — try picking one thing and sticking with it."

        case .idle:
            if hasTask, let t = timeStr {
                return "Idle for \(t). Ready to get back to \(task)?"
            } else if let t = timeStr {
                return "You've been idle for \(t)."
            }
            return "Looks like you've gone idle."

        default:
            if hasTask, let t = timeStr {
                return "You've been off track for \(t). \(task) is still open."
            }
            return "Your focus has drifted."
        }
    }

    // MARK: - Helpers

    private func pick(_ options: [String]) -> String {
        options[Int.random(in: 0..<options.count)]
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return s == 1 ? "1 second" : "\(s) seconds" }
        let m = s / 60
        return m == 1 ? "1 minute" : "\(m) minutes"
    }
}
