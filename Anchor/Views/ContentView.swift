import SwiftUI
import Charts
import AppKit

// MARK: - Content View

struct ContentView: View {
    var sessionManager = SessionManager.shared
    var alertManager   = AppAlertManager.shared
    @AppStorage("onboarding.complete") private var onboardingComplete = false

    var body: some View {
        VStack(spacing: 0) {
            if let summary = sessionManager.lastSummary {
                SessionSummaryView(summary: summary)
            } else if sessionManager.isActive {
                ActiveSessionCompactView()
            } else {
                TabRootView()
            }
            Spacer(minLength: 0)
        }
        .frame(width: 600, height: 450)
        .background(Color.anchorLinen.ignoresSafeArea())
        .preferredColorScheme(.light)
        .alert(
            alertManager.current?.title ?? "",
            isPresented: Binding(
                get: { alertManager.current != nil },
                set: { if !$0 { alertManager.current = nil } }
            ),
            presenting: alertManager.current
        ) { alert in
            if let actionTitle = alert.actionTitle {
                Button(actionTitle) { alert.action?() }
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: sessionManager.isActive) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    findMainWindow()?.miniaturize(nil)
                }
            }
        }
        .onChange(of: sessionManager.lastSummary?.id) { _, id in
            if id != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if let w = findMainWindow() {
                        w.deminiaturize(nil)
                        w.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { !onboardingComplete }, set: { _ in })) {
            OnboardingView()
        }
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) }
    }
}

// MARK: - Tab Root

private enum AppTab: String, CaseIterable {
    case home      = "Home"
    case analytics = "Analytics"
    case settings  = "Settings"

    var icon: String {
        switch self {
        case .home:      "house"
        case .analytics: "chart.bar"
        case .settings:  "gear"
        }
    }
}

