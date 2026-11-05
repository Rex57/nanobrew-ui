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
    /// The rows of the last outdated check (empty when it failed): Updates, and the status marks of Installed.
    public private(set) var outdatedPackages: [OutdatedPackage] = []
    /// nb's error text when the last outdated check failed.
    public private(set) var outdatedError: String?
    /// False until the first outdated check has ended.
    public private(set) var outdatedChecked = false
    /// The console: one line per output line, with a header and an end line per command; the last
    /// `consoleLimit` lines (D3), older lines drop off the top.
    public private(set) var console: [String] = [] {
        didSet {
            let extra = console.count - Self.consoleLimit
            guard extra > 0 else { return }
            console.removeFirst(extra)
            consoleDropped += extra
        }
    }
    public static let consoleLimit = 20_000
    /// How many lines dropped off the top of the console this session: the console view trims the same lines.
    public private(set) var consoleDropped = 0
    /// The changing command that runs now, and the changing commands that wait for their turn.
    public private(set) var running: NBCommand?
    public private(set) var waiting: [NBCommand] = []
    /// Every command that runs now, read-only ones too.
    public private(set) var inProgress: [NBCommand] = []
    /// Changes once each time a command ends, read-only or changing: views with their own fetched data re-load on it.
    public private(set) var commandsEnded = 0
    /// The outdated check after the last changing command or activation; a newer one waits for it to end (a
    /// cancel would end its nb runs, D5), so one check runs at a time.
    private var backgroundCheck: Task<Void, Never>?
    /// A command that waits for the user's yes before it runs.
    public private(set) var pendingConfirmation: NBCommand?
    private var processes: [NBProcess] = []
    private var succeeded: Set<NBCommand> = []

    /// True when the last run of this command (through `run`) exited 0; false after a failure or a cancel.
    public func lastRunSucceeded(_ command: NBCommand) -> Bool { succeeded.contains(command) }

    /// D8: the --prune-kegs setting of the last successful cleanup dry run; nil after a failure, a cancel, a
    /// Clean Up or leaving Maintenance.
    private var cleanupDryRunFor: Bool?
    /// Counts the times Maintenance went away: a dry run that ends after that counts no more.
    private var cleanupDryRunsForgotten = 0
    /// Clean Up runs only after a successful dry run with the same --prune-kegs setting.
    public func canCleanUp(pruneKegs: Bool) -> Bool { cleanupDryRunFor == pruneKegs }

    /// The dry run keeps the setting it started with, even when the switch moves while it runs.
    @discardableResult
    public func dryRunCleanup(pruneKegs: Bool) -> Task<Void, Never> {
        let dryRun = NBCommand.cleanupDryRun(pruneKegs: pruneKegs)
        let task = run(dryRun)
        let forgotten = cleanupDryRunsForgotten
        return Task {
            await task.value
            guard forgotten == cleanupDryRunsForgotten else { return }
            cleanupDryRunFor = lastRunSucceeded(dryRun) ? pruneKegs : nil
        }
    }

    /// Maintenance calls it when it goes away: the next visit needs a new dry run, as before C-7.
    public func forgetCleanupDryRun() {
        cleanupDryRunFor = nil
        cleanupDryRunsForgotten += 1
    }

    /// Asks before the cleanup; the next Clean Up needs a new dry run.
    public func cleanUp(pruneKegs: Bool) {
        cleanupDryRunFor = nil
        request(.cleanup(pruneKegs: pruneKegs))
    }
    private var lastChange: Task<Void, Never>?
    /// The status line (DD4): the last command's result and how long it took, or the one that runs now.
    public private(set) var status: CommandStatus?
    /// The console: closed at start; only the user opens and closes it (D1, which changed DD5).
    public private(set) var consoleShown = false
    public func toggleConsole() { consoleShown.toggle() }
    /// A monotonic clock for the durations; tests inject their own.
    private let now: @MainActor () -> ContinuousClock.Instant
    /// The app's own preferences: the Reinstall verdicts (DD15).
    let defaults: UserDefaults
    /// Counts the verdicts recorded: a view that reads a verdict redraws when one is recorded (UserDefaults is
    /// not observed, and an outdated check with the same rows does not notify).
    var verdictsRecorded = 0

    /// A line in the console and a failure in the status line that is not a command's own result.
    func reportFailure(_ text: String) {
        console.append(text)
        status = CommandStatus(kind: .failure, text: text)
    }

    public var notInstalled: Bool { nbPath == nil }
    public var askBeforeQuit: Bool { running != nil || !waiting.isEmpty || !reinstalling.isEmpty }
    /// The casks whose Reinstall has started and whose install step has not ended (F1: a quit asks first).
    public internal(set) var reinstalling: Set<String> = []

    /// The text of the quit and close question. A cask whose install step runs is not "removed" for good: nb's
    /// install goes on after a quit (D34).
    public var quitMessage: String {
        let names = reinstalling.filter { running != .install($0, cask: true) }.sorted()
        guard !names.isEmpty else {
            return "nb keeps running in the background until it ends. You will not see its output."
        }
        return "\(names.joined(separator: ", ")) \(names.count == 1 ? "is" : "are") removed, or being removed, and "
            + "\(names.count == 1 ? "is" : "are") not installed yet. If you quit, \(names.count == 1 ? "it stays" : "they stay") "
            + "removed until you install \(names.count == 1 ? "it" : "them") again from Discover."
    }
    public var canCancel: Bool { !processes.isEmpty }

    private let locate: (@MainActor () -> String?)?
    /// D5: a background read that has not ended after this long is ended and fails with `timeoutText`.
    public let readLimit: Duration

    /// `locate` finds nb again on `checkAgain()`; without it the nb path stays fixed (tests).
    public init(statePath: String, nbPath: String?, appVersion: String? = nil, locate: (@MainActor () -> String?)? = nil,
                now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
                defaults: UserDefaults = .standard, readLimit: Duration = .seconds(60)) {
        self.now = now
        self.readLimit = readLimit
        self.defaults = defaults
        self.statePath = statePath
        self.nbPath = nbPath
        self.appVersion = appVersion
        self.locate = locate
    }

    /// Finds nb and reads state.json again (Cmd-R, app active, after every command).
    public func checkAgain() {
        if let locate { nbPath = locate() }
        reload()
    }

    /// D11: the app came to the front: find nb, read state.json and check outdated (not awaited).
    /// The window calls it at launch too; the launch and the first activation come together, so one check serves
    /// both (row 6), and the first check of the session puts its result in the status line.
    public func becameActive() {
        checkAgain()
        guard backgroundChecks == 0 else { return }
        startOutdatedCheck(report: !outdatedChecked)
    }

    /// Background checks that started and did not end yet.
    private var backgroundChecks = 0

    private func startOutdatedCheck(report: Bool = false) {
        let previous = backgroundCheck
        backgroundChecks += 1
        backgroundCheck = Task {
            await previous?.value
            await checkOutdated(report: report)
            backgroundChecks -= 1
        }
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

    /// The one path of every background read (D5): the nb run ends when the caller's task is cancelled, when it
    /// has not ended after `readLimit` (then it throws the timeout text), and at `endBackgroundReads()`.
    private func read(_ command: NBCommand, separateStderr: Bool = false) async throws -> (lines: [String], process: NBProcess) {
        guard let nbPath else { throw CommandFailed(text: "nb is not installed") }
        let process = try NBProcess(path: nbPath, args: command.args, separateStderr: separateStderr)
        reads.append(process)
        defer { reads.removeAll { $0 === process } }
        let limit = readLimit
        let timer = Task { () -> Bool in
            guard (try? await Task.sleep(for: limit)) != nil else { return false }
            process.cancel()
            return true
        }
        let lines = await withTaskCancellationHandler {
            var lines: [String] = []
            for await batch in process.lines { lines += batch }
            return lines
        } onCancel: { process.cancel() }
        timer.cancel()
        if await timer.value {
            throw CommandFailed(text: "nb did not answer in \(formatDuration(limit)). Another nb command may be running, "
                                + "or the network does not answer.")
        }
        return (lines, process)
    }

    /// The background reads that run now: `endBackgroundReads()` ends them.
    private var reads: [NBProcess] = []

    /// The app quits: its background reads end; console commands go on (D34).
    public func endBackgroundReads() { reads.forEach { $0.cancel() } }

    /// Runs a read-only command without the console and returns its lines and exit code (nil: no nb, or a signal).
    /// A read past the limit returns the timeout text as its one line.
    public func capture(_ command: NBCommand) async -> (lines: [String], exitCode: Int32?) {
        do {
            let (lines, process) = try await read(command)
            return (lines, process.exitCode)
        } catch let failed as CommandFailed where nbPath != nil {
            return ([failed.text], nil)
        } catch {
            return ([], nil)
        }
    }

    /// stdout of a read-only command, stderr apart. A non-zero exit throws nb's error text (never an empty list).
    private func captureStdout(_ command: NBCommand) async throws -> [String] {
        let (lines, process) = try await read(command, separateStderr: true)
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

    /// Cmd-R, the top-bar button and Updates' Check Again: find nb, read state.json, check outdated. It joins a
    /// running check (D5) and still reports it in the status line.
    public func refresh() async {
        checkAgain()
        let start = now()
        await sharedOutdatedCheck()
        reportChecked(since: start)
    }

    /// Updates opening and `refresh()`: joins the running check, or starts one; never two at once (D5).
    public func sharedOutdatedCheck() async {
        if backgroundChecks == 0 { startOutdatedCheck() }
        await backgroundCheck?.value
    }

    private func reportChecked(since start: ContinuousClock.Instant) {
        guard outdatedError == nil, let snapshot else { return }
        status = CommandStatus(kind: .success, text: "Checked \(snapshot.formulae.count + snapshot.casks.count) packages in "
                               + formatDuration(now() - start))
    }

    /// Sets `updatesCount` (at launch, on activation, on Cmd-R, when Updates opens and after a changing command).
    /// `report` puts the check in the status line (launch and Cmd-R), so it does not replace the result of the command that just ended. A cancelled check
    /// (the user left Updates) changes nothing.
    public func checkOutdated(report: Bool = false) async {
        let start = report ? now() : nil
        do {
            let rows = try await outdated()
            guard !Task.isCancelled else { return }
            outdatedPackages = rows
            outdatedError = nil
        } catch {
            guard !Task.isCancelled else { return }
            outdatedPackages = []
            outdatedError = error.localizedDescription
        }
        outdatedChecked = true
        updatesCount = outdatedPackages.isEmpty ? nil : outdatedPackages.count
        if let start { reportChecked(since: start) }
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
        // A run that cannot start must not leave an earlier success standing (the Reinstall guard reads it).
        succeeded.remove(command)
        console.append("$ \(command.title)")
        guard let path = command.program ?? nbPath else { reportFailure("Failed: nb is not installed"); return }
        let process: NBProcess
        do {
            process = try NBProcess(path: path, args: command.args)
        } catch {
            reportFailure("Failed: \(command.title) (\(error.localizedDescription))")
            return
        }
        processes.append(process)
        inProgress.append(command)
        // While a changing command runs, the status line keeps showing it; a parallel read-only one stays out.
        let quiet = !command.changes && running != nil
        if !quiet { status = CommandStatus(kind: .running, text: "Running: \(command.title)") }
        let start = now()
        var output: [String] = []
        var summary: String?
        let summarizes = CommandStatus.summaryLabel(command) != nil
        for await batch in process.lines {
            console.append(contentsOf: batch)
            // Only an upgrade's outcome reads the output: other commands keep no copy beside the capped console,
            // at most their summary line (D4).
            if command.verb == "upgrade" { output += batch }
            if summarizes, let line = batch.last(where: { CommandStatus.summary(of: command, line: $0) != nil }) { summary = line }
        }
        checkAgain()
        let exitCode = process.wasCancelled ? nil : process.exitCode
        let outcome = UpgradeOutcome(command: command, output: output, exitCode: exitCode, casks: snapshot?.casks,
                                     appVersion: appVersion)
        record(outcome.skips)
        // Decided at the end: a read-only command that started before a change must not hide it either.
        if command.changes || running == nil {
            status = CommandStatus(command: command, exitCode: exitCode, cancelled: process.wasCancelled,
                                   duration: now() - start, skipped: outcome.skips.map(\.token), summary: summary)
        }
        processes.removeAll { $0 === process }
        inProgress.remove(at: inProgress.firstIndex(of: command)!)
        if !process.wasCancelled, process.exitCode == 0 { succeeded.insert(command) } else { succeeded.remove(command) }
        if process.wasCancelled {
            console.append("Cancelled: \(command.title)")
        } else if let code = process.exitCode, code == 0 {
            console.append("Done: \(command.title)")
        } else {
            console.append("Failed: \(command.title) (exit code \(process.exitCode.map(String.init) ?? "signal"))")
        }
        if outcome.replacedSelf { restartOffered = true }
        // D11: only a changing command can change what is outdated.
        if command.changes { startOutdatedCheck() }
        commandsEnded += 1
    }
}
