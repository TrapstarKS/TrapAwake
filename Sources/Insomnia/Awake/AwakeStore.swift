import Darwin
import Foundation

struct AwakePaths: Equatable, Sendable {
    static let environmentKey = "TRAPAWAKE_HOME"
    let appSupport: URL
    let logs: URL

    init(appSupport: URL, logs: URL) {
        self.appSupport = appSupport
        self.logs = logs
    }

    init(root: URL) {
        appSupport = root
        logs = root.appendingPathComponent("Logs", isDirectory: true)
    }

    static var standard: AwakePaths {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return AwakePaths(
            appSupport: library.appendingPathComponent("Application Support/TrapAwake", isDirectory: true),
            logs: library.appendingPathComponent("Logs/TrapAwake", isDirectory: true)
        )
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> AwakePaths {
        if let root = environment[environmentKey], !root.isEmpty {
            return AwakePaths(root: URL(fileURLWithPath: root, isDirectory: true))
        }
        return standard
    }

    var preferencesFile: URL { appSupport.appendingPathComponent("preferences.json") }
    var sessionFile: URL { appSupport.appendingPathComponent("session.json") }
    var ownerLock: URL { appSupport.appendingPathComponent(".owner.lock") }
    var logFile: URL { logs.appendingPathComponent("trapawake.log") }

    func prepare() throws {
        for directory in [appSupport, logs] {
            var info = stat()
            if lstat(directory.path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR {
                throw AwakeError.persistence("\(directory.path) is not a directory.")
            }
            if let problem = try OwnerOnly.createDirectory(directory) { throw problem }
        }
        var info = stat()
        if lstat(ownerLock.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.notRegularFile(file: ownerLock.path) }
            if let problem = OwnerOnly.tighten(path: ownerLock.path) { throw problem }
        }
    }
}

struct AwakeSession: Codable, Equatable, Sendable {
    var id = UUID()
    var startedAt: Date
    var endsAt: Date?
    var keepDisplayAwake: Bool
}

@MainActor
protocol AwakePersisting {
    func loadPreferences() throws -> AwakePreferences?
    func savePreferences(_ preferences: AwakePreferences) throws
    func loadSession() throws -> AwakeSession?
    func saveSession(_ session: AwakeSession) throws
    func clearSession() throws
    func archiveSession() throws -> URL?
}

struct AwakeStore: AwakePersisting {
    let paths: AwakePaths

    func loadPreferences() throws -> AwakePreferences? { try read(AwakePreferences.self, at: paths.preferencesFile) }
    func savePreferences(_ preferences: AwakePreferences) throws {
        try preferences.validate()
        try write(preferences, at: paths.preferencesFile)
    }
    func loadSession() throws -> AwakeSession? { try read(AwakeSession.self, at: paths.sessionFile) }
    func saveSession(_ session: AwakeSession) throws { try write(session, at: paths.sessionFile) }

    func clearSession() throws {
        var info = stat()
        guard lstat(paths.sessionFile.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw AwakeError.persistence("Could not inspect the session marker: \(String(cString: strerror(errno))).")
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.notRegularFile(file: paths.sessionFile.path) }
        try FileManager.default.removeItem(at: paths.sessionFile)
    }

    func archiveSession() throws -> URL? {
        var info = stat()
        guard lstat(paths.sessionFile.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw AwakeError.persistence("Could not inspect the interrupted session marker.")
        }
        let archive = paths.appSupport.appendingPathComponent("session.interrupted-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: paths.sessionFile, to: archive)
        return archive
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw AwakeError.persistence("Could not inspect \(url.lastPathComponent): \(String(cString: strerror(errno))).")
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StoreError.notRegularFile(file: url.path) }
        if let problem = OwnerOnly.tighten(path: url.path) { throw problem }
        return try Store.makeDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, at url: URL) throws {
        let data = try Store.makeEncoder().encode(value)
        if let problem = try OwnerOnly.createDirectory(paths.appSupport) { throw problem }
        let temporary = paths.appSupport.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try OwnerOnly.createFile(at: temporary, contents: data)
        guard rename(temporary.path, url.path) == 0 else {
            throw StoreError.rename(from: temporary.path, to: url.path, errno: errno)
        }
    }
}