private struct AnchorTabBar: View {
    @Binding var selected: AppTab
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { selected = tab } }) {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 11))
                        Text(tab.rawValue).font(.system(size: 12, weight: selected == tab ? .medium : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(
                        Group {
                            if selected == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.anchorLinen)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.anchorBorder, lineWidth: 1))
                            }
                        }
                    )
                    .foregroundStyle(selected == tab ? Color.anchorTerracotta : Color.anchorTextMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

private struct TabRootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        VStack(spacing: 0) {
            AnchorTabBar(selected: $selectedTab)

            switch selectedTab {
            case .home:
                HomeTab(switchToTab: $selectedTab)
                    .transition(.opacity)
            case .analytics:
                CompactAnalyticsTab()
                    .transition(.opacity)
            case .settings:
                SettingsTab()
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Home Tab

private enum SessionMode: String, CaseIterable {
    case freeform  = "Freeform"
    case pomodoro  = "Pomodoro"
}

private struct HomeTab: View {
    @Binding var switchToTab: AppTab
    @State private var taskTitle         = ""
    @State private var classifications:  [String: ContextFitLevel] = [:]
    @State private var runningApps:      [String]                  = []
    @State private var isClassifying     = false
    @State private var classifyDebounce: Task<Void, Never>?
    @State private var sessionMode:      SessionMode = .freeform

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            launcherColumn
            Spacer(minLength: 0)
            recentColumn
        }
        .padding(24)
        .padding(.top, 40)
        .onAppear { refreshApps() }
    }

    private var launcherColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you working on?")
                .font(.system(.caption))
                .foregroundStyle(Color.anchorTextMuted)

            HStack(spacing: 10) {
                TextField("e.g. Build the login flow", text: $taskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.body))
                    .padding(10)
                    .background(Color.anchorLinen)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.anchorBorder, lineWidth: 1.5))
                    .cornerRadius(10)
                    .onSubmit { startSession() }
                    .onChange(of: taskTitle) { _, newValue in
                        scheduleClassification(for: newValue)
                    }

                modePill
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if sessionMode == .pomodoro {
                pomodoroHint
            }

            Button("Drop Anchor") { startSession() }
                .buttonStyle(AnchorPrimaryButtonStyle())

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePill: some View {
        HStack(spacing: 0) {
            ForEach(SessionMode.allCases, id: \.self) { mode in
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { sessionMode = mode } }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode == .freeform ? "timer" : "clock.badge.checkmark")
                            .font(.system(size: 9))
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(
                        Group {
                            if sessionMode == mode {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.anchorLinen)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.anchorBorder, lineWidth: 1))
                            }
                        }
                    )
                    .foregroundStyle(sessionMode == mode ? Color.anchorTerracotta : Color.anchorTextMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 8))
    }

    private var pomodoroHint: some View {
        let work  = Int(PomodoroSettings.workMinutes)
        let brk   = Int(PomodoroSettings.breakMinutes)
        let long  = Int(PomodoroSettings.longBreakMinutes)
        let cyc   = PomodoroSettings.cyclesBeforeLong

        return HStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTerracotta.opacity(0.6))
            Text("\(work)m work · \(brk)m break · \(long)m long every \(cyc)")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
            Spacer()
            Button("Settings →") {
                withAnimation(.easeInOut(duration: 0.18)) { switchToTab = .settings }
            }
            .font(.system(size: 9, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.anchorTerracotta.opacity(0.5))
        }
        .padding(8)
        .background(Color.anchorSand.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recentColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            let sessions = Array(SessionSummaryStore.shared.load().prefix(3))
            Text("Recent")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.anchorTextMuted)

            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.anchorTextMuted.opacity(0.6))
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        RecentSessionRow(session: session)
                    }
                }

                if SessionSummaryStore.shared.load().count > 3 {
                    Button("See all →") {
                            withAnimation(.easeInOut(duration: 0.18)) { switchToTab = .analytics }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.anchorTerracotta)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 170)
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular &&
                $0.bundleIdentifier != Bundle.main.bundleIdentifier
            }
            .compactMap { $0.localizedName }
            .sorted()
    }

    private func startSession() {
        let pomoConfig: PomodoroConfig? = sessionMode == .pomodoro
            ? PomodoroConfig(
                workDuration:           PomodoroSettings.workMinutes * 60,
                shortBreakDuration:     PomodoroSettings.breakMinutes * 60,
                longBreakDuration:      PomodoroSettings.longBreakMinutes * 60,
                cyclesBeforeLongBreak:  PomodoroSettings.cyclesBeforeLong
              )
            : nil
        SessionManager.shared.start(
            taskTitle:          taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            appClassifications: classifications,
            pomodoroConfig:     pomoConfig
        )
        SessionManager.shared.classifyTaskProfile()
    }

    private func scheduleClassification(for value: String) {
        classifyDebounce?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let provider = APIKeyStore.shared.activeProvider
        guard trimmed.count >= 3, provider == .ollama || APIKeyStore.shared.isSet(for: provider) else { return }
        classifyDebounce = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            isClassifying = true
            defer { isClassifying = false }
            do {
                let result = try await TaskClassifier.shared.classify(task: trimmed, apps: runningApps)
                var map: [String: ContextFitLevel] = [:]
                for app in result.onTask    { map[app] = .onTask }
                for app in result.ambiguous { map[app] = .ambiguous }
                for app in result.offTask   { map[app] = .offTask }
                classifications = map
            } catch let error as ClassifierError {
                AppAlertManager.shared.post(title: "Classification Failed", message: error.userMessage)
            } catch {
                AppAlertManager.shared.post(title: "Classification Failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Recent Session Row

private struct RecentSessionRow: View {
    var session: SessionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle.isEmpty ? "Untitled" : session.taskTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.anchorText)
                    .lineLimit(1)
                Text(relativeTime(session.startedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            Spacer()
            Text(String(format: "%.0f%%", session.focusScoreAvg * 100))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(scoreColor(for: session.focusScoreAvg))
        }
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        let minutes = Int(interval) / 60
        if minutes < 60 { return "\(max(1, minutes))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return days == 1 ? "Yesterday" : "\(days)d ago"
    }
}

// MARK: - Compact Analytics Tab

private struct CompactAnalyticsTab: View {
    private let profile: UserProfile
    private let summaries: [SessionSummary]

    init() {
        self.profile   = UserProfileStore.shared.load()
        self.summaries = SessionSummaryStore.shared.load()
    }

    private static let minimumSessions = 3

    var body: some View {
        if profile.totalSessions < Self.minimumSessions {
            insufficientDataState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                scoreBar
                insightCardsGrid
                weeklyChart
            }
            .padding(20)
        }
    }

    private var insufficientDataState: some View {
        let completed = profile.totalSessions
        let remaining = Self.minimumSessions - completed

        return VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(Color.anchorTextMuted)
            Text("Not enough data yet")
                .font(.system(.caption, weight: .medium))
            Text(completed == 0
                ? "Complete a focus session to start building your profile."
                : "Complete \(remaining) more session\(remaining == 1 ? "" : "s") to unlock analytics.")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)

            if completed > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<Self.minimumSessions, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < completed ? Color.anchorTerracotta : Color.anchorTextMuted.opacity(0.25))
                            .frame(width: 20, height: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(20)
    }

    private var scoreBar: some View {
        let score = profile.baselineFocusScore
        let scorePct = Int(score * 100)
        let delta = focusScoreDelta()
        let streak = profile.currentStreak
        let archetype = profile.focusArchetype
        let weekSessions = summaries.filter { isThisWeek($0.startedAt) }
        let totalMins = weekSessions.reduce(0.0) { $0 + $1.duration } / 60

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(scorePct)%")
                    .font(.system(size: 36, weight: .heavy, design: .serif))
                    .foregroundStyle(scoreColor(for: score))

                if let (pct, isUp) = delta {
                    trendPill(pct: pct, isUp: isUp)
                }

                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.anchorTerracotta)
                        Text("\(streak)")
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                    }
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: archetype.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.anchorTerracotta)
                    Text(archetype.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.anchorText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.anchorSand, in: Capsule())
            }

            Text("\(weekSessions.count) session\(weekSessions.count == 1 ? "" : "s"), \(formatDuration(totalMins * 60)) this week")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
        }
    }

    private var insightCardsGrid: some View {
        let topDistraction = profile.topDistractions.first
        let bestHour = profile.bestFocusHours(top: 1).first

        return HStack(spacing: 12) {
            if let top = topDistraction {
                insightCard(
                    title: "Top Distraction",
                    headline: "\(cleanLabel(top.context)) \u{2014} \(formatDuration(top.seconds)) lost",
                    icon: "exclamationmark.triangle",
                    color: .anchorRed
                )
            }

            if let hour = bestHour {
                let formatter = DateFormatter()
                let _ = formatter.dateFormat = "h a"
                var comps = DateComponents()
                let _ = (comps.hour = hour)
                if let date = Calendar.current.date(from: comps) {
                    insightCard(
                        title: "Peak Focus",
                        headline: "You focus best \(formatter.string(from: date))",
                        icon: "clock",
                        color: .anchorSage
                    )
                }
            }

            let dayData = dayOfWeekData()
            if let bestDay = dayData.max(by: { $0.score < $1.score }) {
                let totalMins = summaries
                    .filter { Calendar.current.component(.weekday, from: $0.startedAt) == bestDay.weekday }
                    .reduce(0.0) { $0 + $1.duration } / 60
                insightCard(
                    title: "Best Day",
                    headline: "\(bestDay.label) \u{2014} \(formatDuration(totalMins * 60))",
                    icon: "calendar",
                    color: .anchorAmber
                )
            }
        }
    }

    private func insightCard(title: String, headline: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            Text(headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.anchorText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.anchorSand.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            let data = weekData()
            let hasData = data.contains { $0.totalMinutes > 0 }
            if !hasData {
                Text("No sessions this week")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(data) { day in
                        BarMark(
                            x: .value("Day", day.label),
                            y: .value("Minutes", day.totalMinutes)
                        )
                        .foregroundStyle(day.avgScore > 0 ? barColor(for: day.avgScore).opacity(0.7) : Color.anchorSand)
                        .cornerRadius(3)
                        .annotation(position: .top) {
                            if day.avgScore > 0 {
                                Text(String(format: "%.0f%%", day.avgScore * 100))
                                    .font(.system(size: 7).monospacedDigit())
                                    .foregroundStyle(Color.anchorTextMuted)
                            }
                        }
                    }

                    let avg = data.filter { $0.totalMinutes > 0 }.map(\.totalMinutes).reduce(0, +) / max(1, Double(data.filter { $0.totalMinutes > 0 }.count))
                    RuleMark(y: .value("Avg", avg))
                        .foregroundStyle(Color.anchorTerracotta.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))m").font(.system(size: 8)) }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func trendPill(pct: Int, isUp: Bool) -> some View {
        let color = isUp ? Color.anchorSage : .anchorRed
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text("\(pct)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func focusScoreDelta() -> (Int, Bool)? {
        let sessions = profile.recentSessions
        guard sessions.count >= 6 else { return nil }
        let mid = sessions.count / 2
        let recentAvg = sessions[mid...].map(\.focusScoreAvg).reduce(0, +) / Double(sessions.count - mid)
        let olderAvg = sessions[..<mid].map(\.focusScoreAvg).reduce(0, +) / Double(mid)
        guard olderAvg > 0 else { return nil }
        let delta = Int(((recentAvg - olderAvg) / olderAvg) * 100)
        if delta == 0 { return nil }
        return (abs(delta), delta > 0)
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

    private struct DayFocus: Identifiable {
        let id: Date
        let label: String
        let totalMinutes: Double
        let avgScore: Double
    }

    private func weekData() -> [DayFocus] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let daySummaries = summaries.filter { $0.startedAt >= day && $0.startedAt < next }
            let totalMins = daySummaries.reduce(0.0) { $0 + $1.duration } / 60
            let avgScore = daySummaries.isEmpty
                ? 0
                : daySummaries.reduce(0.0) { $0 + $1.focusScoreAvg } / Double(daySummaries.count)

            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"

            return DayFocus(id: day, label: formatter.string(from: day), totalMinutes: totalMins, avgScore: avgScore)
        }
    }

    private func maxMinutes(in data: [DayFocus]) -> Double {
        max(data.map(\.totalMinutes).max() ?? 1, 1)
    }

    private func isThisWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        return date >= weekAgo
    }

    private func barColor(for score: Double) -> Color {
        scoreColor(for: score)
    }

    private func cleanLabel(_ context: String) -> String {
        context
            .replacingOccurrences(of: "domain:", with: "")
            .replacingOccurrences(of: "app:", with: "")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}

