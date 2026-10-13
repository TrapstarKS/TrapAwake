import AppKit
import Observation
import SwiftUI

@MainActor
final class AwakeStatusItem: NSObject {
    private let controller: AwakeController
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let showSettings: () -> Void
    private let icon = AwakeFieldButton()
    private let countdown = AwakeFieldButton()
    private let stopButton = AwakeFieldButton()
    private var fields: [DurationInput.Field: AwakeFieldButton] = [:]
    private var editor: AwakeDurationEditor?
    private var rejected = false
    private var widthWriter: StatusWidthWriter?
    private var keyCatcher: KeyCatcherPanel?
    private var editorKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var commandMonitor: Any?
    private var invalidated = false
    private var lastError: String?
    private var warningWasVisible = false
    private var lastProtectionReason: String?
    private var presentationGeneration = 0

    init(controller: AwakeController, login: AwakeLoginSettings, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        let position = "NSStatusItem Preferred Position TrapAwake.status"
        if UserDefaults.standard.object(forKey: position) == nil { UserDefaults.standard.set(40, forKey: position) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "TrapAwake.status"
        super.init()
        installButtons()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: AwakePopover(
            controller: controller, login: login, showSettings: showSettings,
            close: { [weak self] in self?.closePopover() }
        ))
        commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleCommand(event) ?? false }
            return handled ? nil : event
        }
        observeController()
    }

    isolated deinit { invalidate() }

    private func installButtons() {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.image = nil
        button.title = ""
        widthWriter = StatusWidthWriter { [item] width in item.length = width }
        for control in [icon, countdown, stopButton] {
            control.isBordered = false
            control.target = self
            control.onContextMenu = { [weak self] in self?.showContextMenu() }
            button.addSubview(control)
        }
        icon.imagePosition = .imageOnly
        icon.action = #selector(clicked(_:))
        countdown.action = #selector(clicked(_:))
        countdown.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        stopButton.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stop current session")
        stopButton.image?.isTemplate = true
        stopButton.imagePosition = .imageOnly
        stopButton.action = #selector(stopSession)
        stopButton.toolTip = "Stop the current awake session"
        stopButton.setAccessibilityLabel("Stop current awake session")
        for field in DurationInput.Field.allCases {
            let control = AwakeFieldButton()
            control.tag = field.rawValue
            control.target = self
            control.action = #selector(selectField(_:))
            control.onContextMenu = { [weak self] in self?.showContextMenu() }
            control.bezelStyle = .roundRect
            control.controlSize = .small
            control.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            control.setAccessibilityLabel(field.placeholder)
            fields[field] = control
            button.addSubview(control)
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true || event?.modifierFlags.contains(.option) == true {
            showContextMenu()
        } else if editor != nil {
            closeDurationEditor()
        } else {
            showDurationEditor()
        }
    }

    func showDurationEditor() {
        guard !invalidated else { return }
        guard !controller.recoveryRequired, !controller.isOtherInstance else { showPopover(); return }
        closePopover()
        guard let button = item.button, anchorIsVisible(button) else {
            Log.info("duration editor: status anchor hidden; showing Settings")
            showSettings()
            return
        }
        if editor == nil { editor = AwakeDurationEditor() }
        rejected = false
        refreshStatus()
        installEditorMonitors()
    }

    func closeDurationEditor() {
        removeEditorMonitors()
        editor = nil
        rejected = false
        refreshStatus()
    }

    @objc private func selectField(_ sender: NSButton) {
        guard let field = DurationInput.Field(rawValue: sender.tag), editor != nil else { return }
        editor?.focused = field
        rejected = false
        refreshStatus()
        keyCatcher?.makeKeyAndOrderFront(nil)
    }

    private func commitDuration() {
        guard let editor else { return }
        guard editor.action(controller: controller) != .reject else { rejectInput(); return }
        if editor.commit(controller: controller) {
            closeDurationEditor()
        } else {
            showPopover()
        }
    }

    private func rejectInput() {
        rejected = true
        NSSound.beep()
        refreshStatus()
    }

    private func installEditorMonitors() {
        removeEditorMonitors()
        guard let button = item.button else { return }
        let panel = KeyCatcherPanel()
        panel.move(toStatusButton: button)
        panel.makeKeyAndOrderFront(nil)
        keyCatcher = panel
        editorKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleEditorKey(event) ?? false }
            return handled ? nil : event
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.editor != nil else { return }
                if event.window !== self.item.button?.window, event.window !== self.keyCatcher { self.closeDurationEditor() }
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak panel] _ in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel, self.keyCatcher === panel else { return }
                self.closeDurationEditor()
            }
        }
    }

    private func removeEditorMonitors() {
        for monitor in [editorKeyMonitor, localMouseMonitor, globalMouseMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        editorKeyMonitor = nil
        localMouseMonitor = nil
        globalMouseMonitor = nil
        keyCatcher?.orderOut(nil)
        keyCatcher = nil
    }

    private func handleCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers == "," {
            closeDurationEditor()
            closePopover()
            showSettings()
            return true
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
            NSApp.terminate(nil)
            return true
        }
        if popover.isShown, event.keyCode == 53 { closePopover(); return true }
        return false
    }

    private func handleEditorKey(_ event: NSEvent) -> Bool {
        guard let focused = editor?.focused else { return false }
        if handleCommand(event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        switch event.keyCode {
        case 53: closeDurationEditor(); return true
        case 36, 76: commitDuration(); return true
        case 48: editor?.focused = flags.contains(.shift) ? focused.previous : focused.next
        case 123: editor?.focused = focused.previous
        case 124: editor?.focused = focused.next
        case 51, 117: editor?.backspace()
        default:
            guard let text = event.charactersIgnoringModifiers, text.count == 1, let character = text.first else { return false }
            if let digit = character.wholeNumberValue, character.isASCII {
                if editor?.append(digit) != true { rejectInput(); return true }
            } else {
                switch character.lowercased() {
                case "d": editor?.focused = .days
                case "h": editor?.focused = .hours
                case "m": editor?.focused = .minutes
                default: return character.isLetter || character.isPunctuation || character == " "
                }
            }
        }
        rejected = false
        refreshStatus()
        return true
    }

    private func showContextMenu() {
        closeDurationEditor()
        closePopover()
        guard let button = item.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let status = NSMenuItem(title: "TrapAwake — \(controller.statusText)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let unlimited = menuItem("Unlimited (until disabled)", action: #selector(startUnlimited))
        unlimited.state = Self.unlimitedIsSelected(controller) ? .on : .off
        unlimited.isEnabled = canStart
        menu.addItem(unlimited)
        let timed = NSMenuItem(title: "Timed presets", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        durations.autoenablesItems = false
        for duration in controller.preferences.presets {
            let preset = menuItem(AwakeDuration.label(duration), action: #selector(startPreset(_:)))
            preset.representedObject = duration
            preset.isEnabled = canStart
            durations.addItem(preset)
        }
        durations.addItem(.separator())
        let customTitle = controller.isActive ? (controller.remaining() != nil ? "Add time…" : "Set timed duration…") : "Custom duration…"
        let custom = menuItem(customTitle, action: #selector(openCustomDuration))
        custom.isEnabled = canStart
        durations.addItem(custom)
        timed.submenu = durations
        timed.isEnabled = canStart
        menu.addItem(timed)
        let stop = menuItem(controller.recoveryRequired ? "Retry stopping session" : "Stop session", action: #selector(stopSession))
        stop.isEnabled = controller.isActive || controller.session != nil
        menu.addItem(stop)
        menu.addItem(.separator())
        let display = menuItem("Keep screen awake", action: #selector(toggleDisplay))
        display.state = controller.preferences.keepDisplayAwake ? .on : .off
        display.isEnabled = !controller.isOtherInstance
        menu.addItem(display)
        if controller.error != nil || controller.warning != nil || controller.protectionReason != nil {
            menu.addItem(menuItem("View safety notice…", action: #selector(openAttention)))
        }
        if controller.recoveryRequired {
            let recover = menuItem("Acknowledge interrupted session", action: #selector(acknowledgeRecovery))
            recover.isEnabled = !controller.isActive && !controller.isOtherInstance
            menu.addItem(recover)
        }
        menu.addItem(menuItem("Open diagnostics", action: #selector(openDiagnostics)))
        menu.addItem(.separator())
        let settings = menuItem("Settings…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        let quit = menuItem("Quit TrapAwake", action: #selector(quit))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private var canStart: Bool { !controller.recoveryRequired && !controller.isOtherInstance }

    static func unlimitedIsSelected(_ controller: AwakeController) -> Bool {
        controller.isActive && controller.session != nil && controller.session?.endsAt == nil
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func startUnlimited() {
        guard !Self.unlimitedIsSelected(controller) else { return }
        if controller.isActive, !controller.stop() { showPopover(); return }
        if !controller.startUnlimited() { showPopover() }
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        if controller.isActive, !controller.stop() { showPopover(); return }
        if !controller.startTimed(duration: duration) { showPopover() }
    }

    @objc private func openCustomDuration() {
        DispatchQueue.main.async { [weak self] in self?.showDurationEditor() }
    }

    @objc private func stopSession() {
        closeDurationEditor()
        if !controller.stop() { showPopover() }
    }

    @objc private func toggleDisplay() {
        var preferences = controller.preferences
        preferences.keepDisplayAwake.toggle()
        if !controller.updatePreferences(preferences) { showPopover() }
    }

    @objc private func acknowledgeRecovery() { if !controller.acknowledgeRecovery() { showPopover() } }
    @objc private func openAttention() { showPopover() }
    @objc private func openDiagnostics() { AwakeDiagnostics.open() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showPopover() {
        guard !invalidated else { return }
        closeDurationEditor()
        presentationGeneration += 1
        let generation = presentationGeneration
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.invalidated, self.presentationGeneration == generation else { return }
            guard let button = self.item.button, self.anchorIsVisible(button) else { self.showSettings(); return }
            self.popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !self.popover.isShown { self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
            self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func anchorIsVisible(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.isVisible, !button.isHiddenOrHasHiddenAncestor else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSScreen.screens.contains { screen in
            guard screen.frame.intersects(anchor) else { return false }
            guard screen.safeAreaInsets.top > 0 else { return true }
            let center = NSPoint(x: anchor.midX, y: anchor.midY)
            return screen.auxiliaryTopLeftArea?.contains(center) == true || screen.auxiliaryTopRightArea?.contains(center) == true
        }
    }

    func closePopover() {
        presentationGeneration += 1
        popover.performClose(nil)
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        removeEditorMonitors()
        if let commandMonitor { NSEvent.removeMonitor(commandMonitor) }
        commandMonitor = nil
        closePopover()
        NSStatusBar.system.removeStatusItem(item)
    }

    private func observeController() {
        guard !invalidated else { return }
        withObservationTracking {
            refreshStatus()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeController() }
        }
    }

    private func refreshStatus() {
        guard !invalidated, let button = item.button else { return }
        let active = controller.isActive
        let attention = controller.error ?? controller.warning ?? controller.protectionReason
        icon.image = NSImage(systemSymbolName: attention != nil ? "exclamationmark.circle.fill" : active ? "sun.max.fill" : "sun.max", accessibilityDescription: "TrapAwake")
        icon.image?.isTemplate = true
        let state = controller.statusText
        let hint = "Click to edit Days, Hours, Minutes. Right-click for options."
        button.toolTip = "TrapAwake — \(state)\n\(attention ?? hint)"
        button.setAccessibilityLabel("TrapAwake, \(state)")
        button.setAccessibilityHelp(hint)
        icon.toolTip = button.toolTip
        icon.setAccessibilityLabel("TrapAwake, \(state)")
        icon.setAccessibilityHelp(hint)
        let height = max(button.bounds.height, NSStatusBar.system.thickness)
        let controlHeight: CGFloat = min(20, height)
        let y = (height - controlHeight) / 2
        icon.frame = NSRect(x: 0, y: 0, width: 26, height: height)
        var x: CGFloat = 28
        for field in DurationInput.Field.allCases {
            guard let control = fields[field] else { continue }
            control.isHidden = editor == nil
            let width = ceil((field.placeholder as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width) + 20
            control.frame = NSRect(x: x, y: y, width: width, height: controlHeight)
            if let editor {
                let value = editor.input.text(for: field)
                let attributes: [NSAttributedString.Key: Any] = [.font: control.font!, .foregroundColor: value == nil ? NSColor.secondaryLabelColor : NSColor.labelColor]
                control.attributedTitle = NSAttributedString(string: value ?? field.placeholder, attributes: attributes)
                control.fieldFocused = editor.focused == field
                control.rejected = rejected
                control.setAccessibilityValue(value ?? "Empty")
                control.toolTip = rejected ? "Choose 1 minute to 30 days; extensions must keep the total within 30 days." : "\(field.placeholder): \(field.help). Type digits; Tab changes field; Return confirms; Escape closes."
                control.setAccessibilityHelp(control.toolTip)
            }
            x += width + 4
        }
        countdown.isHidden = editor != nil || !active || !controller.preferences.showCountdown
        if !countdown.isHidden {
            countdown.title = controller.countdownText ?? "∞"
            let width = ceil((countdown.title as NSString).size(withAttributes: [.font: countdown.font!]).width) + 6
            countdown.frame = NSRect(x: 26, y: 0, width: width, height: height)
            countdown.toolTip = "Edit the awake duration"
            countdown.setAccessibilityLabel(controller.countdownText.map { "\($0) remaining. Edit duration" } ?? "Unlimited session. Set a timed duration")
            if editor == nil { x = 26 + width }
        } else if editor == nil { x = 26 }
        stopButton.isHidden = !active
        if active {
            stopButton.frame = NSRect(x: x, y: 0, width: 22, height: height)
            x += 22
        }
        widthWriter?.write(editor != nil ? x : max(26, x))
        let showAttention = controller.error != nil && controller.error != lastError
            || controller.warning != nil && !warningWasVisible
            || controller.protectionReason != nil && controller.protectionReason != lastProtectionReason
        lastError = controller.error
        warningWasVisible = controller.warning != nil
        lastProtectionReason = controller.protectionReason
        if showAttention { showPopover() }
    }
}
