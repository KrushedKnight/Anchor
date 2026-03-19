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
                Button("New Session") { SessionManager.shared.dismissSummary() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(28)
        }
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Anchor")
                .font(.system(.title2, design: .monospaced).weight(.heavy))
            Text("Session complete")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(summary.taskTitle.isEmpty ? "Untitled session" : summary.taskTitle)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.top, 2)
        }
    }

    private var focusScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryLabel("Focus Score")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", summary.focusScoreAvg * 100))
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundStyle(scoreColor)
                Text("avg")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
            SummaryRow(label: "Focused",      value: formatDuration(summary.timeStable),  color: .green)
            SummaryRow(label: "At risk",      value: formatDuration(summary.timeAtRisk),  color: .orange)
            SummaryRow(label: "Drifted",      value: formatDuration(summary.timeDrift),   color: .red)
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
                    .fill(Color.green.opacity(0.75))
                    .frame(width: geo.size.width * stableFrac)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.75))
                    .frame(width: geo.size.width * atRiskFrac)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.75))
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
                SummaryRow(label: entry.context, value: formatDuration(entry.seconds), color: .red.opacity(0.8))
            }
        }
    }

    private var scoreColor: Color {
        switch summary.focusScoreAvg {
        case 0.7...: return .green
        case 0.4...: return .orange
        default:     return .red
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
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

private struct SummaryRow: View {
    var label: String
    var value: String
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.system(.caption, design: .monospaced))
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(.white)
            .cornerRadius(8)
    }
}
