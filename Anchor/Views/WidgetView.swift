import SwiftUI

struct WidgetView: View {
    var engine         = DriftEngine.shared
    var sessionManager = SessionManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Focus State Mapping

    private var focusTier: FocusTier {
        switch engine.state.riskLevel {
        case .stable: .lockedIn
        case .atRisk: .drifting
        case .drift:  .offTask
        }
    }

    // MARK: - Content

    private var content: some View {
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
    }

    // MARK: - Top Row

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

    // MARK: - Task Name

    private var taskName: some View {
        Text(sessionManager.activeSession?.taskTitle ?? "Focus")
            .font(.system(size: 20, design: .serif))
            .foregroundStyle(Color.widgetTaskText)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.widgetBorder)
                Capsule()
                    .fill(focusTier.dotColor)
                    .frame(width: max(4, geo.size.width * engine.state.focusScore))
                    .animation(.easeInOut(duration: 0.6), value: engine.state.focusScore)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Footer Row

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
        case .lockedIn: Color(red: 0.353, green: 0.541, blue: 0.353)   // #5A8A5A
        case .drifting: Color(red: 0.910, green: 0.627, blue: 0.188)   // #E8A030
        case .offTask:  Color(red: 0.753, green: 0.353, blue: 0.208)   // #C05A35
        }
    }

    var textColor: Color {
        switch self {
        case .lockedIn: Color(red: 0.227, green: 0.420, blue: 0.227)   // #3A6B3A
        case .drifting: Color(red: 0.722, green: 0.471, blue: 0.125)   // #B87820
        case .offTask:  Color(red: 0.600, green: 0.235, blue: 0.114)   // #993C1D
        }
    }
}

// MARK: - Widget Colors

private extension Color {
    static let widgetBorder    = Color(red: 0.894, green: 0.851, blue: 0.784)   // #E4D9C8
    static let widgetSeparator = Color(red: 0.761, green: 0.659, blue: 0.510)   // #C2A882
    static let widgetAppName   = Color(red: 0.549, green: 0.451, blue: 0.333)   // #8C7355
    static let widgetTaskText  = Color(red: 0.110, green: 0.086, blue: 0.071)   // #1C1612
}

// MARK: - End Session Button

private struct WidgetEndButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(Color.widgetAppName)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .background(Color(red: 0.949, green: 0.929, blue: 0.890))  // #F2EDE3
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.widgetBorder, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