// MARK: - Pomodoro Settings (UserDefaults-backed)

private enum PomodoroSettings {
    private static let defaults = UserDefaults.standard

    static var workMinutes: Double {
        get { defaults.object(forKey: "pomo.work") as? Double ?? 25 }
        set { defaults.set(newValue, forKey: "pomo.work") }
    }
    static var breakMinutes: Double {
        get { defaults.object(forKey: "pomo.break") as? Double ?? 5 }
        set { defaults.set(newValue, forKey: "pomo.break") }
    }
    static var longBreakMinutes: Double {
        get { defaults.object(forKey: "pomo.longBreak") as? Double ?? 15 }
        set { defaults.set(newValue, forKey: "pomo.longBreak") }
    }
    static var cyclesBeforeLong: Int {
        get { defaults.object(forKey: "pomo.cycles") as? Int ?? 4 }
        set { defaults.set(newValue, forKey: "pomo.cycles") }
    }
}

// MARK: - Settings Tab

private struct SettingsTab: View {
    @State private var showDebug          = false
    @State private var chromeEnabled      = UserDefaults.standard.object(forKey: "observer.chrome") as? Bool ?? true
    @State private var idleEnabled        = UserDefaults.standard.object(forKey: "observer.idle") as? Bool ?? true
    @State private var windowTitleEnabled = UserDefaults.standard.object(forKey: "observer.windowTitle") as? Bool ?? true

