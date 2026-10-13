import Foundation
import IOKit.pwr_mgt
import XCTest
@testable import Insomnia

@MainActor
final class AwakeFakeDriver: AssertionDriving {
    var calls: [String] = []
    var active: [IOPMAssertionID: AwakeAssertionKind] = [:]
    var failCreate = Set<AwakeAssertionKind>()
    var failRelease = Set<IOPMAssertionID>()
    private var next: IOPMAssertionID = 1

    func create(_ kind: AwakeAssertionKind) throws -> IOPMAssertionID {
        calls.append("create:\(kind.rawValue)")
        if failCreate.contains(kind) { throw AwakeError.assertion(operation: "create", code: -1) }
        let id = next
        next += 1
        active[id] = kind
        return id
    }

    func release(_ id: IOPMAssertionID) throws {
        calls.append("release:\(id)")
        if failRelease.contains(id) { throw AwakeError.assertion(operation: "release", code: -2) }
        active[id] = nil
    }
}

@MainActor
final class AwakeFakeStore: AwakePersisting {
    var preferences: AwakePreferences?
    var marker: AwakeSession?
    var calls: [String] = []
    var failures = Set<String>()
    var failOnce = Set<String>()

    private func check(_ operation: String) throws {
        calls.append(operation)
        if failures.contains(operation) || failOnce.remove(operation) != nil {
            throw AwakeError.persistence("Simulated \(operation) failure")
        }
    }

    func loadPreferences() throws -> AwakePreferences? { try check("loadPreferences"); return preferences }
    func savePreferences(_ preferences: AwakePreferences) throws { try check("savePreferences"); self.preferences = preferences }
    func loadSession() throws -> AwakeSession? { try check("loadSession"); return marker }
    func saveSession(_ session: AwakeSession) throws { try check("saveSession"); marker = session }
    func clearSession() throws { try check("clearSession"); marker = nil }
    func archiveSession() throws -> URL? {
        try check("archiveSession")
        marker = nil
        return URL(fileURLWithPath: "/temporary/session.interrupted-test.json")
    }
}

@MainActor
final class AwakeTestClock {
    var wall = Date(timeIntervalSince1970: 1_800_000_000)
    var continuous: TimeInterval = 500
    var clock: AwakeClock { AwakeClock(wallNow: { self.wall }, continuousNow: { self.continuous }) }
}

