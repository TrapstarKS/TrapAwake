import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
struct AwakeClock {
    var wallNow: () -> Date
    var continuousNow: () -> TimeInterval

    static var live: AwakeClock {
        let origin = ContinuousClock.now
        return AwakeClock(wallNow: { Date() }, continuousNow: {
            let duration = origin.duration(to: ContinuousClock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        })
    }
}

struct AwakePowerSnapshot: Equatable, Sendable {
    var battery: BatteryStatus = .none
    var isCharging = false
    var thermalState: ProcessInfo.ThermalState = .nominal
    var batteryNotificationsAvailable = true
}

enum AwakeProtection: Equatable, Sendable {
    case battery
    case thermal
}

@MainActor
@Observable
final class AwakeController {
    private(set) var preferences = AwakePreferences()
    private(set) var session: AwakeSession?
    private(set) var interruptedSession: AwakeSession?
    private(set) var recoveryRequired = false
    private(set) var isOtherInstance = false
    private(set) var message: String?
    private(set) var error: String?
    private(set) var warning: String?
    private(set) var power = AwakePowerSnapshot()
    private(set) var remainingSeconds: TimeInterval?
    private(set) var systemIsAwake = false
    private(set) var displayIsAwake = false
    private(set) var protection: AwakeProtection?
    private(set) var protectionReason: String?

    @ObservationIgnored private let store: any AwakePersisting
    @ObservationIgnored private let driver: any AssertionDriving
    @ObservationIgnored private let clock: AwakeClock
    @ObservationIgnored private let monitor: PowerMonitor?
    @ObservationIgnored private let powerReader: (() -> AwakePowerSnapshot)?
    @ObservationIgnored private let automaticTimer: Bool
    @ObservationIgnored private var owner: RecoveryLockHandle?
    @ObservationIgnored private var systemAssertion: IOPMAssertionID?
    @ObservationIgnored private var displayAssertion: IOPMAssertionID?
    @ObservationIgnored private var deadline: TimeInterval?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var shuttingDown = false

    init(
        paths: AwakePaths = .fromEnvironment(),
        driver: any AssertionDriving = AssertionDriver(),
        clock: AwakeClock = .live,
        powerMonitor: PowerMonitor? = PowerMonitor(),
        powerReader: (() -> AwakePowerSnapshot)? = nil,
        store: (any AwakePersisting)? = nil,
        automaticTimer: Bool = true
    ) {
        self.store = store ?? AwakeStore(paths: paths)
        self.driver = driver
        self.clock = clock
        self.monitor = powerMonitor
        self.powerReader = powerReader
        self.automaticTimer = automaticTimer
        do {
            try paths.prepare()
            owner = try RecoveryLock(url: paths.ownerLock).tryAcquire()
            guard owner != nil else {
                isOtherInstance = true
                error = AwakeError.anotherInstance.localizedDescription
                return
            }
        } catch {
            self.error = "Could not open TrapAwake's storage: \(error.localizedDescription)"
            recoveryRequired = true
            return
        }
        do {
            preferences = try self.store.loadPreferences() ?? AwakePreferences()
            try preferences.validate()
        } catch {
            self.error = "Preferences could not be read; safe defaults are in use. \(error.localizedDescription)"
        }
        do {
            if let interrupted = try self.store.loadSession() {
                interruptedSession = interrupted
                recoveryRequired = true
                message = "A previous session was interrupted. Its process-owned assertions are gone; it will not resume. Acknowledge to archive its marker."
            }
        } catch {
            recoveryRequired = true
            self.error = "The interrupted session marker could not be read and was kept. Acknowledge to archive it safely. \(error.localizedDescription)"
        }
        monitor?.onChange = { [weak self] in self?.refreshPower() }
        monitor?.start()
        refreshPower()
    }

    var isActive: Bool { systemIsAwake || displayIsAwake }

    var statusText: String {
        if isOtherInstance { return "Another instance is running" }
        if recoveryRequired, !isActive { return "Recovery needs acknowledgement" }
        if let protection { return protection == .battery ? "Battery protection" : "Thermal protection" }
        guard isActive else { return "Paused" }
        if let countdownText { return "Awake · \(countdownText)" }
        return "Awake · Unlimited"
    }

    var countdownText: String? {
        guard let remainingSeconds, let session, let endsAt = session.endsAt else { return nil }
        return SessionMath.formatCountdown(
            remaining: remainingSeconds,
            shape: CountdownShape(initialDuration: endsAt.timeIntervalSince(session.startedAt))
        )
    }