    @State private var workMin      = PomodoroSettings.workMinutes
    @State private var breakMin     = PomodoroSettings.breakMinutes
    @State private var longBreakMin = PomodoroSettings.longBreakMinutes
    @State private var cycles       = PomodoroSettings.cyclesBeforeLong

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if NotificationHandler.shared.isGranted == false {
                    notificationDeniedBanner
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        pomodoroSection
                        classificationsSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 20) {
                        observersSection
                        providerSection
                        debugSection
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showDebug) {
            DebugSheet()
        }
    }

    private var notificationDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.anchorAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications blocked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.anchorText)
                Text("Nudges won't be delivered. Enable in System Settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            Spacer()
            Button("Open") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
            .font(.system(size: 9, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.anchorTerracotta)
        }
        .padding(10)
        .background(Color.anchorAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.anchorAmber.opacity(0.2), lineWidth: 1))
    }

    private var pomodoroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pomodoro")

            PomodoroStepperRow(label: "Work", value: $workMin, range: 10...90, unit: "min")
                .onChange(of: workMin) { _, v in PomodoroSettings.workMinutes = v }
            PomodoroStepperRow(label: "Break", value: $breakMin, range: 1...30, unit: "min")
                .onChange(of: breakMin) { _, v in PomodoroSettings.breakMinutes = v }
            PomodoroStepperRow(label: "Long break", value: $longBreakMin, range: 5...60, unit: "min")
                .onChange(of: longBreakMin) { _, v in PomodoroSettings.longBreakMinutes = v }
            HStack {
                Text("Long break every")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
                Spacer()
                Stepper(value: $cycles, in: 2...8) {
                    Text("\(cycles) cycles")
                        .font(.system(size: 10, weight: .medium))
                }
                .controlSize(.mini)
            }
            .onChange(of: cycles) { _, v in PomodoroSettings.cyclesBeforeLong = v }
        }
    }

    private var observersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Observers")

            ObserverToggle(label: "App Tracking", enabled: .constant(true), locked: true)

            ObserverToggle(label: "Chrome Tabs", enabled: $chromeEnabled)
                .onChange(of: chromeEnabled) { _, on in
                    UserDefaults.standard.set(on, forKey: "observer.chrome")
                    let d = NSApp.delegate as? AppDelegate
                    d?.chromeMonitor.stop()
                    if on { d?.chromeMonitor.start() }
                }

            ObserverToggle(label: "Idle Detection", enabled: $idleEnabled)
                .onChange(of: idleEnabled) { _, on in
                    UserDefaults.standard.set(on, forKey: "observer.idle")
                    let d = NSApp.delegate as? AppDelegate
                    d?.idleMonitor.stop()
                    if on { d?.idleMonitor.start() }
                }

            ObserverToggle(label: "Window Titles", enabled: $windowTitleEnabled)
                .onChange(of: windowTitleEnabled) { _, on in
                    UserDefaults.standard.set(on, forKey: "observer.windowTitle")
                    let d = NSApp.delegate as? AppDelegate
                    d?.windowTitleObserver.stop()
                    if on { d?.windowTitleObserver.start() }
                }
        }
    }

    private var providerSection: some View {
        ProviderSettingsSection()
    }

    private var classificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Classifications")

            Text("Apps")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.anchorTextMuted)
                .textCase(.uppercase)

            ClassificationListSection(kind: .app)

            Text("Domains")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.anchorTextMuted)
                .textCase(.uppercase)
                .padding(.top, 4)

            ClassificationListSection(kind: .domain)
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Under the Hood")

            Button("Open Debug Panel") { showDebug = true }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.anchorTerracotta)
        }
    }
}

