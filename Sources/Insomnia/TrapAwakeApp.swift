import AppKit
import SwiftUI

struct TrapAwakeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: TrapAwakeAppDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class TrapAwakeAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AwakeController()
    private var statusItem: AwakeStatusItem?
    private var settingsWindow: AwakeSettingsWindow?
    private var terminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let login = AwakeLoginSettings(controller: controller)
        login.healAtLaunch()
        let settings = AwakeSettingsWindow(controller: controller, login: login)
        settingsWindow = settings
        statusItem = AwakeStatusItem(controller: controller, login: login) { [weak self] in
            self?.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showDurationEditor()
        return false
    }

    func showSettings() {
        statusItem?.closeDurationEditor()
        statusItem?.closePopover()
        settingsWindow?.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        terminating = true
        guard controller.shutdown() else {
            terminating = false
            statusItem?.showPopover()
            return .terminateCancel
        }
        statusItem?.invalidate()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = controller.shutdown()
        statusItem?.invalidate()
    }
}
