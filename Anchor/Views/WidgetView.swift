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
                        .fill(engine.state.workState.stateColor)
                        .frame(width: 8, height: 8)
                    Text(engine.state.workState.rawValue)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(engine.state.workState.stateColor)
                }

                Divider().frame(height: 12)

                HStack(spacing: 4) {
                    scoreBar
                    Text(String(format: "%.0f%%", engine.state.focusScore * 100))
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundStyle(riskColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WidgetVisualEffect().ignoresSafeArea())
    }

    private var scoreBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(riskColor)
                    .frame(width: geo.size.width * engine.state.focusScore)
            }
        }
        .frame(width: 40, height: 5)
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
