import Foundation
import IOKit.pwr_mgt

enum AwakeAssertionKind: String, Hashable, Sendable {
    case system
    case display
}

@MainActor
protocol AssertionDriving: AnyObject {
    func create(_ kind: AwakeAssertionKind) throws -> IOPMAssertionID
    func release(_ id: IOPMAssertionID) throws
}

@MainActor
final class AssertionDriver: AssertionDriving {
    private var owned = Set<IOPMAssertionID>()

    func create(_ kind: AwakeAssertionKind) throws -> IOPMAssertionID {
        let type = kind == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "TrapAwake: \(kind.rawValue) awake" as CFString, &id)
        guard result == kIOReturnSuccess else { throw AwakeError.assertion(operation: "create", code: result) }
        owned.insert(id)
        return id
    }

    func release(_ id: IOPMAssertionID) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw AwakeError.assertion(operation: "release", code: result) }
        owned.remove(id)
    }

    deinit {
        for id in owned { IOPMAssertionRelease(id) }
    }
}
