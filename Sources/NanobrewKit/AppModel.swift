import Foundation
import Observation

/// The app's state. The views only read it and call it.
@MainActor @Observable
public final class AppModel {
    public let statePath: String
    /// The version of the running app; nil in tests that do not care.
    public let appVersion: String?
    /// True after a successful upgrade replaced Nanobrew UI itself (D20).
    public private(set) var restartOffered = false
    public private(set) var nbPath: String?
    public private(set) var snapshot: StateSnapshot?
    public private(set) var notSetUp = false
    public private(set) var stateError: String?
    /// The console: one line per output line, with a header and an end line per command.
    public private(set) var console: [String] = []
    /// The changing command that runs now, and the changing commands that wait for their turn.
    public private(set) var running: NBCommand?
    public private(set) var waiting: [NBCommand] = []
    /// Every command that runs now, read-only ones too.
    public private(set) var inProgress: [NBCommand] = []
    /// A command that waits for the user's yes before it runs.
    public private(set) var pendingConfirmation: NBCommand?
    private var processes: [NBProcess] = []
    private var lastChange: Task<Void, Never>?

    public var notInstalled: Bool { nbPath == nil }
    public var askBeforeQuit: Bool { running != nil || !waiting.isEmpty }
    public var canCancel: Bool { !processes.isEmpty }

    public init(statePath: String, nbPath: String?, appVersion: String? = nil) {
        self.statePath = statePath
        self.nbPath = nbPath
        self.appVersion = appVersion
    }

    /// The model the app starts with: launch arguments first, then the default places.
    public static func fromLaunch() -> AppModel {
        AppModel(statePath: launchArgument("NBStatePath") ?? StateReader.defaultPath, nbPath: NBLocator.locate(),
                 appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
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

    /// The way the views start a command: one that needs a confirmation waits in `pendingConfirmation`.
    @discardableResult
    public func request(_ command: NBCommand) -> Task<Void, Never>? {
        guard command.confirmation == .none else { pendingConfirmation = command; return nil }
        return run(command)
    }

    /// The user said yes: the pending command runs.
    @discardableResult
    public func confirm() -> Task<Void, Never>? {
        guard let command = pendingConfirmation else { return nil }
        pendingConfirmation = nil
        return run(command)
    }

    public func decline() { pendingConfirmation = nil }

    /// Stops the commands that run now; queued commands then run.
    public func cancel() {
        processes.forEach { $0.cancel() }
    }

    /// Runs a read-only command without the console and returns its lines and exit code (nil: no nb, or a signal).
    public func capture(_ command: NBCommand) async -> (lines: [String], exitCode: Int32?) {
        guard let nbPath, let process = try? NBProcess(path: nbPath, args: command.args) else { return ([], nil) }
        var lines: [String] = []
        for await batch in process.lines { lines += batch }
        return (lines, process.exitCode)
    }

    public func search(_ query: String) async -> [SearchResult] {
        SearchResult.parse(await capture(.search(query)).lines)
    }

    public func services() async -> [Service] { Service.parse(await capture(.servicesList).lines) }

    /// Formulae from `nb outdated`, casks from `nb outdated --cask`.
    public func outdated() async -> [OutdatedPackage] {
        async let formulae = capture(.outdated)
        async let casks = capture(.outdatedCasks)
        return await OutdatedPackage.parse(formulae.lines).filter { !$0.isCask } + OutdatedPackage.parse(casks.lines)
    }

    /// The detail pane of a package: parsed info (or nb's error text) and, for a formula, the dependency tree.
    public func detail(name: String, cask: Bool) async -> PackageDetail {
        let (lines, code) = await capture(cask ? .caskInfo(name) : .info(name))
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == 0, let info = PackageInfo.parse(lines) else {
            return PackageDetail(error: text.isEmpty ? "nb info failed (exit code \(code.map(String.init) ?? "none"))" : text)
        }
        guard !cask else { return PackageDetail(info: info) }
        let tree = await capture(.depsTree(name))
        return PackageDetail(info: info, tree: tree.lines.filter { !$0.hasPrefix("==>") }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines))
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
        inProgress.append(command)
        for await batch in process.lines { console.append(contentsOf: batch) }
        processes.removeAll { $0 === process }
        inProgress.remove(at: inProgress.firstIndex(of: command)!)
        if process.wasCancelled {
            console.append("Cancelled: \(command.title)")
        } else if let code = process.exitCode, code == 0 {
            console.append("Done: \(command.title)")
        } else {
            console.append("Failed: \(command.title) (exit code \(process.exitCode.map(String.init) ?? "signal"))")
        }
        reload()
        if !process.wasCancelled, process.exitCode == 0, replacedSelf(command) { restartOffered = true }
    }

    /// An upgrade of nanobrew-ui (or of everything) after which state.json holds another version than this app.
    private func replacedSelf(_ command: NBCommand) -> Bool {
        let token = "nanobrew-ui"
        guard command.args.first == "upgrade", let appVersion,
              let installed = snapshot?.casks.first(where: { $0.token == token })?.version else { return false }
        let names = command.args.dropFirst().filter { !$0.hasPrefix("-") }
        return (names.isEmpty || names.contains { $0 == token || $0.hasSuffix("/" + token) }) && installed != appVersion
    }
}
