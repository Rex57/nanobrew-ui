import Foundation

public struct Formula: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let version: String
    public let pinned: Bool
    public let installedAt: Int
    public var id: String { name }
}

public struct Cask: Decodable, Equatable, Identifiable, Sendable {
    public let token: String
    public let version: String
    public let apps: [String]
    public let binaries: [String]
    public var id: String { token }
}

public struct HistoryEntry: Decodable, Equatable, Sendable {
    public let version: String
    public let installedAt: Int
}

/// What nanobrew has installed, from state.json. Unknown fields are ignored.
public struct StateSnapshot: Decodable, Equatable, Sendable {
    public let formulae: [Formula]
    public let casks: [Cask]
    public let history: [String: [HistoryEntry]]

    enum CodingKeys: String, CodingKey { case formulae = "kegs", casks, history }

    /// The history entries of a formula without the installed version, newest first (nb appends to the history).
    public func earlierVersions(of name: String) -> [HistoryEntry] {
        let current = formulae.first { $0.name == name }?.version
        return (history[name] ?? []).filter { $0.version != current }.reversed()
    }
}

public enum StateReader {
    public static let defaultPath = "/opt/nanobrew/db/state.json"

    /// nil when the file's folder does not exist (nanobrew is not set up, D9). A missing file in an existing
    /// folder is an empty snapshot: nb init makes the folder, and nb writes the file only later. Never writes.
    public static func read(path: String) throws -> StateSnapshot? {
        guard FileManager.default.fileExists(atPath: path) else {
            let folder = (path as NSString).deletingLastPathComponent
            return FileManager.default.fileExists(atPath: folder) ? StateSnapshot(formulae: [], casks: [], history: [:]) : nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StateSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
}

public enum NBLocator {
    /// The user-defaults key of the nb path field in Settings.
    public static let savedPathKey = "SavedNBPath"
    public static let defaultPlaces = ["/opt/nanobrew/prefix/bin/nb", NSHomeDirectory() + "/.local/bin/nb"]

    /// A given NBPath argument is the only candidate (D30); else the first executable file of the saved path
    /// and the default places, in the order of D24.
    public static func locate(argument: String?, saved: String?, places: [String] = defaultPlaces) -> String? {
        (argument.map { [$0] } ?? [saved].compactMap { $0 } + places).first {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && !isDir.boolValue
                && FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    public static func locate(defaults: UserDefaults = .standard) -> String? {
        locate(argument: launchArgument("NBPath"), saved: defaults.string(forKey: savedPathKey))
    }
}

/// A `-Name value` launch argument (the user-defaults argument domain).
public func launchArgument(_ name: String) -> String? {
    UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
}
