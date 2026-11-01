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

    /// The versions of a formula in the history, without the installed one, oldest first.
    public func earlierVersions(of name: String) -> [String] {
        let current = formulae.first { $0.name == name }?.version
        return (history[name] ?? []).map(\.version).filter { $0 != current }
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

    /// The first candidate that is an executable file, in the order of D24.
    public static func locate(argument: String?, saved: String?, places: [String] = defaultPlaces) -> String? {
        ([argument, saved].compactMap { $0 } + places).first {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &isDir) && !isDir.boolValue
                && FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    public static func locate(defaults: UserDefaults = .standard) -> String? {
        // Test seam: `-NBDefaultPlaces "a:b"` replaces the default places ("" = none), so a Mac with nb can show "not installed".
        let places = launchArgument("NBDefaultPlaces").map { $0.split(separator: ":").map(String.init) } ?? defaultPlaces
        return locate(argument: launchArgument("NBPath"), saved: defaults.string(forKey: savedPathKey), places: places)
    }
}

/// A `-Name value` launch argument (the user-defaults argument domain).
public func launchArgument(_ name: String) -> String? {
    UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
}
