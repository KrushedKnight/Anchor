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
    @State private var taskTitle:           String                         = ""
    @State private var classifications:     [String: ContextFitLevel]      = [:]
    @State private var runningApps:         [String]                       = []
    @State private var isClassifying:       Bool                           = false
    @State private var classifyDebounce:    Task<Void, Never>?             = nil

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
                    .onChange(of: taskTitle) { _, newValue in
                        scheduleClassification(for: newValue)
                    }
            }

            if !classifications.isEmpty || isClassifying {
                ClassificationPreview(classifications: classifications, isLoading: isClassifying)
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
            taskTitle:          taskTitle,
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
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            if !onTask.isEmpty {
                ClassificationRow(label: "on-task", apps: onTask, color: .green)
            }
            if !ambiguous.isEmpty {
                ClassificationRow(label: "neutral", apps: ambiguous, color: .yellow)
            }
            if !offTask.isEmpty {
                ClassificationRow(label: "distractor", apps: offTask, color: .red)
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
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
                    SessionRow(label: "Task",    value: session.taskTitle.isEmpty ? "—" : session.taskTitle)
                    SessionRow(label: "Started", value: session.startedAt.formatted(date: .omitted, time: .shortened))
                    SessionRow(
                        label:      "Context",
                        value:      contextLabel,
                        valueColor: contextColor
                    )
                }
            }

            DebugPanel(state: engine.state, snap: BehaviorAnalyzer.shared.snapshot)

            Button("End Session") { SessionManager.shared.end() }
                .buttonStyle(DestructiveButtonStyle())
        }
        .padding(28)
        .frame(width: 320)
    }

    private var contextLabel: String {
        let fit = engine.state.contextFit
        if fit >= 0.8 { return "ON TASK" }
        if fit >= 0.4 { return "NEUTRAL" }
        return "OFF TASK"
    }

    private var contextColor: Color {
        let fit = engine.state.contextFit
        if fit >= 0.8 { return .green }
        if fit >= 0.4 { return .yellow }
        return .orange
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("DEBUG")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)

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
                DebugMetric(label: "quality", value: String(format: "%.0f%%", state.focusQuality * 100))
                DebugMetric(label: "base",  value: String(format: "%.0f%%", state.workState.baseTargetScore * 100))
                DebugMetric(label: "floor", value: String(format: "%.0f%%", state.workState.decayFloor * 100))
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

            ProviderSettingsSection()
        }
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

private struct ProviderSettingsSection: View {
    var store = APIKeyStore.shared
    @State private var keyInput:      String = ""
    @State private var ollamaEndpoint: String = ""
    @State private var ollamaModel:    String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("AI PROVIDER")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

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
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
            .foregroundStyle(isSelected ? .white : .primary)
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
                    .foregroundStyle(.secondary)
                Spacer()
                Button("clear") { store.clear(for: provider) }
                    .font(.system(size: 9, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        } else {
            HStack(spacing: 6) {
                SecureField(provider.placeholder, text: $keyInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .onSubmit { save() }
                Button("save") { save() }
                    .font(.system(size: 9, design: .monospaced))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
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
            DebugMetric(label: "endpoint", value: "")
            TextField("http://localhost:11434", text: $endpoint)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .padding(5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .onSubmit { save() }

            DebugMetric(label: "model", value: "")
            TextField("e.g. mistral, llama2", text: $model)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .padding(5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .onSubmit { save() }

            Button("save") { save() }
                .font(.system(size: 9, design: .monospaced))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
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
