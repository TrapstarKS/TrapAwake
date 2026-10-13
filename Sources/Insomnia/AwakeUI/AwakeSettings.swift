import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AwakeLoginSettings {
    let loginItem = LoginItem()
    private let controller: AwakeController
    private(set) var persistenceError: String?

    var error: String? { persistenceError ?? loginItem.error }
    var isRegistered: Bool { loginItem.isRegistered }

    init(controller: AwakeController) {
        self.controller = controller
    }

    func healAtLaunch() {
        var config = bridgeConfig()
        guard loginItem.healAtLaunch(config: &config) else { return }
        persist(config)
    }

    func set(_ enabled: Bool) {
        var config = bridgeConfig()
        guard loginItem.set(enabled, config: &config) else { return }
        persist(config)
    }

    private func bridgeConfig() -> Config {
        var config = Config()
        config.launchAtLogin = controller.preferences.launchAtLogin
        config.launchAtLoginInstall = controller.preferences.launchAtLoginInstall
        return config
    }

    private func persist(_ config: Config) {
        var preferences = controller.preferences
        preferences.launchAtLogin = config.launchAtLogin
        preferences.launchAtLoginInstall = config.launchAtLoginInstall
        persistenceError = controller.updatePreferences(preferences)
            ? nil
            : "The login item changed, but its preference could not be saved. \(controller.error ?? "Open diagnostics for details.")"
    }
}

@MainActor
final class AwakeSettingsWindow {
    private var window: NSWindow?
    private let controller: AwakeController
    private let login: AwakeLoginSettings

    init(controller: AwakeController, login: AwakeLoginSettings) {
        self.controller = controller
        self.login = login
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: AwakeSettingsView(controller: controller, login: login))
            let window = NSWindow(contentViewController: host)
            window.title = "TrapAwake Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 580, height: 550))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            self.window = window
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AwakeSettingsView: View {
    @Bindable var controller: AwakeController
    @Bindable var login: AwakeLoginSettings
    @State private var defaultMinutes = "60"
    @State private var presetsText = "15, 30, 60, 120, 240, 480"
    @State private var showChangelog = false

    private var timedDefault: Bool { controller.preferences.defaultDuration != nil }
    private var customDefault: TimeInterval? { AwakeDuration.minutes(defaultMinutes) }
    private var parsedPresets: [TimeInterval]? {
        let parts = presetsText.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...12).contains(parts.count) else { return nil }
        let durations = parts.compactMap { AwakeDuration.minutes(String($0)) }
        guard durations.count == parts.count, Set(durations).count == durations.count else { return nil }
        return durations.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = controller.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            TabView {
                general.tabItem { Label("General", systemImage: "gearshape") }
                safety.tabItem { Label("Safety", systemImage: "shield") }
                about.tabItem { Label("About", systemImage: "info.circle") }
            }
            .padding(12)
        }
        .frame(width: 580, height: 550)
        .onAppear {
            defaultMinutes = minutesText(controller.preferences.defaultDuration ?? 3_600)
            presetsText = controller.preferences.presets.map(minutesText).joined(separator: ", ")
            login.loginItem.refresh()
        }
        .onExitCommand { NSApp.keyWindow?.close() }
        .sheet(isPresented: $showChangelog) {
            VStack(alignment: .leading, spacing: 16) {
                Text("What’s new in TrapAwake 0.2.0").font(.title2.weight(.semibold))
                Text("A minimal native menu bar app with one-click awake control, unlimited or timed sessions, an independent screen-awake setting, and battery and thermal protections.")
                Text("Sessions use process-owned macOS power assertions. Quit releases them, and interrupted sessions are reported at the next launch.")
                HStack {
                    Link("Release history on GitHub", destination: URL(string: "https://github.com/TrapstarKS/TrapAwake/releases")!)
                    Spacer()
                    Button("Done") { showChangelog = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 460)
            .onExitCommand { showChangelog = false }
        }
    }

    private var general: some View {
        Form {
            Section {
                HStack {
                    Label(controller.statusText, systemImage: controller.isActive ? "sun.max.fill" : "sun.max")
                        .monospacedDigit()
                    Spacer()
                    Button(controller.isActive ? (controller.recoveryRequired ? "Retry stopping" : "Stop") : "Keep awake") {
                        if controller.isActive { _ = controller.stop() } else { _ = controller.startDefault() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.recoveryRequired && !controller.isActive || controller.isOtherInstance)
                }
                if let warning = controller.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let message = controller.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Current session")
            }
            Section {
                Picker("Menu bar click starts", selection: Binding(
                    get: { timedDefault },
                    set: { timed in
                        update { $0.defaultDuration = timed ? customDefault ?? 3_600 : nil }
                    }
                )) {
                    Text("Unlimited").tag(false)
                    Text("Timed").tag(true)
                }
                .pickerStyle(.segmented)
                if timedDefault {
                    HStack {
                        TextField("Default duration (minutes)", text: $defaultMinutes)
                            .onSubmit(saveDefaultDuration)
                        Button("Apply", action: saveDefaultDuration)
                            .disabled(customDefault == nil || customDefault == controller.preferences.defaultDuration)
                    }
                }
                Toggle("Keep the screen awake", isOn: boolPreference(\.keepDisplayAwake))
                    .help("This applies only while an awake session is running.")
                Toggle("Show a countdown in the menu bar", isOn: boolPreference(\.showCountdown))
            } header: {
                Text("Awake sessions")
            } footer: {
                Text("Click the menu bar icon once to start or stop. Right-click or Option-click for options. Closing the popup leaves the session running.")
            }

            Section {
                TextField("Preset durations (minutes)", text: $presetsText)
                HStack {
                    Text("Separate 1–12 durations with commas.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save presets") {
                        guard let parsedPresets else { return }
                        update { $0.presets = parsedPresets }
                    }
                    .disabled(parsedPresets == nil || parsedPresets == controller.preferences.presets)
                }
            } header: {
                Text("Duration presets")
            } footer: {
                Text("Each duration can be from 1 minute to 30 days.")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { login.isRegistered }, set: { login.set($0) }))
                if login.loginItem.needsApproval {
                    HStack {
                        Text("Waiting for approval in macOS Login Items.").font(.caption)
                        Button("Open Login Items") { login.loginItem.openLoginItems() }
                    }
                }
                if let error = login.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("TrapAwake launches idle. It never automatically starts an awake session.")
            }
        }
        .formStyle(.grouped)
    }

