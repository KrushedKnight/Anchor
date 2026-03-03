import SwiftUI

struct ContentView: View {
    var store = EventStore.shared

    var body: some View {
        ScrollViewReader { proxy in
            List(store.events) { event in
                EventRow(event: event)
                    .id(event.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            }
            .onChange(of: store.events.count) {
                if let last = store.events.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 420)
    }
}

struct EventRow: View {
    let event: AnchorEvent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formattedTime(event.ts))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(event.type)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(typeColor)
                .frame(width: 130, alignment: .leading)

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
