import AppKit

struct AwakeDurationEditor {
    enum Action: Equatable {
        case start(TimeInterval)
        case extend(TimeInterval)
        case convert(TimeInterval)
        case reject
    }

    var input = DurationInput()
    var focused: DurationInput.Field = .hours

    func action(active: Bool, remaining: TimeInterval?, defaultDuration: TimeInterval?) -> Action {
        let duration: TimeInterval
        if input.isEmpty {
            guard !active else { return .reject }
            duration = defaultDuration ?? 3_600
        } else {
            guard let total = input.total else { return .reject }
            duration = total
        }
        guard duration.isFinite,
              (AwakePreferences.minimumDuration...AwakePreferences.maximumDuration).contains(duration) else { return .reject }
        guard active else { return .start(duration) }
        guard let remaining else { return .convert(duration) }
        guard remaining > 0, remaining + duration <= AwakePreferences.maximumDuration else { return .reject }
        return .extend(duration)
    }

    @MainActor func action(controller: AwakeController) -> Action {
        action(active: controller.isActive, remaining: controller.remaining(), defaultDuration: controller.preferences.defaultDuration)
    }

    @MainActor func commit(controller: AwakeController) -> Bool {
        guard !controller.recoveryRequired, !controller.isOtherInstance else { return false }
        switch action(controller: controller) {
        case let .start(duration): return controller.startTimed(duration: duration)
        case let .extend(duration): return controller.extend(by: duration)
        case let .convert(duration):
            guard controller.stop() else { return false }
            return controller.startTimed(duration: duration)
        case .reject: return false
        }
    }

    mutating func append(_ digit: Int) -> Bool {
        let accepted = input.append(digit: digit, to: focused)
        if accepted, !input.canAcceptDigit(in: focused), focused != .minutes { focused = focused.next }
        return accepted
    }

    mutating func backspace() {
        if !input.backspace(focused) {
            focused = focused.previous
            _ = input.backspace(focused)
        }
    }
}

@MainActor
final class AwakeFieldButton: NSButton {
    var onContextMenu: (() -> Void)?
    var fieldFocused = false { didSet { needsDisplay = true } }
    var rejected = false { didSet { needsDisplay = true } }

    override func rightMouseDown(with event: NSEvent) { onContextMenu?() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
            onContextMenu?()
            return
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard fieldFocused || rejected else { return }
        (rejected ? NSColor.systemRed : NSColor.keyboardFocusIndicatorColor).setStroke()
        let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        ring.lineWidth = 1.5
        ring.stroke()
    }
}
