import SwiftUI

struct SessionSummaryView: View {
    var summary: SessionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                focusScoreSection
                timeBreakdownSection
                keyStatsSection
                if !summary.topDistractions.isEmpty {
                    distractionsSection
                }
                Button("Start Fresh") { SessionManager.shared.dismissSummary() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
        }
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Anchor")
                .font(.system(.title2, design: .serif).weight(.heavy))
            Text("session complete.")
                .font(.system(.caption))
                .foregroundStyle(Color.anchorTextMuted)
            Text(summary.taskTitle.isEmpty ? "Untitled session" : summary.taskTitle)
                .font(.system(.body).weight(.semibold))
                .foregroundStyle(Color.anchorText)
                .padding(.top, 2)
        }
    }

    private var focusScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryLabel("Focus Score")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", summary.focusScoreAvg * 100))
                    .font(.system(size: 36, weight: .heavy, design: .serif))
                    .foregroundStyle(scoreColor)
                Text("avg")
                    .font(.system(.caption))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            HStack(spacing: 12) {
                ScoreStat(label: "low",  value: summary.focusScoreMin)
                ScoreStat(label: "high", value: summary.focusScoreMax)
                ScoreStat(label: "final", value: summary.focusScoreFinal)
            }
        }
    }

    private var timeBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryLabel("Time Breakdown")
            SummaryRow(label: "Duration",     value: formatDuration(summary.duration))
            SummaryRow(label: "Focused",      value: formatDuration(summary.timeStable),  color: .anchorSage)
            SummaryRow(label: "At risk",      value: formatDuration(summary.timeAtRisk),  color: .anchorAmber)
            SummaryRow(label: "Drifted",      value: formatDuration(summary.timeDrift),   color: Color(red: 0.78, green: 0.29, blue: 0.25))
            focusBar
        }
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
                    .fill(Color(red: 0.78, green: 0.29, blue: 0.25).opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .cornerRadius(4)
        .padding(.top, 2)
    }

    private var keyStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryLabel("Stats")
            SummaryRow(label: "Off-task",       value: formatDuration(summary.offTaskTime))
            SummaryRow(label: "Best streak",    value: formatDuration(summary.longestFocusStreak))
            SummaryRow(label: "Interventions",  value: interventionLabel)
        }
    }

    private var distractionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryLabel("Top Distractions")
            ForEach(summary.topDistractions, id: \.context) { entry in
                SummaryRow(label: entry.context, value: formatDuration(entry.seconds), color: Color(red: 0.78, green: 0.29, blue: 0.25).opacity(0.8))
            }
        }
    }

    private var scoreColor: Color {
        switch summary.focusScoreAvg {
        case 0.7...: return .anchorSage
        case 0.4...: return .anchorAmber
        default:     return Color(red: 0.78, green: 0.29, blue: 0.25)
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
                .frame(width: 110, alignment: .leading)
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

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.anchorTerracotta.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(.white)
            .cornerRadius(8)
    }
}
