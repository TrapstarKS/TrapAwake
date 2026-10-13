import Foundation
import ServiceManagement

// Uninstallation must unregister the login item without starting a session.
if CommandLine.arguments.contains("--unregister-login-item") {
    do {
        if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        exit(0)
    } catch {
        print("Could not remove login item: \(error.localizedDescription)")
        exit(1)
    }
}
TrapAwakeApp.main()
