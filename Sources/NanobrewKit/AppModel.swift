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
    /// The console: one line per output line, with a header and an end line per command.
    public private(set) var console: [String] = []
    /// The changing command that runs now, and the changing commands that wait for their turn.
    public private(set) var running: NBCommand?
    public private(set) var waiting: [NBCommand] = []
    private var processes: [NBProcess] = []
    private var lastChange: Task<Void, Never>?

    public var notInstalled: Bool { nbPath == nil }
    public var askBeforeQuit: Bool { running != nil || !waiting.isEmpty }
    public var canCancel: Bool { !processes.isEmpty }

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

    /// Runs a command with its output in the console. Changing commands wait in a serial queue;
    /// read-only commands start at once. The task ends when the command has ended.
    @discardableResult
    public func run(_ command: NBCommand) -> Task<Void, Never> {
        guard command.changes else { return Task { await execute(command) } }
        waiting.append(command)
        let previous = lastChange
        let task = Task {
            await previous?.value
            waiting.removeFirst()
            running = command
            await execute(command)
            running = nil
        }
        lastChange = task
        return task
    }

    /// Stops the commands that run now; queued commands then run.
    public func cancel() {
        processes.forEach { $0.cancel() }
    }

    private func execute(_ command: NBCommand) async {
        console.append("$ \(command.title)")
        guard let nbPath else { console.append("Failed: nb is not installed"); return }
        let process: NBProcess
        do {
            process = try NBProcess(path: nbPath, args: command.args)
        } catch {
            console.append("Failed: \(command.title) (\(error.localizedDescription))")
            return
        }
        processes.append(process)
        for await line in process.lines { console.append(line) }
        processes.removeAll { $0 === process }
        if process.wasCancelled {
            console.append("Cancelled: \(command.title)")
        } else if let code = process.exitCode, code == 0 {
            console.append("Done: \(command.title)")
        } else {
            console.append("Failed: \(command.title) (exit code \(process.exitCode.map(String.init) ?? "signal"))")
        }
        reload()
    }
}
