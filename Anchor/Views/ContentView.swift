import SwiftUI
import AppKit

struct ContentView: View {
    var sessionManager = SessionManager.shared

    var body: some View {
        Group {
            if sessionManager.isActive {
                SessionActiveView()
            } else {
                SessionStartView()
            }
        }
        .background(VisualEffect().ignoresSafeArea())
    }
}

struct SessionStartView: View {
    @State private var taskTitle:   String                  = ""
    @State private var strictness:  FocusSession.Strictness = .normal
    @State private var allowedApps: Set<String>             = []
    @State private var blockedApps: Set<String>             = []
    @State private var runningApps: [String]                = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anchor")
                    .font(.system(.title2, design: .monospaced).weight(.heavy))
                Text("Focus tracker")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What are you working on?")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                TextField("e.g. Build the login flow", text: $taskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                    .onSubmit { tryStart() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Strictness")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(FocusSession.Strictness.allCases, id: \.self) { level in
                        Button(level.rawValue) { strictness = level }
                            .buttonStyle(PickerButtonStyle(isSelected: strictness == level))
                    }
                }
            }

            AppPickerSection(
                title:       "Blocked Apps",
                apps:        runningApps,
                selected:    $blockedApps,
                conflicting: $allowedApps
            )

            if strictness == .strict {
                AppPickerSection(
                    title:       "Allowed Apps",
                    apps:        runningApps,
                    selected:    $allowedApps,
                    conflicting: $blockedApps
                )
            }

            Button("Start Session") { tryStart() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(28)
        .frame(width: 320)
        .onAppear { refreshApps() }
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

    private func tryStart() {
        guard !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        SessionManager.shared.start(
            taskTitle:   taskTitle,
            strictness:  strictness,
            allowedApps: allowedApps,
            blockedApps: blockedApps
        )
    }
}

struct SessionActiveView: View {
    var sessionManager = SessionManager.shared
    var engine         = DriftEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Anchor")
                    .font(.system(.title2, design: .monospaced).weight(.heavy))
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("Session active")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let session = sessionManager.activeSession {
                VStack(alignment: .leading, spacing: 10) {
                    SessionRow(label: "Task",       value: session.taskTitle.isEmpty ? "—" : session.taskTitle)
                    SessionRow(label: "Strictness", value: session.strictness.rawValue)
                    SessionRow(label: "Started",    value: session.startedAt.formatted(date: .omitted, time: .shortened))
                    SessionRow(
                        label:      "Context",
                        value:      engine.state.isOffTaskContext ? "OFF TASK" : "ON TASK",
                        valueColor: engine.state.isOffTaskContext ? .orange : .green
                    )

                    if !session.blockedApps.isEmpty {
                        SessionRow(label: "Blocked", value: session.blockedApps.sorted().joined(separator: ", "))
                    }
                    if !session.allowedApps.isEmpty {
                        SessionRow(label: "Allowed", value: session.allowedApps.sorted().joined(separator: ", "))
                    }
                }
            }

            DebugPanel(state: engine.state, snap: BehaviorAnalyzer.shared.snapshot, config: engine.config)

            Button("End Session") { SessionManager.shared.end() }
                .buttonStyle(DestructiveButtonStyle())
        }
        .padding(28)
        .frame(width: 320)
    }
}

private extension RiskLevel {
    var debugLabel: String {
        switch self { case .stable: "STABLE"; case .atRisk: "AT RISK"; case .drift: "DRIFT" }
    }
    var debugColor: Color {
        switch self { case .stable: .green; case .atRisk: .orange; case .drift: .red }
    }
}

private struct DebugPanel: View {
    var state:  EngineState
    var snap:   BehaviorSnapshot
    var config: RuleConfig

    private var ruleIdleActive:     Bool { snap.isIdle && !snap.currentApp.isEmpty }
    private var ruleHighSwitchRate: Bool { snap.switchesPerMinute >= config.switchRateThreshold }
    private var ruleOffTaskDwell:   Bool { state.isOffTaskContext && snap.dwellInCurrentContext >= config.distractingDwellThreshold }
    private var ruleTotalOffTask:   Bool { state.totalOffTaskDwell >= config.totalOffTaskDwellThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("DEBUG")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

            HStack(spacing: 4) {
                Text("Risk")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(state.riskLevel.debugLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.riskLevel.debugColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("RULES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                DebugRule(label: "idle + active app → atRisk",                              firing: ruleIdleActive)
                DebugRule(label: "ctx sw/min ≥ \(Int(config.switchRateThreshold)) → atRisk", firing: ruleHighSwitchRate)
                DebugRule(label: "off-task dwell ≥ \(Int(config.distractingDwellThreshold))s → drift", firing: ruleOffTaskDwell)
                DebugRule(label: "total off-task ≥ \(Int(config.totalOffTaskDwellThreshold))s → drift", firing: ruleTotalOffTask)
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
                DebugMetric(label: "recovery",       value: String(format: "%.0f%%", state.recoveryProgress * 100))
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

private struct DebugRule: View {
    var label:  String
    var firing: Bool
    var body: some View {
        HStack(spacing: 5) {
            Text(firing ? "●" : "○")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(firing ? Color.red : Color.secondary.opacity(0.5))
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(firing ? Color.primary : Color.secondary)
        }
    }
}

private struct DebugMetric: View {
    var label: String
    var value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

private struct AppPickerSection: View {
    var title:       String
    var apps:        [String]
    @Binding var selected:    Set<String>
    @Binding var conflicting: Set<String>
    @State private var showPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showPopover = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(selected.isEmpty ? "Add" : "\(selected.count) selected")
                    }
                    .font(.system(.caption2, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                    AppListPopover(apps: apps, selected: $selected, conflicting: $conflicting)
                }
            }

            if !selected.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(selected.sorted(), id: \.self) { app in
                            HStack(spacing: 3) {
                                Text(app)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                Button {
                                    selected.remove(app)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }
}

private struct AppListPopover: View {
    var apps:        [String]
    @Binding var selected:    Set<String>
    @Binding var conflicting: Set<String>
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? apps : apps.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    if filtered.isEmpty {
                        Text("No apps found")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(16)
                    } else {
                        ForEach(filtered, id: \.self) { app in
                            HStack(spacing: 8) {
                                Image(systemName: selected.contains(app) ? "checkmark.square.fill" : "square")
                                    .font(.caption)
                                    .foregroundStyle(selected.contains(app) ? Color.accentColor : Color.secondary)
                                Text(app)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .onTapGesture { toggle(app) }
                        }
                    }
                }
            }
            .frame(height: 240)
        }
        .frame(width: 220)
    }

    private func toggle(_ app: String) {
        if selected.contains(app) {
            selected.remove(app)
        } else {
            selected.insert(app)
            conflicting.remove(app)
        }
    }
}

private struct SessionRow: View {
    var label:      String
    var value:      String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

private struct PickerButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(6)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.3))
            .foregroundStyle(.white)
            .cornerRadius(8)
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.red.opacity(configuration.isPressed ? 0.65 : 0.8))
            .foregroundStyle(.white)
            .cornerRadius(8)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = .hudWindow
        view.blendingMode = .behindWindow
        view.state        = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
