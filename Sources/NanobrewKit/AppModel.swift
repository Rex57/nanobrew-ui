import Foundation
import Observation

/// The app's state. The views only read it and call it.
@MainActor @Observable
public final class AppModel {
    public let statePath: String
    public private(set) var nbPath: String?
    public private(set) var snapshot: StateSnapshot?
    public private(set) var notSetUp = false
    public private(set) var stateError: String?

    public var notInstalled: Bool { nbPath == nil }

    public init(statePath: String, nbPath: String?) {
        self.statePath = statePath
        self.nbPath = nbPath
    }

    /// The model the app starts with: launch arguments first, then the default places.
    public static func fromLaunch() -> AppModel {
        AppModel(statePath: launchArgument("NBStatePath") ?? StateReader.defaultPath, nbPath: NBLocator.locate())
    }

    /// Reads state.json again. A broken file keeps the last good snapshot.
    public func reload() {
        do {
            snapshot = try StateReader.read(path: statePath)
            notSetUp = snapshot == nil
            stateError = nil
        } catch {
            stateError = "Cannot read \(statePath): \(error.localizedDescription)"
        }
    }
}