private struct ObserverToggle: View {
    var label: String
    @Binding var enabled: Bool
    var locked: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.anchorText)
            Spacer()
            if locked {
                Text("always on")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.anchorTextMuted)
            } else {
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }
}

// MARK: - Pomodoro Stepper Row

private struct PomodoroStepperRow: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
            Spacer()
            Stepper(value: $value, in: range, step: 5) {
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 10, weight: .medium))
            }
            .controlSize(.mini)
        }
    }
}

// MARK: - Active Session (compact)

private struct ActiveSessionCompactView: View {
    var sessionManager = SessionManager.shared
    var engine         = DriftEngine.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 16) {
                sessionHeader

                if sessionManager.isPaused {
                    breakStateView
                } else {
                    focusStateView
                }

                if let pomo = sessionManager.pomodoroTimer, pomo.isWaitingForUser {
                    pomodoroPromptBanner(pomo)
                }

                actionButtons
            }
            .padding(20)
        }
    }

    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(sessionManager.isPaused ? Color.anchorBreakBlue : Color.anchorSage)
                        .frame(width: 7, height: 7)
                    Text(sessionManager.isPaused ? "On break" : "You're anchored")
                        .font(.system(.caption).weight(.semibold))
                }
                if let session = sessionManager.activeSession {
                    Text(session.taskTitle.isEmpty ? "Untitled" : session.taskTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.anchorTextMuted)
                }
            }
            Spacer()
            if let pomo = sessionManager.pomodoroTimer {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(pomo.phase.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(pomo.phase.isBreak ? Color.anchorBreakBlue : Color.anchorSage)
                    HStack(spacing: 3) {
                        ForEach(0..<pomo.config.cyclesBeforeLongBreak, id: \.self) { i in
                            Circle()
                                .fill(i < pomo.completedCycles ? Color.anchorSage : Color.anchorTextMuted.opacity(0.25))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
    }

    private var focusStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.anchorSand)
                        Capsule()
                            .fill(engine.state.riskLevel.color)
                            .frame(width: geo.size.width * engine.state.focusScore)
                    }
                }
                .frame(height: 5)
                Text(String(format: "%.0f%%", engine.state.focusScore * 100))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(engine.state.riskLevel.color)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.state.workState.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(engine.state.workState.stateColor)
                    Text("state")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.anchorTextMuted)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.state.riskLevel.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(engine.state.riskLevel.color)
                    Text("risk")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.anchorTextMuted)
                }
                Spacer()
                if let pomo = sessionManager.pomodoroTimer, !pomo.isWaitingForUser {
                    Text(formatCountdown(pomo.phaseRemaining))
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(Color.anchorText)
                }
            }
        }
    }

    private var breakStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.anchorBreakBlue)
                if let start = sessionManager.breakTracker.currentBreakStart {
                    Text(formatCountdown(Date.now.timeIntervalSince(start)))
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color.anchorBreakBlue)
                }
                Spacer()
                if let pomo = sessionManager.pomodoroTimer, !pomo.isWaitingForUser {
                    Text("\(formatCountdown(pomo.phaseRemaining)) left")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.anchorTextMuted)
                }
            }

            if sessionManager.breakTracker.breakCount > 0 {
                Text("Break \(sessionManager.breakTracker.breakCount) · \(formatCountdown(sessionManager.activeWorkTime)) focused")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
            }
        }
    }

    private func pomodoroPromptBanner(_ pomo: PomodoroTimer) -> some View {
        HStack {
            Text(pomo.phase == .work ? "Time for a break!" : "Ready to focus?")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if pomo.phase.isBreak {
                Button("Skip") { pomo.skipBreak() }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.anchorTextMuted)
            }
            Button(pomo.phase == .work ? "Take Break" : "Resume") {
                pomo.advancePhase()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.anchorTerracotta)
        }
        .padding(10)
        .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !sessionManager.isPaused && !sessionManager.isPomodoro {
                Button("Take a Break") {
                    SessionManager.shared.pause(reason: "manual")
                }
                .buttonStyle(AnchorSecondaryButtonStyle())
            }
            if sessionManager.isPaused && !sessionManager.isPomodoro {
                Button("Resume") {
                    SessionManager.shared.resume()
                }
                .buttonStyle(AnchorPrimaryButtonStyle())
            }
            Button("Wrap Up") { SessionManager.shared.end() }
                .buttonStyle(AnchorDestructiveButtonStyle())
        }
    }

    private func formatCountdown(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Debug Sheet

private struct DebugSheet: View {
    var engine = DriftEngine.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Debug Panel")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.anchorTerracotta)
            }
            .padding(16)

            Divider()

            ScrollView {
                DebugPanelContent(state: engine.state, snap: BehaviorAnalyzer.shared.snapshot)
                    .padding(16)
            }
        }
        .frame(width: 400, height: 540)
    }
}

