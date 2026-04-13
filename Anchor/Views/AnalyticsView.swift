import SwiftUI
import Charts

struct AnalyticsView: View {
    private let profile: UserProfile
    @State private var summaries: [SessionSummary]

    init() {
        self.profile    = UserProfileStore.shared.load()
        self._summaries = State(initialValue: SessionSummaryStore.shared.load())
    }

    private func reloadSummaries() {
        summaries = SessionSummaryStore.shared.load()
    }

    private static let minimumSessionsRequired = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if profile.totalSessions < Self.minimumSessionsRequired {
                    insufficientDataState
                        .padding(.vertical, 40)
                } else {
                    headerStats
                    archetypeSection
                    streakAndDayOfWeekRow
                    focusTrendSection
                    bestHoursSection
                    driftSourcesSection
                    workStyleSection
                    if profile.totalSessions >= 5 {
                        nudgeEffectivenessSection
                    }
                    let notedSessions = summaries.filter { !$0.note.isEmpty }
                    if !notedSessions.isEmpty {
                        sessionNotesSection(notedSessions)
                    }
                }
                recentSessionsListSection
            }
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    // MARK: - Insufficient Data State

    private var insufficientDataState: some View {
        let completed = profile.totalSessions
        let remaining = Self.minimumSessionsRequired - completed

        return VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(Color.anchorTerracotta.opacity(0.5))

            VStack(spacing: 6) {
                Text("Not enough data yet")
                    .font(.title2.weight(.medium))
                Text(completed == 0
                    ? "Complete your first focus session to start building your profile."
                    : "Complete \(remaining) more session\(remaining == 1 ? "" : "s") to unlock analytics.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .multilineTextAlignment(.center)
            }

            if completed > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<Self.minimumSessionsRequired, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < completed ? Color.anchorTerracotta : Color.anchorTextMuted.opacity(0.25))
                            .frame(width: 28, height: 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header Stats

    private var headerStats: some View {
        HStack(spacing: 16) {
            StatCard(
                label: "Sessions",
                value: "\(profile.totalSessions)",
                icon: "target"
            )
            StatCard(
                label: "Total Focus Time",
                value: formatDuration(profile.totalDuration),
                icon: "clock"
            )
            StatCard(
                label: "Avg Focus Score",
                value: "\(Int(profile.averageFocusScore * 100))%",
                icon: "brain.head.profile"
            )
            StatCard(
                label: "Avg Session",
                value: formatDuration(profile.averageSessionMinutes * 60),
                icon: "timer"
            )
        }
    }

    // MARK: - Archetype

    private var archetypeSection: some View {
        let archetype = profile.focusArchetype
        return AnalyticsCard(title: "Your Focus Archetype", subtitle: archetype.rawValue) {
            HStack(spacing: 16) {
                Image(systemName: archetype.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.anchorTerracotta)
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(archetype.rawValue)
                        .font(.title3.weight(.semibold))
                    Text(archetype.description)
                        .font(.callout)
                        .foregroundStyle(Color.anchorTextMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Streak & Day-of-Week

    private var streakAndDayOfWeekRow: some View {
        HStack(spacing: 16) {
            streakCard
            dayOfWeekSection
        }
    }

    private var streakCard: some View {
        let streak = profile.currentStreak
        return VStack(spacing: 10) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 32))
                .foregroundStyle(streak > 0 ? Color.anchorTerracotta : Color.anchorTextMuted.opacity(0.4))
            Text("\(streak)")
                .font(.system(size: 36, weight: .bold).monospacedDigit())
            Text(streak == 1 ? "day streak" : "day streak")
                .font(.caption)
                .foregroundStyle(Color.anchorTextMuted)
        }
        .frame(maxWidth: 140, maxHeight: .infinity)
        .padding(.vertical, 16)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 12))
    }

    private var dayOfWeekSection: some View {
        AnalyticsCard(title: "Focus by Day", subtitle: "Average score") {
            let dayData = dayOfWeekData()
            if dayData.isEmpty {
                Text("Not enough data yet.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(dayData, id: \.weekday) { entry in
                    BarMark(
                        x: .value("Day", entry.label),
                        y: .value("Score", entry.score * 100)
                    )
                    .foregroundStyle(barColor(for: entry.score))
                    .cornerRadius(4)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)%") }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private struct DayEntry {
        var weekday: Int
        var label: String
        var score: Double
    }

    private func dayOfWeekData() -> [DayEntry] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols

        var scoreSums: [Int: Double] = [:]
        var counts: [Int: Int] = [:]

        for session in profile.recentSessions {
            let wd = calendar.component(.weekday, from: session.date)
            scoreSums[wd, default: 0] += session.focusScoreAvg
            counts[wd, default: 0] += 1
        }

        return counts.keys.sorted().map { wd in
            DayEntry(
                weekday: wd,
                label: symbols[wd - 1],
                score: scoreSums[wd, default: 0] / Double(counts[wd, default: 1])
            )
        }
    }

    // MARK: - Focus Trend

    private var focusTrendSection: some View {
        AnalyticsCard(title: "Focus Over Time", subtitle: trendLabel) {
            if profile.recentSessions.count >= 2 {
                Chart {
                    ForEach(Array(profile.recentSessions.enumerated()), id: \.offset) { index, session in
                        LineMark(
                            x: .value("Session", index + 1),
                            y: .value("Focus", session.focusScoreAvg * 100)
                        )
                        .foregroundStyle(Color.anchorTerracotta.gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Session", index + 1),
                            y: .value("Focus", session.focusScoreAvg * 100)
                        )
                        .foregroundStyle(Color.anchorTerracotta.opacity(0.08))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Session", index + 1),
                            y: .value("Focus", session.focusScoreAvg * 100)
                        )
                        .foregroundStyle(Color.anchorTerracotta)
                        .symbolSize(30)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)%") }
                        }
                    }
                }
                .chartXAxisLabel("Session")
                .frame(height: 200)
            } else {
                Text("Need at least 2 sessions to show a trend.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var trendLabel: String {
        guard let slope = profile.recentTrend else { return "" }
        if slope > 0.02      { return "Improving" }
        else if slope < -0.02 { return "Declining" }
        else                  { return "Steady" }
    }

    // MARK: - Best Hours

    private var bestHoursSection: some View {
        AnalyticsCard(title: "Your Best Hours", subtitle: "When you focus best") {
            let hourData = bestHourData()
            if hourData.isEmpty {
                Text("Not enough data yet — keep going.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(hourData, id: \.hour) { entry in
                    BarMark(
                        x: .value("Score", entry.score * 100),
                        y: .value("Hour", entry.label)
                    )
                    .foregroundStyle(barColor(for: entry.score))
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(Int(entry.score * 100))%")
                            .font(.caption)
                            .foregroundStyle(Color.anchorTextMuted)
                    }
                }
                .chartXScale(domain: 0...100)
                .chartXAxis(.hidden)
                .frame(height: CGFloat(hourData.count) * 36)
            }
        }
    }

    private struct HourEntry {
        var hour: Int
        var label: String
        var score: Double
    }

    private func bestHourData() -> [HourEntry] {
        let minMinutes: Double = 10
        return (0..<24)
            .filter { profile.hourlyFocusMinutes[$0] > minMinutes }
            .map { hour in
                let avg = profile.hourlyFocusScoreSum[hour] / profile.hourlyFocusMinutes[hour]
                return HourEntry(hour: hour, label: formatHour(hour), score: avg)
            }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .reversed()
            .map { $0 }
    }

    // MARK: - Recent Sessions List

    private var recentSessionsListSection: some View {
        AnalyticsCard(title: "Recent Sessions", subtitle: "\(summaries.count) total") {
            if summaries.isEmpty {
                Text("No sessions recorded yet.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(summaries) { summary in
                        SessionRow(
                            summary: summary,
                            onDelete: {
                                SessionSummaryStore.shared.delete(sessionId: summary.sessionId)
                                reloadSummaries()
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Drift Sources

    private var driftSourcesSection: some View {
        AnalyticsCard(title: "Where You Drift", subtitle: "Top distractions by time") {
            let distractions = profile.topDistractions.prefix(5)
            if distractions.isEmpty {
                Text("No distractions recorded. Nice work.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(distractions.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(cleanContextLabel(entry.context))
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            Text(formatDuration(entry.seconds))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Color.anchorTextMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Work Style

    private var workStyleSection: some View {
        AnalyticsCard(title: "How You Work", subtitle: "Time distribution across work states") {
            let slices = workStateSlices()
            if slices.isEmpty {
                Text("Keep going — patterns emerge over time.")
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 24) {
                    Chart(slices, id: \.state) { slice in
                        SectorMark(
                            angle: .value("Time", slice.fraction),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .foregroundStyle(slice.color)
                        .cornerRadius(3)
                    }
                    .frame(width: 160, height: 160)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices, id: \.state) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 10, height: 10)
                                Text(slice.label)
                                    .font(.callout)
                                Spacer()
                                Text("\(Int(slice.fraction * 100))%")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(Color.anchorTextMuted)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private struct WorkStateSlice {
        var state: String
        var label: String
        var fraction: Double
        var color: Color
    }

    private func workStateSlices() -> [WorkStateSlice] {
        let dist = profile.workStateDistribution
        guard !dist.isEmpty else { return [] }

        return WorkState.allCases.compactMap { ws in
            let frac = dist[ws.rawValue] ?? 0
            guard frac > 0.01 else { return nil }
            return WorkStateSlice(
                state: ws.rawValue,
                label: ws.rawValue,
                fraction: frac,
                color: ws.stateColor
            )
        }
        .sorted { $0.fraction > $1.fraction }
    }

    // MARK: - Nudge Effectiveness

    private var nudgeEffectivenessSection: some View {
        AnalyticsCard(title: "Nudge Effectiveness", subtitle: "How often nudges help you refocus") {
            HStack(spacing: 32) {
                if profile.softInterventionsFired > 0 {
                    NudgeRing(
                        label: "Soft Nudges",
                        rate: profile.softRecoveryRate,
                        count: profile.softInterventionsFired
                    )
                }
                if profile.strongInterventionsFired > 0 {
                    NudgeRing(
                        label: "Strong Nudges",
                        rate: profile.strongRecoveryRate,
                        count: profile.strongInterventionsFired
                    )
                }
                if profile.softInterventionsFired == 0 && profile.strongInterventionsFired == 0 {
                    Text("No nudges fired yet.")
                        .foregroundStyle(Color.anchorTextMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Session Notes

    private func sessionNotesSection(_ noted: [SessionSummary]) -> some View {
        AnalyticsCard(title: "Session Notes", subtitle: "\(noted.count) note\(noted.count == 1 ? "" : "s")") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(noted.prefix(5)) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(session.taskTitle.isEmpty ? "Untitled" : session.taskTitle)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(session.startedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(Color.anchorTextMuted)
                        }
                        Text(session.note)
                            .font(.caption)
                            .foregroundStyle(Color.anchorTextMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if session.id != noted.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? .now
        return formatter.string(from: date)
    }

    private func barColor(for score: Double) -> Color {
        if score >= 0.7 { return .anchorTerracotta }
        if score >= 0.4 { return .anchorAmber }
        return .anchorRed
    }

    private func cleanContextLabel(_ context: String) -> String {
        context
            .replacingOccurrences(of: "domain:", with: "")
            .replacingOccurrences(of: "app:", with: "")
    }
}

// MARK: - WorkState + CaseIterable

extension WorkState: CaseIterable {
    static var allCases: [WorkState] {
        [.deepFocus, .productiveSwitching, .stuckCycling, .noveltySeeking, .passiveDrift, .idle]
    }
}

// MARK: - Reusable Components

private struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.anchorTerracotta)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.anchorTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AnalyticsCard<Content: View>: View {
    let title: String
    var subtitle: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Spacer()
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.anchorTextMuted)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NudgeRing: View {
    let label: String
    let rate: Double
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.anchorTextMuted.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: rate)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(rate * 100))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            .frame(width: 64, height: 64)

            Text(label)
                .font(.caption)
            Text("\(count) sent")
                .font(.caption2)
                .foregroundStyle(Color.anchorTextMuted)
        }
    }

    private var ringColor: Color {
        if rate >= 0.6 { return .anchorTerracotta }
        if rate >= 0.3 { return .anchorAmber }
        return .anchorRed
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let summary: SessionSummary
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var showDeleteConfirm = false
    @State private var editingNote: String = ""

    var body: some View {
        VStack(spacing: 0) {
            collapsedHeader
            if isExpanded {
                expandedDetails
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color.anchorLinen, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.anchorBorder.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded { editingNote = summary.note }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session record. Your overall stats and analytics won't change.")
        }
    }

    private var collapsedHeader: some View {
        HStack(spacing: 12) {
            scoreBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.taskTitle.isEmpty ? "Untitled session" : summary.taskTitle)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(Color.anchorText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(relativeDate(summary.startedAt))
                    Text("·")
                    Text(formatDuration(summary.duration))
                }
                .font(.caption)
                .foregroundStyle(Color.anchorTextMuted)
            }

            Spacer()

            if !summary.note.isEmpty {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(Color.anchorTerracotta.opacity(0.7))
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.anchorTextMuted)
        }
    }

    private var scoreBadge: some View {
        Text("\(Int(summary.focusScoreAvg * 100))%")
            .font(.system(.callout, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.anchorText)
            .frame(width: 48, height: 32)
            .background(scoreColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(scoreColor.opacity(0.5), lineWidth: 1)
            )
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.bottom, 6)

            detailRow("Best streak",  formatDuration(summary.longestFocusStreak))
            detailRow("Off-task",     formatDuration(summary.offTaskTime))
            detailRow("Score low/high/final", scoreSummary)
            if summary.breakCount > 0 {
                detailRow("Active time", formatDuration(summary.activeWorkTime))
                detailRow("Break time",  formatDuration(summary.totalBreakTime), color: .anchorBreakBlue)
                detailRow("Breaks",      "\(summary.breakCount)")
            }
            if let cycles = summary.pomodoroCompletedCycles {
                detailRow("Pomodoro cycles", "\(cycles)")
            }
            detailRow("Interventions", interventionLabel)

            if !summary.topDistractions.isEmpty {
                Text("TOP DISTRACTIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.anchorTerracotta.opacity(0.6))
                    .tracking(0.8)
                    .padding(.top, 6)
                ForEach(summary.topDistractions.prefix(3), id: \.context) { entry in
                    detailRow(
                        cleanContextLabel(entry.context),
                        formatDuration(entry.seconds),
                        color: .anchorRed.opacity(0.8)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("NOTE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.anchorTerracotta.opacity(0.6))
                    .tracking(0.8)
                    .padding(.top, 6)
                TextEditor(text: $editingNote)
                    .font(.caption)
                    .scrollContentBackground(.hidden)
                    .background(Color.anchorLinen)
                    .cornerRadius(6)
                    .frame(minHeight: 50, maxHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if editingNote.isEmpty {
                            Text("Add a note...")
                                .font(.caption)
                                .foregroundStyle(Color.anchorTextMuted.opacity(0.5))
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.anchorBorder.opacity(0.5), lineWidth: 1)
                    )
                    .tint(Color.anchorTerracotta)
                    .onTapGesture {}

                if editingNote != summary.note {
                    HStack {
                        Spacer()
                        Button("Save note") {
                            var updated = summary
                            updated.note = editingNote
                            SessionSummaryStore.shared.save(updated)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.anchorTerracotta)
                    }
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.anchorRed)
            }
            .padding(.top, 8)
        }
    }

    private func detailRow(_ label: String, _ value: String, color: Color = .anchorText) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.anchorTextMuted)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
    }

    private var scoreColor: Color {
        switch summary.focusScoreAvg {
        case 0.7...: return .anchorTerracotta
        case 0.4...: return .anchorAmber
        default:     return .anchorRed
        }
    }

    private var scoreSummary: String {
        let lo  = String(format: "%.0f%%", summary.focusScoreMin   * 100)
        let hi  = String(format: "%.0f%%", summary.focusScoreMax   * 100)
        let fin = String(format: "%.0f%%", summary.focusScoreFinal * 100)
        return "\(lo) / \(hi) / \(fin)"
    }

    private var interventionLabel: String {
        if summary.interventionCount == 0 { return "none" }
        var label = "\(summary.interventionCount)"
        if summary.escalationCount > 0 {
            label += " (\(summary.escalationCount) escalated)"
        }
        return label
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172_800 { return "yesterday" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 {
            let m = s / 60
            let r = s % 60
            return r == 0 ? "\(m)m" : "\(m)m \(r)s"
        }
        let h = s / 3600
        let m = (s % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func cleanContextLabel(_ context: String) -> String {
        context
            .replacingOccurrences(of: "domain:", with: "")
            .replacingOccurrences(of: "app:", with: "")
    }
}

#Preview("With Data") {
    AnalyticsView()
}
