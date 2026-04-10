import SwiftUI

struct WidgetView: View {
    var engine         = DriftEngine.shared
    var sessionManager = SessionManager.shared

    @State private var isHovered = false

    @State private var urgency: WidgetUrgency = .calm
    @State private var nudgeTitle: String = ""
    @State private var nudgeBody: String = ""
    @State private var glowPhase: Bool = false
    @State private var subscriptionId: UUID?
    @State private var listenTask: Task<Void, Never>?
    @State private var collapseTimer: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ZStack(alignment: .topTrailing) {
                Color.clear
                if isHovered || urgency == .assertive {
                    expandedContent
                        .onHover { hovering in
                            if !hovering && urgency != .assertive {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isHovered = false
                                }
                            }
                        }
                } else {
                    collapsedContent
                        .onHover { hovering in
                            if hovering {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    isHovered = true
                                }
                            }
                        }
                }
            }
            .frame(width: 240, height: 140)
        }
        .preferredColorScheme(.light)
        .onAppear { startListening() }
        .onDisappear { stopListening() }
        .onChange(of: engine.state.riskLevel) {
            if engine.state.riskLevel == .stable {
                clearUrgency()
            }
        }
    }

    // MARK: - Intervention Listener

    private func startListening() {
        let (id, stream) = InterventionBus.shared.subscribe()
        subscriptionId = id
        listenTask = Task { @MainActor in
            for await intervention in stream {
                guard intervention.channel == .widget else { continue }
                handleWidgetIntervention(intervention)
            }
        }
    }

    private func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        collapseTimer?.cancel()
        collapseTimer = nil
        if let id = subscriptionId {
            InterventionBus.shared.unsubscribe(id)
            subscriptionId = nil
        }
    }

    private func handleWidgetIntervention(_ intervention: Intervention) {
        nudgeTitle = intervention.title
        nudgeBody  = intervention.body

        switch intervention.level {
        case .ambient:
            if urgency < .assertive {
                withAnimation(.easeInOut(duration: 0.6)) { urgency = .ambient }
                startBreathing()
            }
        case .soft:
            collapseTimer?.cancel()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                urgency = .assertive
                isHovered = false
            }
            scheduleAutoCollapse()
        default:
            break
        }
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            glowPhase = true
        }
    }

    private func scheduleAutoCollapse() {
        collapseTimer?.cancel()
        collapseTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(InterventionConfig.defaults.assertiveDisplayTime))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                if urgency == .assertive { urgency = .ambient }
            }
        }
    }

    private func dismissNudge() {
        collapseTimer?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            urgency = .ambient
        }
    }

    private func clearUrgency() {
        collapseTimer?.cancel()
        withAnimation(.easeOut(duration: 0.4)) {
            urgency = .calm
            glowPhase = false
        }
    }

    // MARK: - Focus Tier

    private var focusTier: FocusTier {
        if sessionManager.isPaused { return .onBreak }
        switch engine.state.workState {
        case .deepFocus, .productiveSwitching: return .lockedIn
        case .stuckCycling, .noveltySeeking:   return .drifting
        case .passiveDrift:                    return .offTask
        case .idle:                            return .away
        }
    }

    // MARK: - Collapsed (Pill)

    private var collapsedContent: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(focusTier.dotColor)
                .frame(width: 7, height: 7)

            if urgency == .ambient {
                Text(nudgeTitle.isEmpty ? focusTier.label : nudgeTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(focusTier.textColor)
                Text("·")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.widgetSeparator)
                Text(taskNameForPill)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Color.widgetAppName)
                    .lineLimit(1)
            } else {
                Text(focusTier.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(focusTier.textColor)
                Text("·")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.widgetSeparator)
                Text(collapsedRightText)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(Color.widgetAppName)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.anchorLinen)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(pillBorderColor, lineWidth: urgency == .ambient ? 1.5 : 1))
        .shadow(
            color: urgency == .ambient ? focusTier.dotColor.opacity(glowPhase ? 0.5 : 0.0) : .clear,
            radius: glowPhase ? 8 : 0
        )
        .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
    }

    private var pillBorderColor: Color {
        urgency == .ambient ? focusTier.dotColor.opacity(0.6) : Color.widgetBorder
    }

    private var taskNameForPill: String {
        sessionManager.activeSession?.taskTitle ?? "Focus"
    }

    private var collapsedRightText: String {
        if focusTier == .lockedIn && engine.state.focusStreakSeconds >= 600 {
            return formatStreak(engine.state.focusStreakSeconds)
        }
        return "Anchor"
    }

    private func formatStreak(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    // MARK: - Expanded (Full)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow

            if urgency == .assertive {
                nudgeBanner
            } else {
                taskName
            }

            if let pomo = sessionManager.pomodoroTimer {
                pomodoroSection(pomo)
            } else if sessionManager.isPaused {
                breakBanner
            } else {
                progressBar
            }

            footerRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 240, alignment: .leading)
        .background(Color.anchorLinen)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(expandedBorderColor, lineWidth: urgency != .calm ? 1.5 : 1)
        )
        .shadow(
            color: urgency != .calm ? focusTier.dotColor.opacity(glowPhase ? 0.35 : 0.0) : .clear,
            radius: glowPhase ? 10 : 0
        )
        .transition(.scale(scale: 0.95, anchor: .topTrailing).combined(with: .opacity))
    }

    private var expandedBorderColor: Color {
        urgency != .calm ? focusTier.dotColor.opacity(0.5) : Color.widgetBorder
    }

    // MARK: - Nudge Banner

    private var nudgeBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nudgeTitle)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundStyle(focusTier.textColor)
                .lineLimit(2)
            if !nudgeBody.isEmpty {
                Text(nudgeBody)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.widgetAppName)
                    .lineLimit(2)
            }
        }
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

    private var breakBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.widgetBreakAccent)
            Text(breakElapsedFormatted)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(Color.widgetBreakAccent)
            Spacer()
            Button("Resume") {
                SessionManager.shared.resume()
            }
            .buttonStyle(WidgetSmallButtonStyle())
        }
    }

    private func pomodoroSection(_ pomo: PomodoroTimer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<pomo.config.cyclesBeforeLongBreak, id: \.self) { i in
                    Circle()
                        .fill(i < pomo.completedCycles ? Color.anchorSage : Color.widgetBorder)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Text(pomo.phase.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(pomo.phase.isBreak ? Color.widgetBreakAccent : Color.anchorSage)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.widgetBorder)
                    Capsule()
                        .fill(pomo.phase.isBreak ? Color.widgetBreakAccent : Color.anchorSage)
                        .frame(width: max(4, geo.size.width * pomo.progress))
                }
            }
            .frame(height: 5)

            if pomo.isWaitingForUser {
                pomodoroPrompt(pomo)
            } else {
                Text(formatInterval(pomo.phaseRemaining))
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Color.widgetAppName)
            }
        }
    }

    private func pomodoroPrompt(_ pomo: PomodoroTimer) -> some View {
        HStack(spacing: 6) {
            Text(pomo.phase == .work ? "Time for a break!" : "Ready to focus?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.widgetTaskText)
            Spacer()
            if pomo.phase.isBreak {
                Button("Skip") { pomo.skipBreak() }
                    .buttonStyle(WidgetSmallButtonStyle())
            }
            Button(pomo.phase == .work ? "Break" : "Go") {
                pomo.advancePhase()
            }
            .buttonStyle(WidgetSmallButtonStyle())
        }
    }

    private var footerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(workTimeFormatted)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color.widgetAppName)
                if sessionManager.breakTracker.breakCount > 0 {
                    Text("\(sessionManager.breakTracker.breakCount) break\(sessionManager.breakTracker.breakCount == 1 ? "" : "s")")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.widgetAppName.opacity(0.6))
                }
            }
            Spacer()

            if urgency == .assertive {
                Button("Dismiss") { dismissNudge() }
                    .buttonStyle(WidgetSmallButtonStyle())
            }

            if !sessionManager.isPaused && !sessionManager.isPomodoro {
                Button("Break") {
                    SessionManager.shared.pause(reason: "manual")
                }
                .buttonStyle(WidgetSmallButtonStyle())
            }
            Button("End") {
                SessionManager.shared.end(reason: "manual")
            }
            .buttonStyle(WidgetEndButtonStyle())
        }
    }

    // MARK: - Timer Formatting

    private var workTimeFormatted: String {
        formatInterval(sessionManager.activeWorkTime)
    }

    private var breakElapsedFormatted: String {
        guard let start = sessionManager.breakTracker.currentBreakStart else { return "0:00" }
        return formatInterval(Date.now.timeIntervalSince(start))
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        let elapsed = max(0, Int(interval))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Widget Urgency

private enum WidgetUrgency: Int, Comparable {
    case calm = 0, ambient = 1, assertive = 2
    static func < (l: WidgetUrgency, r: WidgetUrgency) -> Bool { l.rawValue < r.rawValue }
}

// MARK: - Focus Tier

private enum FocusTier: Equatable {
    case lockedIn, drifting, offTask, away, onBreak

    var label: String {
        switch self {
        case .lockedIn: "Locked in"
        case .drifting: "Drifting"
        case .offTask:  "Off task"
        case .away:     "Away"
        case .onBreak:  "On break"
        }
    }

    var dotColor: Color {
        switch self {
        case .lockedIn: Color.anchorSage
        case .drifting: Color.anchorAmber
        case .offTask:  Color(red: 0.753, green: 0.353, blue: 0.208)
        case .away:     Color.anchorTextMuted
        case .onBreak:  Color.widgetBreakAccent
        }
    }

    var textColor: Color {
        switch self {
        case .lockedIn: Color(red: 0.227, green: 0.420, blue: 0.227)
        case .drifting: Color(red: 0.722, green: 0.471, blue: 0.125)
        case .offTask:  Color(red: 0.600, green: 0.235, blue: 0.114)
        case .away:     Color.anchorTextMuted
        case .onBreak:  Color(red: 0.306, green: 0.439, blue: 0.573)
        }
    }
}

// MARK: - Button Styles

private struct WidgetSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.widgetAppName)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Color(red: 0.949, green: 0.929, blue: 0.890).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.widgetBorder.opacity(0.5), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

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