    private var safety: some View {
        Form {
            Section {
                Stepper("Warn on battery at \(controller.preferences.warningBatteryPercent)%", value: Binding(
                    get: { controller.preferences.warningBatteryPercent },
                    set: { value in update { $0.warningBatteryPercent = max(value, $0.criticalBatteryPercent) } }
                ), in: controller.preferences.criticalBatteryPercent...100)
                Stepper("Stop on battery at \(controller.preferences.criticalBatteryPercent)%", value: Binding(
                    get: { controller.preferences.criticalBatteryPercent },
                    set: { value in update { $0.criticalBatteryPercent = value } }
                ), in: 1...controller.preferences.warningBatteryPercent)
            } header: {
                Text("Battery")
            } footer: {
                Text("Battery thresholds apply while running on battery power. The critical battery stop is always enabled.")
            }

            Section {
                Toggle("Stop when macOS reports serious heat", isOn: boolPreference(\.stopOnSeriousHeat))
            } header: {
                Text("Temperature")
            } footer: {
                Text("Critical thermal pressure always stops an awake session. Serious and critical are macOS thermal states, rather than temperature readings.")
            }

            Section {
                Label("Closed-lid overrides are unavailable", systemImage: "laptopcomputer")
                Text("TrapAwake follows normal macOS lid behavior. Supported clamshell operation depends on your Mac, external display, and power setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Open diagnostics") { AwakeDiagnostics.open() }
                if controller.recoveryRequired {
                    Text("A previous session was interrupted. It will not restart automatically.").font(.caption)
                    Button("Acknowledge interrupted session") { _ = controller.acknowledgeRecovery() }
                }
            } header: {
                Text("Recovery")
            } footer: {
                Text("Awake assertions belong to this app process. macOS releases them if the process exits. TrapAwake releases them before quitting.")
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 18) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("TrapAwake").font(.title.weight(.semibold))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")")
                    .foregroundStyle(.secondary)
            }
            Text("Keep your Mac awake, on your terms.")
            Text("An independent fork of Insomnia by Krish Garg (krishhgg), originally released under the MIT license. TrapAwake is not affiliated with or endorsed by the original author.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            HStack(spacing: 20) {
                Link("TrapAwake on GitHub", destination: URL(string: "https://github.com/TrapstarKS/TrapAwake")!)
                Link("Original project", destination: URL(string: "https://github.com/krishhgg/Insomnia")!)
            }
            HStack(spacing: 20) {
                Button("What’s new") { openChangelog() }
                Button("Open diagnostics") { AwakeDiagnostics.open() }
            }
            .buttonStyle(.bordered)
            Text("No root helper. No persistent system power changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func boolPreference(_ keyPath: WritableKeyPath<AwakePreferences, Bool>) -> Binding<Bool> {
        Binding(get: { controller.preferences[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func update(_ change: (inout AwakePreferences) -> Void) {
        var preferences = controller.preferences
        change(&preferences)
        _ = controller.updatePreferences(preferences)
    }

    private func saveDefaultDuration() {
        guard let customDefault else { return }
        update { $0.defaultDuration = customDefault }
    }

    private func minutesText(_ duration: TimeInterval) -> String {
        let minutes = duration / 60
        return minutes == floor(minutes) ? String(Int(minutes)) : String(minutes)
    }

    private func openChangelog() {
        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            showChangelog = true
        }
    }
}

enum AwakeDiagnostics {
    @MainActor static func open() {
        let directory = AwakePaths.fromEnvironment().logFile.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open diagnostics"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
