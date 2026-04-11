import SwiftUI

struct SessionSummaryView: View {
    var summary: SessionSummary
    @State private var note: String = ""
    @State private var showDetails: Bool = false

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            headline
            focusBar
                .padding(.horizontal, 24)
            noteSection
                .padding(.horizontal, 24)
            actionButtons
                .padding(.horizontal, 24)
            DisclosureGroup(isExpanded: $showDetails) {
                detailsContent
                    .padding(.top, 8)
            } label: {
                Text("Details")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: showDetails)
        }
        .padding(.vertical, 20)
        .frame(width: 600)
        .frame(minHeight: 350)
        .onAppear { note = summary.note }
    }

    private func saveAndDismiss() {
        var updated = summary
        updated.note = note
        SessionSummaryStore.shared.save(updated)
        SessionManager.shared.dismissSummary()
    }

    private var headline: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Session Complete")
                .font(.system(.caption))
                .foregroundStyle(Color.anchorTextMuted)
            Text(summary.taskTitle.isEmpty ? "Untitled session" : summary.taskTitle)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Color.anchorText)
            Text(String(format: "%.0f%%", summary.focusScoreAvg * 100))
                .font(.system(size: 48, weight: .heavy, design: .serif))
                .foregroundStyle(scoreColor)
            Text(oneLinerSummary)
                .font(.system(.caption))
                .foregroundStyle(Color.anchorTextMuted)
        }
    }

    private var oneLinerSummary: String {
        let focused = formatDuration(summary.timeStable)
        let drifted = formatDuration(summary.timeDrift)
        let interventions = summary.interventionCount
        let intLabel = interventions == 1 ? "1 intervention" : "\(interventions) interventions"
        return "\(focused) focused · \(drifted) drifted · \(intLabel)"
    }

    private var focusBar: some View {
        let total = summary.timeStable + summary.timeAtRisk + summary.timeDrift
        let stableFrac = total > 0 ? summary.timeStable / total : 0
        let atRiskFrac = total > 0 ? summary.timeAtRisk / total : 0

        return GeometryReader { geo in
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.anchorSage.opacity(0.8))
                    .frame(width: geo.size.width * stableFrac)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.anchorAmber.opacity(0.8))
                    .frame(width: geo.size.width * atRiskFrac)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.anchorRed.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .cornerRadius(4)
    }

    private var noteSection: some View {
        TextEditor(text: $note)
            .font(.system(.caption))
            .scrollContentBackground(.hidden)
            .background(Color.anchorSand)
            .cornerRadius(6)
            .frame(minHeight: 60, maxHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.anchorTextMuted.opacity(0.2), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text("What went well? What derailed you?")
                        .font(.system(.caption))
                        .foregroundStyle(Color.anchorTextMuted.opacity(0.5))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .tint(Color.anchorTerracotta)
    }

    private var actionButtons: some View {
        Button("Start Fresh") { saveAndDismiss() }
            .buttonStyle(AnchorPrimaryButtonStyle())
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            SummaryRow(label: "Best streak",    value: formatDuration(summary.longestFocusStreak))
            SummaryRow(label: "Off-task",       value: formatDuration(summary.offTaskTime))
            SummaryRow(label: "Score low/high/final", value: scoreSummary)
            SummaryRow(label: "Duration",       value: formatDuration(summary.duration))
            if summary.breakCount > 0 {
                SummaryRow(label: "Active time",  value: formatDuration(summary.activeWorkTime))
                SummaryRow(label: "Break time",   value: formatDuration(summary.totalBreakTime), color: .anchorBreakBlue)
                SummaryRow(label: "Breaks taken", value: "\(summary.breakCount)")
            }
            if let cycles = summary.pomodoroCompletedCycles {
                SummaryRow(label: "Pomodoro cycles", value: "\(cycles)")
            }
            SummaryRow(label: "Interventions",  value: interventionLabel)
            if !summary.topDistractions.isEmpty {
                SummaryLabel("Top Distractions")
                    .padding(.top, 4)
                ForEach(summary.topDistractions, id: \.context) { entry in
                    SummaryRow(label: entry.context, value: formatDuration(entry.seconds), color: .anchorRed.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreSummary: String {
        let lo   = String(format: "%.0f%%", summary.focusScoreMin   * 100)
        let hi   = String(format: "%.0f%%", summary.focusScoreMax   * 100)
        let fin  = String(format: "%.0f%%", summary.focusScoreFinal * 100)
        return "\(lo) / \(hi) / \(fin)"
    }

    private var scoreColor: Color {
        switch summary.focusScoreAvg {
        case 0.7...: return .anchorSage
        case 0.4...: return .anchorAmber
        default:     return .anchorRed
        }
    }

    private var interventionLabel: String {
        if summary.interventionCount == 0 { return "none" }
        var label = "\(summary.interventionCount)"
        if summary.escalationCount > 0 {
            label += " (\(summary.escalationCount) escalated)"
        }
        return label
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60  { return "\(s)s" }
        if s < 3600 {
            let m = s / 60
            let r = s % 60
            return r == 0 ? "\(m)m" : "\(m)m \(r)s"
        }
        let h = s / 3600
        let m = (s % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private struct SummaryLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.capitalized)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.anchorTerracotta.opacity(0.6))
            .tracking(0.8)
    }
}

private struct SummaryRow: View {
    var label: String
    var value: String
    var color: Color = Color.anchorText

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(Color.anchorTextMuted)
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.system(.caption))
                .foregroundStyle(color)
        }
    }
}

private struct ScoreStat: View {
    var label: String
    var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.anchorTextMuted)
        }
    }
}
