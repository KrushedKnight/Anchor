import SwiftUI

struct WidgetView: View {
    var engine         = DriftEngine.shared
    var sessionManager = SessionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("Anchor")
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .foregroundStyle(.primary)
                if let title = sessionManager.activeSession?.taskTitle, !title.isEmpty {
                    Text(" · \(title)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(riskColor)
                        .frame(width: 8, height: 8)
                    Text(riskLabel)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(riskColor)
                }

                if engine.state.sessionActive && engine.state.isOffTaskContext {
                    Divider().frame(height: 12)
                    Text("OFF TASK")
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundStyle(.orange)
                }

                Divider().frame(height: 12)

                Text("dwell \(Int(engine.state.dwellInCurrentContext))s")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("\(String(format: "%.1f", engine.state.switchesPerMinute)) sw/min")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WidgetVisualEffect().ignoresSafeArea())
    }

    private var riskColor: Color {
        switch engine.state.riskLevel {
        case .stable: .green
        case .atRisk: .yellow
        case .drift:  .red
        }
    }

    private var riskLabel: String {
        switch engine.state.riskLevel {
        case .stable: "STABLE"
        case .atRisk: "AT RISK"
        case .drift:  "DRIFT"
        }
    }
}

private struct WidgetVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = .hudWindow
        view.blendingMode = .behindWindow
        view.state        = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
