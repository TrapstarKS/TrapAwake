import AppKit
import Observation
import SwiftUI

@MainActor
final class AwakeStatusItem: NSObject {
    private let controller: AwakeController
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let showSettings: () -> Void
    private var countdownTimer: Timer?
    private var keyMonitor: Any?
    private var invalidated = false
    private var lastError: String?
    private var warningWasVisible = false
    private var lastProtectionReason: String?
    private var presentationGeneration = 0

    init(controller: AwakeController, login: AwakeLoginSettings, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        let position = "NSStatusItem Preferred Position TrapAwake.status"
        if UserDefaults.standard.object(forKey: position) == nil {
            UserDefaults.standard.set(40, forKey: position)
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "TrapAwake.status"
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: AwakePopover(
            controller: controller,
            login: login,
            showSettings: showSettings,
            close: { [weak self] in self?.closePopover() }
        ))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self else { return false }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.contains(.command), event.charactersIgnoringModifiers == "," {
                    self.closePopover()
                    self.showSettings()
                    return true
                }
                if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
                    NSApp.terminate(nil)
                    return true
                }
                if self.popover.isShown, event.keyCode == 53 {
                    self.closePopover()
                    return true
                }
                return false
            }
            return handled ? nil : event
        }
        observeController()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let opensOptions = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
            || event?.modifierFlags.contains(.control) == true
        if opensOptions {
            if popover.isShown { closePopover() } else { showPopover() }
            return
        }
        let succeeded = controller.isActive ? controller.stop() : controller.startDefault()
        refreshStatus()
        if !succeeded { showPopover() }
    }

    func showPopover() {
        guard !invalidated else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated, self.presentationGeneration == generation else { return }
            self.presentPopover()
        }
    }

    private func presentPopover() {
        guard let button = item.button, let window = button.window else {
            Log.info("options: status anchor missing; showing Settings")
            showSettings()
            return
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let onScreen = NSScreen.screens.contains { screen in
            guard screen.frame.intersects(anchor) else { return false }
            guard screen.safeAreaInsets.top > 0 else { return true }
            let center = NSPoint(x: anchor.midX, y: anchor.midY)
            return screen.auxiliaryTopLeftArea?.contains(center) == true
                || screen.auxiliaryTopRightArea?.contains(center) == true
        }
        let visible = window.isVisible && !button.isHiddenOrHasHiddenAncestor && window.alphaValue > 0 && onScreen
        Log.info("options: status anchor \(NSStringFromRect(anchor)), visible \(visible), window visible \(window.isVisible), active \(NSApp.isActive)")
        guard visible else {
            Log.info("options: status anchor hidden or offscreen; showing Settings")
            showSettings()
            return
        }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        Log.info("options: popover shown \(popover.isShown), window visible \(popover.contentViewController?.view.window?.isVisible == true)")
    }

    func closePopover() {
        presentationGeneration += 1
        popover.performClose(nil)
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        closePopover()
        NSStatusBar.system.removeStatusItem(item)
    }

    private func observeController() {
        guard !invalidated else { return }
        withObservationTracking {
            _ = controller.session
            _ = controller.preferences
            _ = controller.error
            _ = controller.recoveryRequired
            _ = controller.message
            _ = controller.warning
            _ = controller.protectionReason
            refreshStatus()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeController() }
        }
    }

    private func refreshStatus() {
        guard let button = item.button else { return }
        let active = controller.isActive
        let attention = controller.error ?? controller.warning ?? controller.protectionReason
        let symbol = attention != nil ? "exclamationmark.circle.fill" : active ? "sun.max.fill" : "sun.max"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TrapAwake")
        button.image?.isTemplate = true
        let countdown = controller.preferences.showCountdown ? controller.countdownText : nil
        button.title = countdown.map { " \($0)" } ?? ""
        let state = controller.statusText
        let hint = "Click to \(active ? "stop" : "start"). Right-click or Option-click for options."
        let detail = attention.map { "\n\($0)" } ?? ""
        button.toolTip = "TrapAwake — \(state)\(detail)\n\(hint)"
        button.setAccessibilityLabel("TrapAwake, \(state)\(detail)")
        button.setAccessibilityHelp(hint)
        button.setAccessibilityValue(active ? "Awake enabled" : "Awake disabled")
        let showAttention = controller.error != nil && controller.error != lastError
            || controller.warning != nil && !warningWasVisible
            || controller.protectionReason != nil && controller.protectionReason != lastProtectionReason
        lastError = controller.error
        warningWasVisible = controller.warning != nil
        lastProtectionReason = controller.protectionReason
        if showAttention { showPopover() }
        if active, controller.remaining() != nil, countdownTimer == nil {
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStatus() }
            }
        } else if !active || controller.remaining() == nil {
            countdownTimer?.invalidate()
            countdownTimer = nil
        }
    }
}
