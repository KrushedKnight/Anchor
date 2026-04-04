import SwiftUI

struct WidgetView: View {
    var engine         = DriftEngine.shared
    var sessionManager = SessionManager.shared

    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack(alignment: .topTrailing) {
                Color.clear
                if isHovered { expandedContent } else { collapsedContent }
            }
            .frame(width: 240, height: 140)
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isHovered = hovering
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Focus Tier

    private var focusTier: FocusTier {
        switch engine.state.workState {
        case .deepFocus, .productiveSwitching: .lockedIn
        case .stuckCycling, .noveltySeeking:   .drifting
        case .passiveDrift, .idle:             .offTask
        }
    }

    // MARK: - Collapsed (Pill)

    private var collapsedContent: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(focusTier.dotColor)
                .frame(width: 7, height: 7)
            Text(focusTier.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focusTier.textColor)
            Text("·")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.widgetSeparator)
            Text(elapsedFormatted)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundStyle(Color.widgetAppName)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.anchorLinen)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.widgetBorder, lineWidth: 1))
        .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
    }

    // MARK: - Expanded (Full)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            taskName
            progressBar
            footerRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 240, alignment: .leading)
        .background(Color.anchorLinen)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.widgetBorder, lineWidth: 1)
        )
        .transition(.scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
    }

    // MARK: - Expanded Subviews

    private var topRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(focusTier.dotColor)
                .frame(width: 7, height: 7)
            Text(focusTier.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focusTier.textColor)
            Text("·")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.widgetSeparator)
            Text(engine.state.currentApp.isEmpty ? "—" : engine.state.currentApp)
                .font(.system(size: 11))
                .foregroundStyle(Color.widgetAppName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var taskName: some View {
        Text(sessionManager.activeSession?.taskTitle ?? "Focus")
            .font(.system(size: 20, design: .serif))
            .foregroundStyle(Color.widgetTaskText)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.widgetBorder)
                Capsule()
                    .fill(focusTier.dotColor)
                    .frame(width: max(4, geo.size.width * engine.state.focusScore))
            }
        }
        .frame(height: 5)
        .animation(.easeInOut(duration: 0.6), value: engine.state.focusScore)
        .animation(.easeInOut(duration: 0.4), value: engine.state.workState.rawValue)
    }

    private var footerRow: some View {
        HStack {
            Text(elapsedFormatted)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Color.widgetAppName)
            Spacer()
            Button("End session") {
                SessionManager.shared.end(reason: "manual")
            }
            .buttonStyle(WidgetEndButtonStyle())
        }
    }

    // MARK: - Elapsed

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

// MARK: - Focus Tier

private enum FocusTier {
    case lockedIn, drifting, offTask

    var label: String {
        switch self {
        case .lockedIn: "Locked in"
        case .drifting: "Drifting"
        case .offTask:  "Off task"
        }
    }

    var dotColor: Color {
        switch self {
        case .lockedIn: Color(red: 0.353, green: 0.541, blue: 0.353)
        case .drifting: Color(red: 0.910, green: 0.627, blue: 0.188)
        case .offTask:  Color(red: 0.753, green: 0.353, blue: 0.208)
        }
    }

    var textColor: Color {
        switch self {
        case .lockedIn: Color(red: 0.227, green: 0.420, blue: 0.227)
        case .drifting: Color(red: 0.722, green: 0.471, blue: 0.125)
        case .offTask:  Color(red: 0.600, green: 0.235, blue: 0.114)
        }
    }
}

// MARK: - Widget Colors

private extension Color {
    static let widgetBorder    = Color(red: 0.894, green: 0.851, blue: 0.784)
    static let widgetSeparator = Color(red: 0.761, green: 0.659, blue: 0.510)
    static let widgetAppName   = Color(red: 0.549, green: 0.451, blue: 0.333)
    static let widgetTaskText  = Color(red: 0.110, green: 0.086, blue: 0.071)
}

// MARK: - End Session Button

private struct WidgetEndButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(Color.widgetAppName.opacity(0.5))
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .background(Color(red: 0.949, green: 0.929, blue: 0.890).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.widgetBorder.opacity(0.5), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
