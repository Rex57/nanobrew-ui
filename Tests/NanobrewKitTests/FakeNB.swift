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

    func exit(_ command: String, code: Int) throws {
        try "\(code)".write(to: dir.appendingPathComponent("exit-\(command)"), atomically: true, encoding: .utf8)
    }

    /// Log lines split at tabs: ["START", "arg1", ...].
    var log: [[String]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent("fake-nb.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    /// The argv of every run, in start order.
    var argvs: [[String]] { log.filter { $0.first == "START" }.map { Array($0.dropFirst()) } }

    @MainActor func model(statePath: String = fixture("state.json")) -> AppModel {
        AppModel(statePath: statePath, nbPath: path)
    }
}

/// Waits until `condition` is true, up to 10 seconds.
@MainActor func eventually(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
}
