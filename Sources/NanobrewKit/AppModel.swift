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
    /// The number on Updates in the sidebar: outdated formulae plus casks; nil for 0 or when the check failed.
    public private(set) var updatesCount: Int?
    /// The rows of the last outdated check (empty when it failed): the status marks of Installed.
    public private(set) var outdatedPackages: [OutdatedPackage] = []
    /// The console: one line per output line, with a header and an end line per command.
    // shortcut: every line of the session is kept (a few MB at the expected load); cap it if sessions
    // reach tens of MB of output (for example a long-running command left open for days).
    public private(set) var console: [String] = []
    /// The changing command that runs now, and the changing commands that wait for their turn.
    public private(set) var running: NBCommand?
    public private(set) var waiting: [NBCommand] = []
    /// Every command that runs now, read-only ones too.
    public private(set) var inProgress: [NBCommand] = []
    /// A command that waits for the user's yes before it runs.
    public private(set) var pendingConfirmation: NBCommand?
    private var processes: [NBProcess] = []
    private var succeeded: Set<NBCommand> = []

    /// True when the last run of this command (through `run`) exited 0; false after a failure or a cancel.
    public func lastRunSucceeded(_ command: NBCommand) -> Bool { succeeded.contains(command) }
    private var lastChange: Task<Void, Never>?
    /// The status line (DD4): the last command's result and how long it took, or the one that runs now.
    public private(set) var status: CommandStatus?
    /// The console (DD5): closed at start, open while a command runs, closed when it ends unless pinned.
    public private(set) var consoleShown = false
    public var consolePinned = false
    public func toggleConsole() { consoleShown.toggle() }
    /// A monotonic clock for the durations; tests inject their own.
    private let now: @MainActor () -> ContinuousClock.Instant

    public var notInstalled: Bool { nbPath == nil }
    public var askBeforeQuit: Bool { running != nil || !waiting.isEmpty }
    public var canCancel: Bool { !processes.isEmpty }

    private let locate: (@MainActor () -> String?)?

    /// `locate` finds nb again on `checkAgain()`; without it the nb path stays fixed (tests).
    public init(statePath: String, nbPath: String?, appVersion: String? = nil, locate: (@MainActor () -> String?)? = nil,
                now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
        self.statePath = statePath
        self.nbPath = nbPath
        self.appVersion = appVersion
        self.locate = locate
    }

    /// Finds nb and reads state.json again (Cmd-R, app active, after each command).
    public func checkAgain() {
        if let locate { nbPath = locate() }
        reload()
    }

    /// The model the app starts with: launch arguments first, then the default places.
    public static func fromLaunch() -> AppModel {
        AppModel(statePath: launchArgument("NBStatePath") ?? StateReader.defaultPath, nbPath: NBLocator.locate(),
                 appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                 locate: { NBLocator.locate() })
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

    /// The user said yes: the pending command runs. A `.typeYes` command runs only when `typed` is exactly "yes".
    @discardableResult
    public func confirm(typed: String = "") -> Task<Void, Never>? {
        guard let command = pendingConfirmation else { return nil }
        pendingConfirmation = nil
        guard command.confirmation != .typeYes || typed == "yes" else { return nil }
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

    /// stdout of a read-only command, stderr apart. A non-zero exit throws nb's error text (never an empty list).
    private func captureStdout(_ command: NBCommand) async throws -> [String] {
        guard let nbPath else { throw CommandFailed(text: "nb is not installed") }
        let process = try NBProcess(path: nbPath, args: command.args, separateStderr: true)
        var lines: [String] = []
        for await batch in process.lines { lines += batch }
        guard process.exitCode == 0 else {
            let joined = { (lines: [String]) in lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            let text = joined(process.stderrLines).isEmpty ? joined(lines) : joined(process.stderrLines)
            throw CommandFailed(text: text.isEmpty ? "\(command.title) failed (exit code \(process.exitCode.map(String.init) ?? "none"))" : text)
        }
        return lines
    }

    public func search(_ query: String) async throws -> [SearchResult] {
        SearchResult.parse(try await captureStdout(.search(query)))
    }

    /// The text of `nb completions <shell>`, with nb's final newline; nil when nb fails.
    public func completions(_ shell: String) async -> String? {
        guard let lines = try? await captureStdout(.completions(shell)) else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    public func autoupdateStatus() async -> AutoupdateStatus? { AutoupdateStatus.parse(await capture(.autoupdateStatus).lines) }

    public func telemetryEnabled() async -> Bool? { parseTelemetry(await capture(.telemetryStatus).lines) }

    public struct CommandFailed: Error, LocalizedError, Equatable {
        public let text: String
        public var errorDescription: String? { text }
    }

    /// Writes nb's stdout of `nb bundle dump` to `url`; nothing is written when nb fails (its stderr is thrown).
    public func bundleDump(to url: URL) async throws {
        let lines = try await captureStdout(.bundleDump)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Saves the nb path of the Settings field (empty clears it) and finds nb again.
    public func saveNBPath(_ path: String, defaults: UserDefaults = .standard) {
        if path.isEmpty { defaults.removeObject(forKey: NBLocator.savedPathKey) } else { defaults.set(path, forKey: NBLocator.savedPathKey) }
        nbPath = NBLocator.locate(defaults: defaults)
    }

    public func nbVersion() async -> String? { parseNBVersion(await capture(.version).lines) }

    public func services() async throws -> [Service] { Service.parse(try await captureStdout(.servicesList)) }

    /// Formulae from `nb outdated`, casks from `nb outdated --cask`.
    public func outdated() async throws -> [OutdatedPackage] {
        async let formulae = captureStdout(.outdated)
        async let casks = captureStdout(.outdatedCasks)
        return try await OutdatedPackage.parse(formulae).filter { !$0.isCask } + OutdatedPackage.parse(casks)
    }

    /// Sets `updatesCount` (at launch, on Cmd-R and after each command). `report` puts the check in the status
    /// line (launch and Cmd-R), so it does not replace the result of the command that just ended.
    public func checkOutdated(report: Bool = false) async {
        let start = now()
        outdatedPackages = (try? await outdated()) ?? []
        updatesCount = outdatedPackages.isEmpty ? nil : outdatedPackages.count
        guard report, let snapshot else { return }
        status = CommandStatus(kind: .success, text: "Checked \(snapshot.formulae.count + snapshot.casks.count) packages in "
                               + formatDuration(now() - start))
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
        guard let path = command.program ?? nbPath else { console.append("Failed: nb is not installed"); return }
        let process: NBProcess
        do {
            process = try NBProcess(path: path, args: command.args)
        } catch {
            console.append("Failed: \(command.title) (\(error.localizedDescription))")
            return
        }
        processes.append(process)
        inProgress.append(command)
        consoleShown = true
        status = CommandStatus(kind: .running, text: "Running: \(command.title)")
        let start = now()
        for await batch in process.lines { console.append(contentsOf: batch) }
        status = CommandStatus(command: command, exitCode: process.wasCancelled ? nil : process.exitCode,
                               cancelled: process.wasCancelled, duration: now() - start)
        processes.removeAll { $0 === process }
        inProgress.remove(at: inProgress.firstIndex(of: command)!)
        if inProgress.isEmpty, !consolePinned { consoleShown = false }
        if !process.wasCancelled, process.exitCode == 0 { succeeded.insert(command) } else { succeeded.remove(command) }
        if process.wasCancelled {
            console.append("Cancelled: \(command.title)")
        } else if let code = process.exitCode, code == 0 {
            console.append("Done: \(command.title)")
        } else {
            console.append("Failed: \(command.title) (exit code \(process.exitCode.map(String.init) ?? "signal"))")
        }
        checkAgain()
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
