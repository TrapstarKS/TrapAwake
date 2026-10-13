import Darwin
import Foundation
import XCTest
@testable import Insomnia

@MainActor
final class AwakeStoreTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trapawake-store-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testPathsUseTrapAwakeAndIgnoreLegacyEnvironment() {
        let standard = AwakePaths.fromEnvironment(["INSOMNIA_HOME": "/wrong"])
        XCTAssertTrue(standard.appSupport.path.hasSuffix("Library/Application Support/TrapAwake"))
        XCTAssertTrue(standard.logs.path.hasSuffix("Library/Logs/TrapAwake"))
        let temporary = root()
        let paths = AwakePaths.fromEnvironment(["TRAPAWAKE_HOME": temporary.path])
        XCTAssertEqual(paths.appSupport, temporary)
        XCTAssertEqual(paths.logs, temporary.appendingPathComponent("Logs", isDirectory: true))
    }

    func testPreferencesDecodeMissingKeysAndRejectUnsafeLimits() throws {
        let defaults = try JSONDecoder().decode(AwakePreferences.self, from: Data("{}".utf8))
        XCTAssertNil(defaults.defaultDuration)
        XCTAssertEqual(defaults.criticalBatteryPercent, 10)
        XCTAssertEqual(defaults.presets, [900, 1800, 3600, 7200, 14400, 28800])
        XCTAssertTrue(defaults.stopOnSeriousHeat)
        for json in ["{\"criticalBatteryPercent\":0}", "{\"criticalBatteryPercent\":30,\"warningBatteryPercent\":20}", "{\"defaultDuration\":59}", "{\"presets\":[2592001]}", "{\"presets\":[]}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(AwakePreferences.self, from: Data(json.utf8)))
        }
        var preferences = defaults
        preferences.defaultDuration = .nan
        XCTAssertThrowsError(try preferences.validate())
    }

    func testAtomicOwnerOnlyPreferencesAndUnlimitedMarkerRoundTrip() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AwakePaths(root: root)
        try paths.prepare()
        let store = AwakeStore(paths: paths)
        var preferences = AwakePreferences()
        preferences.defaultDuration = 3600
        preferences.keepDisplayAwake = true
        preferences.presets = [60, 30 * 86_400]
        try store.savePreferences(preferences)
        XCTAssertEqual(try store.loadPreferences(), preferences)
        let marker = AwakeSession(startedAt: Date(timeIntervalSince1970: 1_800_000_000), endsAt: nil, keepDisplayAwake: true)
        try store.saveSession(marker)
        XCTAssertEqual(try store.loadSession(), marker)
        for url in [paths.preferencesFile, paths.sessionFile] {
            var info = stat()
            XCTAssertEqual(lstat(url.path, &info), 0)
            XCTAssertEqual(info.st_mode & 0o777, 0o600)
        }
        var directory = stat()
        XCTAssertEqual(lstat(root.path, &directory), 0)
        XCTAssertEqual(directory.st_mode & 0o777, 0o700)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.contains(".tmp-") })
    }

    func testUnreadableMarkerIsRetainedAndBlocksStartUntilArchived() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AwakePaths(root: root)
        try paths.prepare()
        let bad = Data("broken marker".utf8)
        try bad.write(to: paths.sessionFile)
        let driver = AwakeFakeDriver()
        let controller = AwakeController(paths: paths, driver: driver, powerMonitor: nil, automaticTimer: false)
        XCTAssertTrue(controller.recoveryRequired)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.startDefault())
        XCTAssertTrue(driver.calls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: paths.sessionFile), bad)
        XCTAssertTrue(controller.acknowledgeRecovery())
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.sessionFile.path))
        let archived = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("session.interrupted-") }
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(try Data(contentsOf: archived[0]), bad)
        XCTAssertTrue(controller.startDefault())
        XCTAssertTrue(controller.shutdown())
    }

    func testSymlinkMarkerIsNeverReadAndArchiveMovesOnlyTheLink() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AwakePaths(root: root)
        try paths.prepare()
        let target = root.appendingPathComponent("target.json")
        let contents = Data("do not alter".utf8)
        try contents.write(to: target)
        try FileManager.default.createSymbolicLink(at: paths.sessionFile, withDestinationURL: target)
        let store = AwakeStore(paths: paths)
        XCTAssertThrowsError(try store.loadSession())
        let archive = try XCTUnwrap(store.archiveSession())
        XCTAssertEqual(try Data(contentsOf: target), contents)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: archive.path), target.path)
        XCTAssertNil(try store.loadSession())
    }

    func testOwnerLockRejectsSymlinkWithoutOpeningItsTarget() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AwakePaths(root: root)
        try paths.prepare()
        let target = root.appendingPathComponent("target")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: paths.ownerLock, withDestinationURL: target)
        let controller = AwakeController(paths: paths, driver: AwakeFakeDriver(), powerMonitor: nil, automaticTimer: false)
        XCTAssertTrue(controller.recoveryRequired)
        XCTAssertFalse(controller.startDefault())
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "untouched")
    }
}