private struct DebugPanelContent: View {
    var state: EngineState
    var snap:  BehaviorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("State")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
                Text(state.workState.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.workState.stateColor)
                Text(formatSec(state.workStateDuration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
            }

            HStack(spacing: 4) {
                Text("Risk")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
                Text(state.riskLevel.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.riskLevel.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.anchorSand)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(state.riskLevel.color)
                                .frame(width: geo.size.width * state.focusScore)
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f%%", state.focusScore * 100))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(state.riskLevel.color)
                        .frame(width: 30, alignment: .trailing)
                }
                DebugMetric(label: "quality",     value: String(format: "%.0f%%", state.focusQuality * 100))
                DebugMetric(label: "base",        value: String(format: "%.0f%%", state.workState.baseTargetScore * 100))
                DebugMetric(label: "floor",       value: String(format: "%.0f%%", state.workState.decayFloor * 100))
                DebugMetric(label: "accumulator", value: formatSec(state.accumulatorSeconds))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("METRICS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
                    .padding(.top, 2)
                DebugMetric(label: "app",            value: snap.currentApp.isEmpty ? "—" : snap.currentApp)
                DebugMetric(label: "domain",         value: snap.currentDomain.isEmpty ? "—" : snap.currentDomain)
                DebugMetric(label: "idle",           value: snap.isIdle ? "yes" : "no")
                DebugMetric(label: "app sw/30s",     value: String(format: "%.0f", snap.appSwitchRate30s))
                DebugMetric(label: "tab sw/30s",     value: String(format: "%.0f", snap.tabSwitchRate30s))
                DebugMetric(label: "ctx sw/min",     value: String(format: "%.0f", snap.switchesPerMinute))
                DebugMetric(label: "distinct/5m",    value: "\(snap.distinctApps5m) apps")
                DebugMetric(label: "bouncing",       value: snap.isBouncing ? "YES" : "no")
                DebugMetric(label: "dwell",          value: formatSec(snap.dwellInCurrentContext))
                DebugMetric(label: "focus streak",   value: formatSec(snap.currentFocusStreak))
                DebugMetric(label: "idle ratio 2m",  value: String(format: "%.1f%%", snap.idleRatio120s * 100))
                DebugMetric(label: "off-task total", value: formatSec(state.totalOffTaskDwell))
                DebugMetric(label: "off-task ctx",   value: state.isOffTaskContext ? "yes" : "no")
            }

            if !snap.recentAppDwells.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RECENT DWELLS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.anchorTextMuted)
                        .padding(.top, 2)
                    ForEach(Array(snap.recentAppDwells.reversed().enumerated()), id: \.offset) { _, entry in
                        DebugMetric(label: formatSec(entry.duration), value: entry.app)
                    }
                }
            }
        }
    }

    private func formatSec(_ t: TimeInterval) -> String {
        t < 60 ? String(format: "%.0fs", t) : String(format: "%.1fm", t / 60)
    }
}

