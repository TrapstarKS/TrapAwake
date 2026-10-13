import AppKit
import XCTest
@testable import Insomnia

@MainActor
final class AwakeMenuBarTests: XCTestCase {
    private func fixture() throws -> (AwakeController, AwakeFakeDriver, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trapawake-editor-tests-\(UUID().uuidString)")
        let driver = AwakeFakeDriver()
        let controller = AwakeController(paths: AwakePaths(root: root), driver: driver, clock: AwakeTestClock().clock, powerMonitor: nil, store: AwakeFakeStore(), automaticTimer: false)
        return (controller, driver, root)
    }

    func testEmptyEnterStartsTimedDefaultOrOneHourButNeverExtends() {
        let editor = AwakeDurationEditor()
        XCTAssertEqual(editor.action(active: false, remaining: nil, defaultDuration: nil), .start(3_600))
        XCTAssertEqual(editor.action(active: false, remaining: nil, defaultDuration: 900), .start(900))
        XCTAssertEqual(editor.action(active: true, remaining: 900, defaultDuration: 900), .reject)
        XCTAssertEqual(editor.action(active: true, remaining: nil, defaultDuration: nil), .reject)
    }

    func testCombinedDurationAndExtensionStayWithinThirtyDays() {
        var editor = AwakeDurationEditor()
        editor.input = DurationInput(days: 30)
        XCTAssertEqual(editor.action(active: false, remaining: nil, defaultDuration: nil), .start(AwakePreferences.maximumDuration))
        editor.input.hours = 1
        XCTAssertEqual(editor.action(active: false, remaining: nil, defaultDuration: nil), .reject)
        editor.input = DurationInput(minutes: 1)
        XCTAssertEqual(editor.action(active: true, remaining: AwakePreferences.maximumDuration - 60, defaultDuration: nil), .extend(60))
        XCTAssertEqual(editor.action(active: true, remaining: AwakePreferences.maximumDuration - 59, defaultDuration: nil), .reject)
        editor.input = DurationInput(hours: 0)
        XCTAssertEqual(editor.action(active: false, remaining: nil, defaultDuration: 900), .reject)
    }

    func testDigitsAdvanceFocusAndBackspaceMovesToPreviousField() {
        var editor = AwakeDurationEditor()
        XCTAssertEqual(editor.focused, .hours)
        XCTAssertTrue(editor.append(2))
        XCTAssertTrue(editor.append(3))
        XCTAssertEqual(editor.input.hours, 23)
        XCTAssertEqual(editor.focused, .minutes)
        editor.backspace()
        XCTAssertEqual(editor.focused, .hours)
        XCTAssertEqual(editor.input.hours, 2)
        editor.focused = .days
        XCTAssertTrue(editor.append(3))
        XCTAssertFalse(editor.append(1))
        XCTAssertEqual(editor.input.days, 3)
    }

    func testTimedCommitExtendsWithoutReplacingAssertion() throws {
        let (controller, driver, root) = try fixture()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(controller.startTimed(duration: 900))
        var editor = AwakeDurationEditor()
        editor.input = DurationInput(minutes: 15)
        XCTAssertTrue(editor.commit(controller: controller))
        XCTAssertEqual(controller.remaining(), 1_800)
        XCTAssertEqual(driver.calls, ["create:system"])
        XCTAssertFalse(AwakeStatusItem.unlimitedIsSelected(controller))
    }

    func testUnlimitedConversionRequiresSuccessfulStop() throws {
        let (controller, driver, root) = try fixture()
        defer { driver.failRelease = []; controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(AwakeStatusItem.unlimitedIsSelected(controller))
        XCTAssertTrue(controller.startUnlimited())
        XCTAssertTrue(AwakeStatusItem.unlimitedIsSelected(controller))
        var editor = AwakeDurationEditor()
        editor.input = DurationInput(minutes: 15)
        driver.failRelease = Set(driver.active.keys)
        XCTAssertFalse(editor.commit(controller: controller))
        XCTAssertTrue(AwakeStatusItem.unlimitedIsSelected(controller))
        XCTAssertEqual(driver.calls.filter { $0 == "create:system" }.count, 1)
    }

    func testUnlimitedConversionCreatesFiniteSessionAfterRelease() throws {
        let (controller, driver, root) = try fixture()
        defer { controller.shutdown(); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(controller.startUnlimited())
        var editor = AwakeDurationEditor()
        editor.input = DurationInput(hours: 1)
        XCTAssertTrue(editor.commit(controller: controller))
        XCTAssertEqual(controller.remaining(), 3_600)
        XCTAssertFalse(AwakeStatusItem.unlimitedIsSelected(controller))
        XCTAssertEqual(driver.calls, ["create:system", "release:1", "create:system"])
    }

    func testChildButtonsRouteRightControlAndOptionClickDirectly() throws {
        let button = AwakeFieldButton()
        var contexts = 0
        button.onContextMenu = { contexts += 1 }
        let right = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        button.rightMouseDown(with: right)
        for modifiers: NSEvent.ModifierFlags in [.control, .option] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
            button.mouseDown(with: event)
        }
        XCTAssertEqual(contexts, 3)
    }
}
