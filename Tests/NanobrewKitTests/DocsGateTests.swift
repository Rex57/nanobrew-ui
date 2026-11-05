import Foundation
import Testing

/// The docs gate (tools/check_docs.py) is part of `swift test`: a broken link or anchor, a page the map
/// does not link, or a missing status line fails the suite.
@Suite struct DocsGateTests {
    /// The repo root: two folders above this file.
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().path

    static func gate(_ args: [String]) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", root + "/tools/check_docs.py"] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @Test func theDocsPassTheGate() throws {
        let result = try Self.gate([Self.root])
        #expect(result.code == 0, "\(result.output)")
    }

    @Test func theGatePassesItsSelftest() throws {
        let result = try Self.gate(["--selftest"])
        #expect(result.code == 0, "\(result.output)")
    }
}
