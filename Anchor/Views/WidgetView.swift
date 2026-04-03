import SwiftUI

struct WidgetView: View {
    var engine         = DriftEngine.shared
    var sessionManager = SessionManager.shared

    private var stateColor: Color { engine.state.workState.stateColor }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                statePill
                Spacer()
                elapsedText
            }

            Text(sessionManager.activeSession?.taskTitle ?? "Focus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)

            progressBar

            appRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 210, alignment: .leading)
        .background(WidgetVisualEffect().ignoresSafeArea())
    }

    private var statePill: some View {
        Text(engine.state.workState.rawValue)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(stateColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stateColor.opacity(0.15), in: Capsule())
    }

    private var elapsedText: some View {
        Text(elapsedFormatted)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(stateColor)
                    .frame(width: max(4, geo.size.width * engine.state.focusScore))
                    .animation(.easeInOut(duration: 0.6), value: engine.state.focusScore)
            }
        }
        .frame(height: 3)
    }

    private var appRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appDotColor)
                .frame(width: 6, height: 6)
            Text(engine.state.currentApp.isEmpty ? "—" : engine.state.currentApp)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var appDotColor: Color {
        let fit = engine.state.contextFit
        if fit >= 0.8 { return .green }
        if fit >= 0.4 { return .yellow }
        return .red
    }

    private var elapsedFormatted: String {
        guard let start = sessionManager.activeSession?.startedAt else { return "0:00" }
        let elapsed = Int(Date.now.timeIntervalSince(start))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
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
