import SwiftUI
import Charts
import AppKit

// MARK: - Content View

struct ContentView: View {
    var sessionManager = SessionManager.shared

    var body: some View {
        Group {
            if let summary = sessionManager.lastSummary {
                SessionSummaryView(summary: summary)
            } else if sessionManager.isActive {
                ActiveSessionCompactView()
            } else {
                TabRootView()
            }
        }
        .frame(width: 420)
        .background(Color.anchorLinen.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: sessionManager.isActive) { _, active in
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    findMainWindow()?.miniaturize(nil)
                }
            }
        }
        .onChange(of: sessionManager.lastSummary?.id) { _, id in
            if id != nil {
                findMainWindow()?.deminiaturize(nil)
            }
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
                    .padding(.vertical, 7)
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
                HomeTab()
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

private struct HomeTab: View {
    @State private var taskTitle         = ""
    @State private var classifications:  [String: ContextFitLevel] = [:]
    @State private var runningApps:      [String]                  = []
    @State private var isClassifying     = false
    @State private var classifyDebounce: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you working on?")
                    .font(.system(.caption))
                    .foregroundStyle(Color.anchorTextMuted)
                TextField("e.g. Build the login flow", text: $taskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.body))
                    .padding(10)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.anchorBorder, lineWidth: 1.5))
                    .cornerRadius(10)
                    .onSubmit { startSession() }
                    .onChange(of: taskTitle) { _, newValue in
                        scheduleClassification(for: newValue)
                    }
            }

            if !classifications.isEmpty || isClassifying {
                ClassificationPreview(classifications: classifications, isLoading: isClassifying)
            }

            Button("Drop Anchor") { startSession() }
                .buttonStyle(AnchorPrimaryButtonStyle())

            recentSessionsList
        }
        .padding(20)
        .onAppear { refreshApps() }
    }

    @ViewBuilder
    private var recentSessionsList: some View {
        let sessions = Array(SessionSummaryStore.shared.load().prefix(5))
        if !sessions.isEmpty {
            Divider()
            SectionHeader("Recent Sessions")
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    RecentSessionRow(session: session)
                }
            }
        }
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
        SessionManager.shared.start(
            taskTitle:          taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            appClassifications: classifications
        )
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
            } catch {}
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
                HStack(spacing: 4) {
                    Text(session.startedAt, style: .relative)
                    Text("·")
                    Text(formatDuration(session.duration))
                }
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
}

// MARK: - Compact Analytics Tab

private struct CompactAnalyticsTab: View {
    private let profile: UserProfile
    private let summaries: [SessionSummary]

    init() {
        self.profile   = UserProfileStore.shared.load()
        self.summaries = SessionSummaryStore.shared.load()
    }

    var body: some View {
        if profile.totalSessions == 0 {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(Color.anchorTextMuted)
                Text("Complete a session to see analytics")
                    .font(.system(.caption))
                    .foregroundStyle(Color.anchorTextMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .padding(20)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    weeklyChartSection
                    insightsSection
                }
                .padding(20)
            }
        }
    }

    private var weeklyChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("This Week")

            let data = weekData()
            if data.allSatisfy({ $0.totalMinutes == 0 }) {
                Text("No sessions this week")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.anchorTextMuted)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Minutes", day.totalMinutes)
                    )
                    .foregroundStyle(barColor(for: day.avgScore))
                    .cornerRadius(3)
                }
                .chartYAxisLabel("min")
                .frame(height: 160)
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Insights")

            ForEach(Array(generateInsights().enumerated()), id: \.offset) { _, insight in
                Text(insight)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.anchorText)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func generateInsights() -> [String] {
        var insights: [String] = []

        let bestHours = profile.bestFocusHours(top: 1)
        if let hour = bestHours.first {
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            var comps = DateComponents()
            comps.hour = hour
            if let date = Calendar.current.date(from: comps) {
                insights.append("You focus best around \(formatter.string(from: date)).")
            }
        }

        if let top = profile.topDistractions.first {
            let name = top.context
                .replacingOccurrences(of: "domain:", with: "")
                .replacingOccurrences(of: "app:", with: "")
            insights.append("\(name) is your biggest distractor (\(formatInsightDuration(top.seconds)) total).")
        }

        if profile.softInterventionsFired >= 5 {
            let pct = Int(profile.softRecoveryRate * 100)
            insights.append("Soft nudges help you refocus \(pct)% of the time.")
        }

        if let slope = profile.recentTrend {
            if slope > 0.02 {
                insights.append("Your focus is trending upward.")
            } else if slope < -0.02 {
                insights.append("Your focus has been declining — shorter sessions might help.")
            } else {
                insights.append("Your focus has been steady across recent sessions.")
            }
        }

        if insights.isEmpty {
            insights.append("Keep completing sessions to unlock insights.")
        }

        return insights
    }

    private func barColor(for score: Double) -> Color {
        if score >= 0.7 { return .anchorSage }
        if score >= 0.4 { return .anchorAmber }
        return Color(red: 0.78, green: 0.29, blue: 0.25)
    }

    private func formatInsightDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}