    func remaining(now: Date = Date()) -> TimeInterval? {
        // Wall time is only diagnostic: changing the clock cannot extend a live session.
        _ = now
        _ = remainingSeconds
        guard let deadline, isActive else { return nil }
        return max(0, deadline - clock.continuousNow())
    }

    @discardableResult
    func startUnlimited() -> Bool { start(duration: nil) }

    @discardableResult
    func startTimed(duration: TimeInterval) -> Bool { start(duration: duration) }

    @discardableResult
    func startDefault() -> Bool { start(duration: preferences.defaultDuration) }

    @discardableResult
    func extend(by duration: TimeInterval) -> Bool {
        guard var session, let current = remaining(), current > 0 else { return false }
        let total = current + duration
        do {
            try AwakePreferences.validateDuration(duration)
            try AwakePreferences.validateDuration(total)
            session.endsAt = clock.wallNow().addingTimeInterval(total)
            try store.saveSession(session)
            self.session = session
            deadline = clock.continuousNow() + total
            remainingSeconds = total
            error = nil
            message = "Session extended."
            return true
        } catch {
            self.error = "Could not extend the session: \(error.localizedDescription)"
            return false
        }
    }

    private func start(duration: TimeInterval?) -> Bool {
        guard !shuttingDown, owner != nil, !isOtherInstance, !recoveryRequired else { return false }
        guard !isActive else {
            error = "End the current session before starting another."
            return false
        }
        monitor?.refreshBattery()
        refreshPower()
        do {
            if let duration { try AwakePreferences.validateDuration(duration) }
            if let unsafe = unsafePowerReason() {
                protection = unsafe.protection
                protectionReason = unsafe.reason
                throw AwakeError.unsafePower(unsafe.reason)
            }
            let startedAt = clock.wallNow()
            let next = AwakeSession(startedAt: startedAt, endsAt: duration.map { startedAt.addingTimeInterval($0) }, keepDisplayAwake: preferences.keepDisplayAwake)
            try store.saveSession(next)
            session = next
            systemAssertion = try driver.create(.system)
            systemIsAwake = true
            if preferences.keepDisplayAwake {
                displayAssertion = try driver.create(.display)
                displayIsAwake = true
            }
            deadline = duration.map { clock.continuousNow() + $0 }
            remainingSeconds = duration
            error = nil
            protection = nil
            protectionReason = nil
            message = duration == nil ? "Unlimited session started." : "Timed session started."
            updateWarning()
            startTimer()
            return true
        } catch {
            let failure = "Could not start: \(error.localizedDescription)"
            if session != nil {
                let released = releaseAssertions()
                if released.isEmpty {
                    session = nil
                    do { try store.clearSession() }
                    catch {
                        recoveryRequired = true
                        self.error = failure + " The session marker could not be cleared: \(error.localizedDescription)"
                        return false
                    }
                } else {
                    recoveryRequired = true
                    self.error = failure + " Cleanup failed: " + released.joined(separator: " ")
                    return false
                }
            }
            self.error = failure
            return false
        }
    }

