import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @AppStorage("onboarding.complete") private var complete = false
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            stepDots
                .padding(.top, 28)

            Spacer()

            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: NotificationsStep()
                case 2: AccessibilityStep()
                case 3: AIProviderStep()
                default: WelcomeStep()
                }
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)

            Spacer()

            footerButtons
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
        }
        .frame(width: 420, height: 500)
        .background(Color.anchorLinen.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Circle()
                    .fill(i <= step ? Color.anchorTerracotta : Color.anchorBorder)
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.anchorTextMuted)
                    .font(.system(size: 12))
            }
            Spacer()
            Button(step == 3 ? "Get Started" : "Continue") {
                if step == 3 { complete = true } else { step += 1 }
            }
            .buttonStyle(AnchorPrimaryButtonStyle())
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "anchor")
                .font(.system(size: 52))
                .foregroundStyle(Color.anchorTerracotta)

            Text("Welcome to Anchor")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.anchorText)

            Text("Anchor watches what you're doing and gently nudges you back when you drift — so you can stay in flow without willpower.")
                .font(.system(size: 13))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }
}

private struct NotificationsStep: View {
    @State private var granted: Bool? = nil
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge")
                .font(.system(size: 44))
                .foregroundStyle(Color.anchorTerracotta)

            Text("Gentle nudges")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.anchorText)

            Text("Anchor sends a notification when it detects drift. No spam — just a tap on the shoulder when you need it.")
                .font(.system(size: 13))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let granted {
                Label(
                    granted
                        ? "Notifications enabled"
                        : "Denied — enable in System Settings > Notifications.",
                    systemImage: granted ? "checkmark.circle.fill" : "xmark.circle"
                )
                .font(.system(size: 11))
                .foregroundStyle(granted ? Color.anchorSage : .red)
            } else {
                Button("Enable Notifications") {
                    requesting = true
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                        DispatchQueue.main.async {
                            granted = ok
                            requesting = false
                        }
                    }
                }
                .buttonStyle(AnchorPrimaryButtonStyle())
                .disabled(requesting)
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    if settings.authorizationStatus != .notDetermined {
                        granted = settings.authorizationStatus == .authorized
                    }
                }
            }
        }
    }
}

private struct AccessibilityStep: View {
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 44))
                .foregroundStyle(Color.anchorTerracotta)

            Text("Window awareness")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.anchorText)

            Text("Anchor can read window titles to distinguish, say, \"editing code\" from \"browsing docs\". This requires Accessibility permission.")
                .font(.system(size: 13))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if trusted {
                Label("Accessibility granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.anchorSage)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(AnchorPrimaryButtonStyle())

                    Text("Add Anchor, then return here and click Continue.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.anchorTextMuted)
                }
            }

            Text("Optional — Anchor works without it, but context detection is less precise.")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)
        }
        .onAppear { trusted = AXIsProcessTrusted() }
    }
}

private struct AIProviderStep: View {
    var store = APIKeyStore.shared
    @State private var keyInput = ""
    @State private var validationError: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(Color.anchorTerracotta)

            Text("AI classification")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.anchorText)

            Text("Anchor uses AI to classify apps and websites as on-task or off-task. Connect a provider for the best results.")
                .font(.system(size: 13))
                .foregroundStyle(Color.anchorTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(APIProvider.allCases) { provider in
                        Button(provider.displayName) {
                            store.activeProvider = provider
                            keyInput = ""
                            validationError = nil
                        }
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(store.activeProvider == provider ? Color.anchorTerracotta : Color.primary.opacity(0.07))
                        .foregroundStyle(store.activeProvider == provider ? Color.white : Color.anchorText)
                        .cornerRadius(4)
                        .buttonStyle(.plain)
                    }
                }

                switch store.activeProvider {
                case .anthropic, .openAI:
                    onboardingKeyField
                case .ollama:
                    Text("Ollama runs locally — no key needed. Make sure Ollama is running before you start a session.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.anchorTextMuted)
                        .lineSpacing(2)
                }
            }
            .padding(12)
            .background(Color.anchorSand, in: RoundedRectangle(cornerRadius: 10))

            Text("You can change this any time in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(Color.anchorTextMuted)
        }
    }

    private var onboardingKeyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isSet(for: store.activeProvider) {
                HStack(spacing: 6) {
                    Text("●●●●●●●●●●●●")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.anchorTextMuted)
                    Spacer()
                    Button("clear") {
                        store.clear(for: store.activeProvider)
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 6) {
                    SecureField(store.activeProvider.placeholder, text: $keyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .padding(5)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.anchorBorder, lineWidth: 1.5))
                        .cornerRadius(8)
                        .onSubmit { saveKey() }
                    Button("save") { saveKey() }
                        .font(.system(size: 9))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.anchorTerracotta)
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let err = validationError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let err = APIKeyStore.validate(trimmed, for: store.activeProvider) {
            validationError = err
            return
        }
        validationError = store.save(trimmed, for: store.activeProvider)
        if validationError == nil { keyInput = "" }
    }
}