// MARK: - Classification Preview

private struct ClassificationPreview: View {
    var classifications: [String: ContextFitLevel]
    var isLoading: Bool

    private var onTask:    [String] { classifications.filter { $0.value == .onTask }.keys.sorted() }
    private var ambiguous: [String] { classifications.filter { $0.value == .ambiguous }.keys.sorted() }
    private var offTask:   [String] { classifications.filter { $0.value == .offTask }.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("App Classification")
                    .font(.system(.caption))
                    .foregroundStyle(Color.anchorTextMuted)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }
            if !onTask.isEmpty {
                ClassificationRow(label: "on-task", apps: onTask, color: .anchorSage)
            }
            if !ambiguous.isEmpty {
                ClassificationRow(label: "neutral", apps: ambiguous, color: .anchorAmber)
            }
            if !offTask.isEmpty {
                ClassificationRow(label: "distractor", apps: offTask, color: .anchorRed)
            }
        }
    }
}

private struct ClassificationRow: View {
    var label: String
    var apps:  [String]
    var color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
            Text("\(label): \(apps.joined(separator: ", "))")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
                .lineLimit(2)
        }
    }
}

// MARK: - Provider Settings

private struct ProviderSettingsSection: View {
    var store = APIKeyStore.shared
    @State private var keyInput:       String = ""
    @State private var ollamaEndpoint: String = ""
    @State private var ollamaModel:    String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("AI Provider")

            HStack(spacing: 6) {
                ForEach(APIProvider.allCases) { provider in
                    Button(provider.displayName) {
                        store.activeProvider = provider
                        keyInput = ""
                    }
                    .buttonStyle(ProviderPickerStyle(isSelected: store.activeProvider == provider))
                }
            }

            switch store.activeProvider {
            case .anthropic, .openAI:
                APIKeyField(provider: store.activeProvider, store: store, keyInput: $keyInput)
            case .ollama:
                OllamaConfigFields(store: store, endpoint: $ollamaEndpoint, model: $ollamaModel)
            }
        }
        .onAppear {
            ollamaEndpoint = store.ollamaConfig.endpoint
            ollamaModel    = store.ollamaConfig.modelName
        }
    }
}

private struct ProviderPickerStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.anchorTerracotta : Color.anchorSand)
            .foregroundStyle(isSelected ? Color.anchorLinen : Color.anchorText)
            .cornerRadius(4)
    }
}

private struct APIKeyField: View {
    var provider: APIProvider
    var store:    APIKeyStore
    @Binding var keyInput: String
    @State private var saveError: String?

    var body: some View {
        if store.isSet(for: provider) {
            HStack(spacing: 6) {
                Text("●●●●●●●●●●●●")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.anchorTextMuted)
                Spacer()
                Button("clear") { store.clear(for: provider) }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.anchorRed)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SecureField(provider.placeholder, text: $keyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .padding(5)
                        .background(Color.anchorLinen)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(saveError != nil ? Color.anchorRed.opacity(0.6) : Color.anchorBorder, lineWidth: 1.5))
                        .cornerRadius(8)
                        .onSubmit { save() }
                        .onChange(of: keyInput) { _, _ in saveError = nil }
                    Button("save") { save() }
                        .font(.system(size: 9))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.anchorTerracotta)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = saveError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.anchorRed)
                }
            }
        }
    }

    private func save() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let validationError = APIKeyStore.validate(trimmed, for: provider) {
            saveError = validationError
            return
        }
        if let keychainError = store.save(trimmed, for: provider) {
            saveError = keychainError
            return
        }
        saveError = nil
        keyInput = ""
    }
}

