import SwiftUI

struct ContentView: View {
    var store  = EventStore.shared
    var engine = DriftEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            RiskBanner(state: engine.state)
            Divider()
            ScrollViewReader { proxy in
                List(store.log) { event in
                    EventRow(event: event)
                        .id(event.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                }
                .scrollContentBackground(.hidden)
                .onChange(of: store.log.count) {
                    if let last = store.log.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 120)
        .background(VisualEffect().ignoresSafeArea())
    }
}

struct RiskBanner: View {
    let state: EngineState

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(riskColor)
                .frame(width: 10, height: 10)
            Text(riskLabel)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(riskColor)
            Spacer()
            if !state.currentApp.isEmpty {
                Text(state.currentApp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !state.currentDomain.isEmpty {
                Text(state.currentDomain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text("dwell \(Int(state.dwellInCurrentContext))s")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("\(String(format: "%.1f", state.switchesPerMinute)) sw/min")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(riskColor.opacity(0.08))
    }

    private var riskColor: Color {
        switch state.riskLevel {
        case .stable: return .green
        case .atRisk: return .yellow
        case .drift:  return .red
        }
    }

    private var riskLabel: String {
        switch state.riskLevel {
        case .stable: return "STABLE"
        case .atRisk: return "AT RISK"
        case .drift:  return "DRIFT"
        }
    }
}

struct EventRow: View {
    let event: AnchorEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formattedTime(event.ts))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(event.type)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(typeColor)
                .frame(width: 110, alignment: .leading)

            Text(dataString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
    }

    private var dataString: String {
        event.data
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }

    private var typeColor: Color {
        switch event.type {
        case "active_app":     return .blue
        case "browser_domain": return .green
        case "idle_start":     return .orange
        case "idle_end":       return .purple
        default:               return .primary
        }
    }

    private func formattedTime(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        return timeFormatter.string(from: date)
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

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
