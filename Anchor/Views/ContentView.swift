import SwiftUI
import AppKit

struct ContentView: View {
    var sessionManager = SessionManager.shared

    var body: some View {
        Group {
            if sessionManager.isActive {
                SessionActiveView()
            } else if let summary = sessionManager.lastSummary {
                SessionSummaryView(summary: summary)
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

            DebugPanel(state: engine.state, snap: BehaviorAnalyzer.shared.snapshot)

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
    var state: EngineState
    var snap:  BehaviorSnapshot

    @State private var keyInput:   String = ""
    @State private var isEditing:  Bool   = false
    var apiKeyStore = APIKeyStore.shared

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
                                .fill(scoreColor)
                                .frame(width: geo.size.width * state.focusScore)
                        }
                    }
                    .frame(height: 6)
                    Text(String(format: "%.0f%%", state.focusScore * 100))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(scoreColor)
                        .frame(width: 30, alignment: .trailing)
                }
                DebugMetric(label: "target", value: String(format: "%.0f%%", state.pressures.target * 100))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("PRESSURES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                PressureRow(label: "off-task",   value: state.pressures.offTask,     isBonus: false)
                PressureRow(label: "accumulator",value: state.pressures.accumulator,  isBonus: false)
                PressureRow(label: "scatter",    value: state.pressures.scatter,      isBonus: false)
                PressureRow(label: "skimming",   value: state.pressures.skimming,     isBonus: false)
                PressureRow(label: "idle ratio", value: state.pressures.idleRatio,    isBonus: false)
                PressureRow(label: "streak",     value: state.pressures.streakBonus,  isBonus: true)
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

            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Text("ANTHROPIC API KEY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if apiKeyStore.isSet && !isEditing {
                    HStack(spacing: 6) {
                        Text("sk-ant-●●●●●●●●●●●●")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("change") {
                            keyInput  = ""
                            isEditing = true
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        Button("clear") {
                            apiKeyStore.clear()
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                } else {
                    HStack(spacing: 6) {
                        SecureField("sk-ant-…", text: $keyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                            .onSubmit { commitKey() }
                        Button("save") { commitKey() }
                            .font(.system(size: 9, design: .monospaced))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func commitKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        apiKeyStore.save(trimmed)
        keyInput  = ""
        isEditing = false
    }

    private var scoreColor: Color {
        switch state.riskLevel {
        case .stable: .green
        case .atRisk: .orange
        case .drift:  .red
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

private struct PressureRow: View {
    var label:   String
    var value:   Double
    var isBonus: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(value > 0.01 ? (isBonus ? Color.green : Color.primary) : Color.secondary)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isBonus ? Color.green.opacity(0.7) : Color.red.opacity(0.6))
                        .frame(width: geo.size.width * min(value / (isBonus ? 0.15 : 0.80), 1.0))
                }
            }
            .frame(height: 5)
            Text(isBonus ? String(format: "+%.0f%%", value * 100) : String(format: "−%.0f%%", value * 100))
                .font(.system(size: 10, weight: value > 0.01 ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(value > 0.01 ? (isBonus ? Color.green : Color.red) : Color.secondary)
                .frame(width: 36, alignment: .trailing)
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