    @discardableResult
    func stop(reason: String = "Session ended. Normal idle sleep is allowed.") -> Bool {
        guard isActive || session != nil else { return true }
        let failures = releaseAssertions()
        guard failures.isEmpty else {
            recoveryRequired = true
            error = "Could not release every power assertion. Retry End Session. " + failures.joined(separator: " ")
            return false
        }
        timer?.cancel()
        timer = nil
        deadline = nil
        remainingSeconds = nil
        session = nil
        warning = nil
        do {
            try store.clearSession()
            recoveryRequired = false
            error = nil
            message = reason
            return true
        } catch {
            recoveryRequired = true
            self.error = "Assertions were released, but the session marker could not be cleared. Acknowledge to archive it. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updatePreferences(_ next: AwakePreferences) -> Bool {
        guard owner != nil, !isOtherInstance, !shuttingDown else { return false }
        do { try next.validate() }
        catch {
            self.error = "Could not update preferences: \(error.localizedDescription)"
            return false
        }
        let previous = preferences
        var createdDisplay: IOPMAssertionID?
        var removedDisplay = false
        var savedPreferences = false
        do {
            if isActive, next.keepDisplayAwake != previous.keepDisplayAwake {
                if next.keepDisplayAwake {
                    let id = try driver.create(.display)
                    createdDisplay = id
                    displayAssertion = id
                    displayIsAwake = true
                } else if let id = displayAssertion {
                    try driver.release(id)
                    displayAssertion = nil
                    displayIsAwake = false
                    removedDisplay = true
                }
            }
            try store.savePreferences(next)
            savedPreferences = true
            if var active = session {
                active.keepDisplayAwake = next.keepDisplayAwake
                try store.saveSession(active)
                session = active
            }
            preferences = next
            if !recoveryRequired { error = nil }
            refreshPower()
            return true
        } catch {
            var failures = ["Could not update preferences: \(error.localizedDescription)"]
            if let createdDisplay {
                do {
                    try driver.release(createdDisplay)
                    displayAssertion = nil
                    displayIsAwake = false
                } catch {
                    recoveryRequired = true
                    failures.append("Display cleanup failed: \(error.localizedDescription)")
                }
            } else if removedDisplay {
                do {
                    displayAssertion = try driver.create(.display)
                    displayIsAwake = true
                } catch {
                    recoveryRequired = true
                    failures.append("Could not restore the display policy: \(error.localizedDescription)")
                }
            }
            if savedPreferences {
                do { try store.savePreferences(previous) }
                catch {
                    recoveryRequired = true
                    failures.append("Could not restore the saved preferences: \(error.localizedDescription)")
                }
            }
            self.error = failures.joined(separator: " ")
            return false
        }
    }

    @discardableResult
    func acknowledgeRecovery() -> Bool {
        guard owner != nil, !isOtherInstance, !isActive else { return false }
        do {
            let archive = try store.archiveSession()
            recoveryRequired = false
            interruptedSession = nil
            error = nil
            message = archive.map { "Interrupted session archived as \($0.lastPathComponent)." } ?? "Recovery acknowledged."
            return true
        } catch {
            recoveryRequired = true
            self.error = "Could not archive the session marker; it was kept. \(error.localizedDescription)"
            return false
        }
    }

    func clearError() {
        if !recoveryRequired, !isOtherInstance { error = nil }
    }

    @discardableResult
    func shutdown() -> Bool {
        let ended = stop()
        guard ended else { return false }
        shuttingDown = true
        timer?.cancel()
        timer = nil
        monitor?.stop()
        return ended
    }

    func tick() {
        guard isActive else { return }
        remainingSeconds = remaining()
        if let remainingSeconds, remainingSeconds <= 0 {
            stop(reason: "Timer finished. Normal idle sleep is allowed.")
        }
    }

    func refreshPower() {
        if let powerReader {
            power = powerReader()
        } else if let monitor {
            power = AwakePowerSnapshot(battery: monitor.battery, isCharging: monitor.isCharging, thermalState: monitor.thermalState, batteryNotificationsAvailable: monitor.batteryNotificationsAvailable)
        }
        if let unsafe = unsafePowerReason() {
            protection = unsafe.protection
            protectionReason = unsafe.reason
            if isActive { stop(reason: unsafe.reason) }
        } else {
            protection = nil
            protectionReason = nil
        }
        updateWarning()
    }

    private func unsafePowerReason() -> (protection: AwakeProtection, reason: String)? {
        if power.thermalState == .critical { return (.thermal, "Session stopped for critical heat. Let the Mac cool down.") }
        if preferences.stopOnSeriousHeat, power.thermalState == .serious { return (.thermal, "Session stopped for serious heat. Let the Mac cool down.") }
        if power.battery != .none, !power.batteryNotificationsAvailable {
            return (.battery, "Battery monitoring is unavailable. Restart TrapAwake before starting another session.")
        }
        guard !power.isCharging else { return nil }
        if let percent = power.battery.percent, percent <= preferences.criticalBatteryPercent {
            return (.battery, "Session stopped at the critical battery limit (\(percent)%). Connect a charger.")
        }
        if case let .unreadable(misses) = power.battery, misses >= 2 {
            return (.battery, "Session stopped because the battery level remains unreadable. Connect a charger before trying again.")
        }
        return nil
    }

    private func updateWarning() {
        if isActive, !power.isCharging, let percent = power.battery.percent, percent <= preferences.warningBatteryPercent {
            warning = "Low battery: \(percent)%. The session ends at \(preferences.criticalBatteryPercent)%."
        } else {
            warning = nil
        }
    }

    private func releaseAssertions() -> [String] {
        var failures: [String] = []
        if let id = displayAssertion {
            do {
                try driver.release(id)
                displayAssertion = nil
                displayIsAwake = false
            } catch { failures.append("Display: \(error.localizedDescription)") }
        }
        if let id = systemAssertion {
            do {
                try driver.release(id)
                systemAssertion = nil
                systemIsAwake = false
            } catch { failures.append("System: \(error.localizedDescription)") }
        }
        return failures
    }

    private func startTimer() {
        guard automaticTimer, deadline != nil else { return }
        timer?.cancel()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                self.tick()
                if !self.isActive { return }
            }
        }
    }
}
