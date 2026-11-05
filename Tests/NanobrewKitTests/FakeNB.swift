import Foundation
@testable import NanobrewKit

/// A scratch folder with `nb` linked to the fake nb; see Tests/Fixtures/fake-nb.
struct FakeNB {
    let dir: URL
    var path: String { dir.appendingPathComponent("nb").path }

    init() throws {
        dir = try scratchDir()
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("nb").path,
                                                   withDestinationPath: fixture("fake-nb"))
    }

    /// The fake nb sleeps this long when its first argument is `command`.
    func wait(_ command: String, seconds: Int) throws {
        try "\(seconds)".write(to: dir.appendingPathComponent("wait-\(command)"), atomically: true, encoding: .utf8)
    }

    /// The fake nb and its sleep child ignore SIGTERM when the first argument is `command`.
    func ignoreTerm(_ command: String) throws {
        try "".write(to: dir.appendingPathComponent("ignore-term-\(command)"), atomically: true, encoding: .utf8)
    }

    /// The fake nb prints the recorded output `name` (Tests/Fixtures/nb-output/<name>.txt) for `command`.
    func output(_ command: String, recorded name: String) throws {
        try FileManager.default.copyItem(atPath: fixture("nb-output/\(name).txt"), toPath: dir.appendingPathComponent("out-\(command)").path)
    }

    func exit(_ command: String, code: Int) throws {
        try "\(code)".write(to: dir.appendingPathComponent("exit-\(command)"), atomically: true, encoding: .utf8)
    }

    func stderr(_ command: String, text: String) throws {
        try text.write(to: dir.appendingPathComponent("stderr-\(command)"), atomically: true, encoding: .utf8)
    }

    /// Log lines split at tabs: ["START", "arg1", ...].
    var log: [[String]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent("fake-nb.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// The argv of every run, in start order, the outdated checks too.
    var allArgvs: [[String]] { log.filter { $0.first == "START" }.map { Array($0.dropFirst()) } }
    /// The argv of every run but the outdated checks (the model starts one after each changing command).
    var argvs: [[String]] { allArgvs.filter { $0.first != "outdated" } }

    /// The process group of the first run that slept (the fake nb's pid): no process of that run is alive once
    /// `kill(-group, 0)` fails.
    func firstSleeperGroup() -> pid_t? {
        log.first { $0.first == "CHILD" }.flatMap { Int32($0[1]) }.map { getpgid($0) }
    }

    /// Ends the sleep children of `wait` that no cancel stopped.
    func killChildren() {
        for line in log where line.first == "CHILD" { if let pid = Int32(line[1]) { kill(pid, SIGKILL) } }
    }

    @MainActor func model(statePath: String = fixture("state.json"), readLimit: Duration = .seconds(60)) -> AppModel {
        AppModel(statePath: statePath, nbPath: path, readLimit: readLimit)
    }
}

/// Waits until `condition` is true, up to 10 seconds.
@MainActor func eventually(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
}