private struct OllamaConfigFields: View {
    var store: APIKeyStore
    @Binding var endpoint: String
    @Binding var model:    String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("endpoint")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(width: 60, alignment: .leading)
                TextField("http://localhost:11434", text: $endpoint)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .padding(5)
                    .background(Color.anchorLinen)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.anchorBorder, lineWidth: 1.5))
                    .cornerRadius(8)
                    .onSubmit { save() }
            }

            HStack {
                Text("model")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(width: 60, alignment: .leading)
                TextField("e.g. mistral, llama2", text: $model)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .padding(5)
                    .background(Color.anchorLinen)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.anchorBorder, lineWidth: 1.5))
                    .cornerRadius(8)
                    .onSubmit { save() }
            }

            Button("save") { save() }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundStyle(Color.anchorTerracotta)
                .disabled(endpoint.isEmpty || model.isEmpty)
        }
    }

    private func save() {
        let config = OllamaConfig(
            endpoint:  endpoint.trimmingCharacters(in: .whitespaces),
            modelName: model.trimmingCharacters(in: .whitespaces)
        )
        store.saveOllamaConfig(config)
    }
}

// MARK: - Shared Components

private struct DebugMetric: View {
    var label: String
    var value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.anchorTextMuted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.anchorText)
        }
    }
}

struct AnchorPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.anchorTerracotta.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35))
            .foregroundStyle(.white)
            .cornerRadius(10)
    }
}

private struct AnchorSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.anchorSand.opacity(configuration.isPressed ? 0.6 : 1))
            .foregroundStyle(Color.anchorText)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.anchorBorder, lineWidth: 1))
    }
}

private struct AnchorDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.anchorRed.opacity(configuration.isPressed ? 0.65 : 0.85))
            .foregroundStyle(.white)
            .cornerRadius(10)
    }
}

// MARK: - RiskLevel Extensions

extension RiskLevel {
    var label: String {
        switch self { case .stable: "in flow"; case .atRisk: "drifting"; case .drift: "off course" }
    }
    var color: Color {
        switch self { case .stable: .anchorSage; case .atRisk: .anchorAmber; case .drift: .anchorRed }
    }
}

// MARK: - Helpers

private func scoreColor(for score: Double) -> Color {
    if score >= 0.7 { return .anchorSage }
    if score >= 0.4 { return .anchorAmber }
    return .anchorRed
}

private func formatSessionDate(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
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

// MARK: - Classification Overrides UI

private enum ClassificationKind { case app, domain }

private struct ClassificationListSection: View {
    var kind: ClassificationKind
    var store = ClassificationOverrideStore.shared

    @State private var newName  = ""
    @State private var newLevel = ContextFitLevel.onTask

    private var overrides: [String: ContextFitLevel] {
        kind == .app ? store.appOverrides : store.domainOverrides
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(overrides.keys.sorted(), id: \.self) { key in
                ClassificationOverrideRow(
                    name: key,
                    level: Binding(
                        get: { overrides[key] ?? .ambiguous },
                        set: { set(key, to: $0) }
                    ),
                    onRemove: { remove(key) }
                )
            }

            HStack(spacing: 6) {
                TextField(kind == .app ? "App name..." : "domain.com...", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorText)
                    .frame(maxWidth: .infinity)

                LevelPicker(level: $newLevel)

                Button {
                    guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if kind == .app { store.setApp(name, to: newLevel) }
                    else            { store.setDomain(name, to: newLevel) }
                    newName = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.anchorSage)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.anchorSand.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func set(_ name: String, to level: ContextFitLevel) {
        if kind == .app { store.setApp(name, to: level) }
        else            { store.setDomain(name, to: level) }
    }

    private func remove(_ name: String) {
        if kind == .app { store.removeApp(name) }
        else            { store.removeDomain(name) }
    }
}

private struct ClassificationOverrideRow: View {
    var name: String
    @Binding var level: ContextFitLevel
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            LevelPicker(level: $level)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.anchorSand.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct LevelPicker: View {
    @Binding var level: ContextFitLevel

    var body: some View {
        Picker("", selection: $level) {
            Text("On Task").tag(ContextFitLevel.onTask)
            Text("Ambiguous").tag(ContextFitLevel.ambiguous)
            Text("Off Task").tag(ContextFitLevel.offTask)
        }
        .pickerStyle(.menu)
        .controlSize(.mini)
        .labelsHidden()
        .frame(width: 82)
    }
}
