import SwiftUI

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
    @State private var taskTitle:  String                  = ""
    @State private var strictness: FocusSession.Strictness = .normal

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

            Button("Start Session") { tryStart() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(28)
        .frame(width: 320)
    }

    private func tryStart() {
        guard !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        SessionManager.shared.start(taskTitle: taskTitle, strictness: strictness)
    }
}

struct SessionActiveView: View {
    var sessionManager = SessionManager.shared

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
                }
            }

            Button("End Session") { SessionManager.shared.end() }
                .buttonStyle(DestructiveButtonStyle())
        }
        .padding(28)
        .frame(width: 320)
    }
}

private struct SessionRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
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
