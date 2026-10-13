import AppKit
import SwiftUI

struct AwakePopover: View {
    @Bindable var controller: AwakeController
    @Bindable var login: AwakeLoginSettings
    let showSettings: () -> Void
    let close: () -> Void
    @State private var customMinutes = "60"
    @FocusState private var customFocused: Bool

    private var duration: TimeInterval? {
        AwakeDuration.minutes(customMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: controller.isActive ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(controller.isActive ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TrapAwake").font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(stateLine(now: context.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
            }

            notices

            Button {
                if controller.isActive { _ = controller.stop() } else { _ = controller.startDefault() }
            } label: {
                Label(controller.isActive ? (controller.recoveryRequired ? "Retry stopping" : "Stop keeping awake") : "Keep awake", systemImage: controller.isActive ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(controller.recoveryRequired && !controller.isActive || controller.isOtherInstance)

            VStack(alignment: .leading, spacing: 10) {
                Text(controller.isActive ? "Restart with a duration" : "Choose a duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Unlimited") { start(duration: nil) }
                    .frame(maxWidth: .infinity)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(controller.preferences.presets.enumerated()), id: \.offset) { _, duration in
                        Button(AwakeDuration.label(duration)) { start(duration: duration) }
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Minutes", text: $customMinutes)
                        .textFieldStyle(.roundedBorder)
                        .focused($customFocused)
                        .accessibilityLabel("Custom duration in minutes")
                        .onSubmit(startCustom)
                    Text("min").foregroundStyle(.secondary)
                    Button("Start", action: startCustom)
                        .disabled(duration == nil)
                        .accessibilityLabel("Start custom duration")
                }
                Text("Custom duration: 1 minute to 30 days.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .disabled(controller.recoveryRequired || controller.isOtherInstance)

            Divider()

            Toggle("Keep the screen awake", isOn: preference(\.keepDisplayAwake))
                .toggleStyle(.switch)
                .help("While TrapAwake is active, also prevent the display from sleeping.")
            Text("Closing the lid follows normal macOS behavior.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Settings…", action: showSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial)
        .onExitCommand(perform: close)
    }

    @ViewBuilder private var notices: some View {
        if controller.recoveryRequired {
            VStack(alignment: .leading, spacing: 8) {
                Label(controller.isActive ? "Session cleanup needs attention" : "Recovery needs acknowledgement", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                Text(controller.isActive ? "An awake assertion is still active. Retry stopping to release it." : "No session has been restarted. Acknowledge to archive the previous session marker.")
                    .font(.caption)
                if !controller.isActive {
                    Button("Acknowledge and continue") { _ = controller.acknowledgeRecovery() }
                        .buttonStyle(.bordered)
                }
            }
            .foregroundStyle(.orange)
        }
        if let warning = controller.warning {
            Label(warning, systemImage: "battery.25percent")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let error = controller.error {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                if !controller.recoveryRequired, !controller.isOtherInstance {
                    Button("Dismiss error") { controller.clearError() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        } else if let message = controller.message, !controller.recoveryRequired {
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        if let error = login.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func preference(_ keyPath: WritableKeyPath<AwakePreferences, Bool>) -> Binding<Bool> {
        Binding {
            controller.preferences[keyPath: keyPath]
        } set: { value in
            var preferences = controller.preferences
            preferences[keyPath: keyPath] = value
            _ = controller.updatePreferences(preferences)
        }
    }

    private func stateLine(now: Date) -> String {
        guard controller.isActive else { return controller.statusText }
        guard let remaining = controller.remaining(now: now) else { return "Awake · unlimited" }
        return "Awake · \(AwakeDuration.countdown(remaining)) remaining"
    }

    private func startCustom() {
        guard let duration else { return }
        customFocused = false
        start(duration: duration)
    }

    private func start(duration: TimeInterval?) {
        if controller.isActive, !controller.stop() { return }
        if let duration { _ = controller.startTimed(duration: duration) } else { _ = controller.startUnlimited() }
    }
}

enum AwakeDuration {
    static let maximum = AwakePreferences.maximumDuration

    static func minutes(_ text: String) -> TimeInterval? {
        guard let minutes = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              minutes.isFinite, minutes >= 1, minutes * 60 <= maximum else { return nil }
        return minutes * 60
    }

    static func label(_ seconds: TimeInterval) -> String {
        if seconds.truncatingRemainder(dividingBy: 86_400) == 0 { return "\(Int(seconds / 86_400)) \(seconds == 86_400 ? "day" : "days")" }
        if seconds.truncatingRemainder(dividingBy: 3_600) == 0 { return "\(Int(seconds / 3_600)) hr" }
        return "\((seconds / 60).formatted(.number.precision(.fractionLength(0...2)))) min"
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let hours = total / 3_600
        let minutes = total / 60 % 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