// MARK: - Settings Tab

private struct SettingsTab: View {
    @State private var showDebug          = false
    @State private var chromeEnabled      = UserDefaults.standard.object(forKey: "observer.chrome") as? Bool ?? true
    @State private var idleEnabled        = UserDefaults.standard.object(forKey: "observer.idle") as? Bool ?? true
    @State private var windowTitleEnabled = UserDefaults.standard.object(forKey: "observer.windowTitle") as? Bool ?? true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProviderSettingsSection()

                Divider()

                observersSection

                Divider()

                debugSection
            }
            .padding(20)
        }
        .sheet(isPresented: $showDebug) {
            DebugSheet()
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

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Under the Hood")

            Button("Open Debug Panel") { showDebug = true }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
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

// MARK: - Active Session (compact)

private struct ActiveSessionCompactView: View {
    var sessionManager = SessionManager.shared
    var engine         = DriftEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.anchorSage).frame(width: 7, height: 7)
                        Text("You're anchored")
                            .font(.system(.caption).weight(.semibold))
                    }
                    if let session = sessionManager.activeSession {
                        Text(session.taskTitle.isEmpty ? "Untitled" : session.taskTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.anchorTextMuted)
                    }
                }
                Spacer()
            }

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.anchorSand)
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
            }

            Button("Wrap Up") { SessionManager.shared.end() }
                .buttonStyle(AnchorDestructiveButtonStyle())
        }
        .padding(20)
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
                    .foregroundStyle(Color.accentColor)
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
                    .foregroundStyle(.secondary)
                Text(state.workState.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.workState.stateColor)
                Text(formatSec(state.workStateDuration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("Risk")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(state.riskLevel.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.riskLevel.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
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
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                ClassificationRow(label: "distractor", apps: offTask, color: Color(red: 0.78, green: 0.29, blue: 0.25))
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
            SectionHeader("AI Brain")

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
            .background(isSelected ? Color.anchorTerracotta : Color.primary.opacity(0.07))
            .foregroundStyle(isSelected ? Color.white : Color.anchorText)
            .cornerRadius(4)
    }
}

private struct APIKeyField: View {
    var provider: APIProvider
    var store:    APIKeyStore
    @Binding var keyInput: String

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
                    .foregroundStyle(.red)
            }
        } else {
            HStack(spacing: 6) {
                SecureField(provider.placeholder, text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .padding(5)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.anchorBorder, lineWidth: 1.5))
                    .cornerRadius(8)
                    .onSubmit { save() }
                Button("save") { save() }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.anchorTerracotta)
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.save(trimmed, for: provider)
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
                    .background(Color.white)
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
                    .background(Color.white)
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
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

private struct AnchorPrimaryButtonStyle: ButtonStyle {
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

private struct AnchorDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(red: 0.78, green: 0.29, blue: 0.25).opacity(configuration.isPressed ? 0.65 : 0.85))
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
        switch self { case .stable: .anchorSage; case .atRisk: .anchorAmber; case .drift: Color(red: 0.78, green: 0.29, blue: 0.25) }
    }
}

// MARK: - Helpers

private func scoreColor(for score: Double) -> Color {
    if score >= 0.7 { return .anchorSage }
    if score >= 0.4 { return .anchorAmber }
    return Color(red: 0.78, green: 0.29, blue: 0.25)
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