@MainActor
final class AwakeControllerTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trapawake-controller-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeController(_ root: URL, driver: AwakeFakeDriver, store: AwakeFakeStore, clock: AwakeTestClock = AwakeTestClock(), power: (() -> AwakePowerSnapshot)? = nil) -> AwakeController {
        AwakeController(paths: AwakePaths(root: root), driver: driver, clock: clock.clock, powerMonitor: nil, powerReader: power, store: store, automaticTimer: false)
    }

    func testUnlimitedIsTheDefaultAndHasNoDeadline() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore(), clock = AwakeTestClock()
        let controller = makeController(root, driver: driver, store: store, clock: clock)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startDefault())
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.session?.endsAt)
        XCTAssertNil(store.marker?.endsAt)
        XCTAssertNil(controller.remaining())
        XCTAssertNil(controller.countdownText)
        XCTAssertEqual(driver.calls, ["create:system"])
        clock.continuous += 100_000_000
        controller.tick()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.stop())
        XCTAssertNil(store.marker)
        XCTAssertTrue(driver.active.isEmpty)
    }

    func testTimedExpirationUsesContinuousTimeAcrossWallClockChanges() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore(), clock = AwakeTestClock()
        let controller = makeController(root, driver: driver, store: store, clock: clock)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startTimed(duration: 900))
        XCTAssertEqual(controller.countdownText, "15:00")
        clock.wall += 86_400
        clock.continuous += 450
        controller.tick()
        XCTAssertEqual(controller.remaining(now: .distantFuture), 450)
        XCTAssertEqual(controller.countdownText, "07:30")
        clock.wall -= 2 * 86_400
        clock.continuous += 450
        controller.tick()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(store.marker)
        XCTAssertEqual(controller.message, "Timer finished. Normal idle sleep is allowed.")
    }

    func testInvalidDurationNeverCreatesAssertionsOrMarker() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        let controller = makeController(root, driver: driver, store: store)
        let invalid: [TimeInterval] = [0, 59, .nan, .infinity, 30 * 86_400 + 1]
        for duration in invalid {
            XCTAssertFalse(controller.startTimed(duration: duration))
        }
        XCTAssertTrue(driver.calls.isEmpty)
        XCTAssertNil(store.marker)
    }

    func testMarkerSaveFailurePreventsAnyAssertion() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        store.failures.insert("saveSession")
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertFalse(controller.startUnlimited())
        XCTAssertTrue(driver.calls.isEmpty)
        XCTAssertNotNil(controller.error)
    }

    func testDisplayCreateFailureRollsBackSystemAndMarker() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var preferences = AwakePreferences()
        preferences.keepDisplayAwake = true
        store.preferences = preferences
        driver.failCreate.insert(.display)
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertFalse(controller.startUnlimited())
        XCTAssertEqual(driver.calls, ["create:system", "create:display", "release:1"])
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(store.marker)
        XCTAssertFalse(controller.recoveryRequired)
    }

    func testPartialCreateCleanupFailureKeepsAssertionIDForRetry() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var preferences = AwakePreferences()
        preferences.keepDisplayAwake = true
        store.preferences = preferences
        driver.failCreate.insert(.display)
        driver.failRelease.insert(1)
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertFalse(controller.startUnlimited())
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.recoveryRequired)
        XCTAssertNotNil(store.marker)
        XCTAssertFalse(controller.acknowledgeRecovery())
        driver.failRelease.removeAll()
        XCTAssertTrue(controller.stop())
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(store.marker)
        XCTAssertEqual(driver.calls.filter { $0 == "release:1" }.count, 2)
    }

    func testReleaseFailureRetainsOnlyTheFailedAssertion() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var preferences = AwakePreferences()
        preferences.keepDisplayAwake = true
        store.preferences = preferences
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertTrue(controller.startUnlimited())
        driver.failRelease.insert(2)
        XCTAssertFalse(controller.stop())
        XCTAssertFalse(controller.systemIsAwake)
        XCTAssertTrue(controller.displayIsAwake)
        XCTAssertNotNil(store.marker)
        driver.failRelease.removeAll()
        XCTAssertTrue(controller.stop())
        XCTAssertEqual(driver.calls.filter { $0 == "release:1" }.count, 1)
        XCTAssertEqual(driver.calls.filter { $0 == "release:2" }.count, 2)
    }

    func testMarkerClearFailureRequiresArchiveAfterAssertionsAreReleased() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertTrue(controller.startUnlimited())
        store.failures.insert("clearSession")
        XCTAssertFalse(controller.stop())
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(driver.active.isEmpty)
        XCTAssertTrue(controller.recoveryRequired)
        XCTAssertFalse(controller.startUnlimited())
        store.failures.insert("archiveSession")
        XCTAssertFalse(controller.acknowledgeRecovery())
        XCTAssertNotNil(store.marker)
        store.failures.remove("archiveSession")
        XCTAssertTrue(controller.acknowledgeRecovery())
        XCTAssertFalse(controller.recoveryRequired)
        XCTAssertNil(store.marker)
    }

    func testStartupInterruptedSessionIsNeverResumed() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        store.marker = AwakeSession(startedAt: .now, endsAt: .distantFuture, keepDisplayAwake: true)
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertFalse(controller.isActive)
        XCTAssertNotNil(controller.interruptedSession)
        XCTAssertTrue(controller.recoveryRequired)
        XCTAssertFalse(controller.startDefault())
        XCTAssertTrue(driver.calls.isEmpty)
        XCTAssertTrue(controller.acknowledgeRecovery())
        XCTAssertTrue(controller.startDefault())
        XCTAssertTrue(controller.shutdown())
    }

    func testQuitReleasesBothAssertionsAndCannotRestart() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var preferences = AwakePreferences()
        preferences.keepDisplayAwake = true
        store.preferences = preferences
        let controller = makeController(root, driver: driver, store: store)
        XCTAssertTrue(controller.startTimed(duration: 3600))
        XCTAssertTrue(controller.shutdown())
        XCTAssertTrue(driver.active.isEmpty)
        XCTAssertNil(store.marker)
        XCTAssertFalse(controller.startDefault())
    }

    func testOwnerLockIsHeldForObjectLifetimeIncludingAfterShutdown() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var first: AwakeController? = makeController(root, driver: AwakeFakeDriver(), store: AwakeFakeStore())
        let secondDriver = AwakeFakeDriver()
        let second = makeController(root, driver: secondDriver, store: AwakeFakeStore())
        XCTAssertTrue(second.isOtherInstance)
        XCTAssertFalse(second.startDefault())
        XCTAssertTrue(secondDriver.calls.isEmpty)
        XCTAssertTrue(first!.shutdown())
        let third = makeController(root, driver: AwakeFakeDriver(), store: AwakeFakeStore())
        XCTAssertTrue(third.isOtherInstance)
        first = nil
        let fourth = makeController(root, driver: AwakeFakeDriver(), store: AwakeFakeStore())
        XCTAssertFalse(fourth.isOtherInstance)
        XCTAssertNil(fourth.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: AwakePaths(root: root).ownerLock.path))
    }

    func testFailedQuitKeepsProtectionLiveAndAllowsRetry() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var power = AwakePowerSnapshot(battery: .percent(80))
        let controller = makeController(root, driver: driver, store: store, power: { power })
        XCTAssertTrue(controller.startDefault())
        driver.failRelease.insert(1)
        XCTAssertFalse(controller.shutdown())
        XCTAssertTrue(controller.isActive)
        driver.failRelease.removeAll()
        power.battery = .percent(1)
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.protection, .battery)
        XCTAssertEqual(controller.statusText, "Battery protection")
        XCTAssertNotNil(controller.protectionReason)
        power.battery = .percent(80)
        XCTAssertTrue(controller.startDefault(), "A rejected quit must not permanently shut down the controller")
        XCTAssertNil(controller.protectionReason)
        XCTAssertTrue(controller.shutdown())
    }

    func testLiveTimerExpiresUsingInjectedContinuousClock() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore(), clock = AwakeTestClock()
        let controller = AwakeController(paths: AwakePaths(root: root), driver: driver, clock: clock.clock, powerMonitor: nil, store: store)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startTimed(duration: 60))
        clock.continuous += 60
        let deadline = Date().addingTimeInterval(5)
        while controller.isActive, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(store.marker)
        XCTAssertTrue(driver.active.isEmpty)
    }

    func testCriticalBatteryStopsAndBlocksStartButChargerAllowsIt() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var power = AwakePowerSnapshot(battery: .percent(50))
        let controller = makeController(root, driver: driver, store: store, power: { power })
        XCTAssertTrue(controller.startDefault())
        power.battery = .percent(20)
        controller.refreshPower()
        XCTAssertTrue(controller.isActive)
        XCTAssertNotNil(controller.warning)
        power.battery = .percent(10)
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.startDefault())
        power.isCharging = true
        XCTAssertTrue(controller.startDefault())
        XCTAssertNil(controller.warning)
        XCTAssertTrue(controller.shutdown())
    }

    func testPersistentUnreadableBatteryStopsOnlyWhenOnBattery() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var power = AwakePowerSnapshot(battery: .unreadable(misses: 1))
        let controller = makeController(root, driver: driver, store: store, power: { power })
        XCTAssertTrue(controller.startDefault())
        power.battery = .unreadable(misses: 2)
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.startDefault())
        power.isCharging = true
        XCTAssertTrue(controller.startDefault())
        XCTAssertTrue(controller.shutdown())
    }

    func testMissingBatteryNotificationsBlockLaptopsEvenOnChargerAndStopActiveSessions() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var power = AwakePowerSnapshot(battery: .percent(80), isCharging: true, batteryNotificationsAvailable: false)
        let controller = makeController(root, driver: driver, store: store, power: { power })
        XCTAssertFalse(controller.startDefault())
        XCTAssertTrue(driver.calls.isEmpty)
        XCTAssertEqual(controller.protection, .battery)
        XCTAssertTrue(controller.error!.contains("Battery monitoring is unavailable"))
        power.battery = .none
        XCTAssertTrue(controller.startDefault(), "A desktop has no battery to monitor")
        power.battery = .percent(80)
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(driver.active.isEmpty)
        XCTAssertTrue(controller.message!.contains("Battery monitoring is unavailable"))
    }

    func testCriticalHeatCannotBeDisabledAndSeriousHeatDefaultsToStop() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        var power = AwakePowerSnapshot()
        let controller = makeController(root, driver: driver, store: store, power: { power })
        XCTAssertTrue(controller.startDefault())
        power.thermalState = .serious
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        var preferences = controller.preferences
        preferences.stopOnSeriousHeat = false
        XCTAssertTrue(controller.updatePreferences(preferences))
        XCTAssertTrue(controller.startDefault())
        power.thermalState = .critical
        controller.refreshPower()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.startDefault())
    }

    func testDisplayPolicyChangesLiveAndFailedPersistenceRollsBack() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        let controller = makeController(root, driver: driver, store: store)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startDefault())
        var next = controller.preferences
        next.keepDisplayAwake = true
        store.failOnce.insert("savePreferences")
        XCTAssertFalse(controller.updatePreferences(next))
        XCTAssertFalse(controller.preferences.keepDisplayAwake)
        XCTAssertFalse(controller.displayIsAwake)
        XCTAssertEqual(driver.active.count, 1)
        XCTAssertTrue(controller.updatePreferences(next))
        XCTAssertTrue(controller.displayIsAwake)
        XCTAssertTrue(store.marker!.keepDisplayAwake)
        next.keepDisplayAwake = false
        store.failOnce.insert("saveSession")
        XCTAssertFalse(controller.updatePreferences(next))
        XCTAssertTrue(controller.preferences.keepDisplayAwake)
        XCTAssertTrue(controller.displayIsAwake)
        XCTAssertEqual(driver.active.count, 2)
        XCTAssertTrue(controller.updatePreferences(next))
        XCTAssertFalse(controller.displayIsAwake)
    }

    func testInvalidPreferencesDoNotWriteOrChangeDisplayAssertions() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore()
        let controller = makeController(root, driver: driver, store: store)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startDefault())
        let calls = store.calls
        var preferences = controller.preferences
        preferences.keepDisplayAwake = true
        preferences.criticalBatteryPercent = 0
        XCTAssertFalse(controller.updatePreferences(preferences))
        XCTAssertEqual(store.calls, calls)
        XCTAssertFalse(controller.displayIsAwake)
        XCTAssertEqual(driver.active.count, 1)
    }

    func testExtensionPersistsBeforeChangingContinuousDeadline() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = AwakeFakeDriver(), store = AwakeFakeStore(), clock = AwakeTestClock()
        let controller = makeController(root, driver: driver, store: store, clock: clock)
        defer { controller.shutdown() }
        XCTAssertTrue(controller.startTimed(duration: 900))
        clock.continuous += 60
        XCTAssertTrue(controller.extend(by: 900))
        XCTAssertEqual(controller.remaining(), 1740)
        store.failures.insert("saveSession")
        XCTAssertFalse(controller.extend(by: 900))
        XCTAssertEqual(controller.remaining(), 1740)
        XCTAssertEqual(driver.calls, ["create:system"])
    }
}
