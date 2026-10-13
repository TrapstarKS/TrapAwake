import Foundation

struct AwakePreferences: Codable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 60
    static let maximumDuration: TimeInterval = 30 * 24 * 60 * 60
    static let standardPresets: [TimeInterval] = [900, 1800, 3600, 7200, 14400, 28800]

    var defaultDuration: TimeInterval? = nil
    var presets: [TimeInterval] = standardPresets
    var keepDisplayAwake = false
    var warningBatteryPercent = 20
    var criticalBatteryPercent = 10
    var stopOnSeriousHeat = true
    var showCountdown = true
    var launchAtLogin = false
    var launchAtLoginInstall: String? = nil

    init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultDuration, presets, keepDisplayAwake, warningBatteryPercent
        case criticalBatteryPercent, stopOnSeriousHeat, showCountdown, launchAtLogin, launchAtLoginInstall
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultDuration = try values.decodeIfPresent(TimeInterval.self, forKey: .defaultDuration)
        presets = try values.decodeIfPresent([TimeInterval].self, forKey: .presets) ?? Self.standardPresets
        keepDisplayAwake = try values.decodeIfPresent(Bool.self, forKey: .keepDisplayAwake) ?? false
        warningBatteryPercent = try values.decodeIfPresent(Int.self, forKey: .warningBatteryPercent) ?? 20
        criticalBatteryPercent = try values.decodeIfPresent(Int.self, forKey: .criticalBatteryPercent) ?? 10
        stopOnSeriousHeat = try values.decodeIfPresent(Bool.self, forKey: .stopOnSeriousHeat) ?? true
        showCountdown = try values.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        launchAtLoginInstall = try values.decodeIfPresent(String.self, forKey: .launchAtLoginInstall)
        try validate()
    }

    func validate() throws {
        if let defaultDuration { try Self.validateDuration(defaultDuration) }
        guard !presets.isEmpty else { throw AwakeError.invalidPreferences("Choose at least one duration preset.") }
        for duration in presets { try Self.validateDuration(duration) }
        guard (1...100).contains(criticalBatteryPercent) else {
            throw AwakeError.invalidPreferences("The critical battery limit must be between 1% and 100%.")
        }
        guard (criticalBatteryPercent...100).contains(warningBatteryPercent) else {
            throw AwakeError.invalidPreferences("The battery warning must be at or above the critical limit.")
        }
    }

    static func validateDuration(_ duration: TimeInterval) throws {
        guard duration.isFinite, (minimumDuration...maximumDuration).contains(duration) else {
            throw AwakeError.invalidPreferences("Choose a duration between 1 minute and 30 days.")
        }
    }
}

enum AwakeError: Error, LocalizedError {
    case invalidPreferences(String)
    case anotherInstance
    case unsafePower(String)
    case persistence(String)
    case assertion(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case let .invalidPreferences(message), let .unsafePower(message), let .persistence(message): message
        case .anotherInstance: "Another TrapAwake process is running. Quit it before opening this instance."
        case let .assertion(operation, code): "Could not \(operation) the power assertion (IOKit \(code))."
        }
    }
}
