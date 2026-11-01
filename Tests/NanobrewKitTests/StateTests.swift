import Foundation
import Testing
@testable import NanobrewKit

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

func fixture(_ name: String) -> String { fixtures.appendingPathComponent(name).path }

func scratchDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct StateReaderTests {
    @Test func readsEveryFormulaAndCaskOfTheTrimmedFixture() throws {
        let snapshot = try #require(try StateReader.read(path: fixture("state.json")))
        // Expected values copied from Tests/Fixtures/state.json.
        #expect(snapshot.formulae.map { "\($0.name) \($0.version) \($0.pinned)" } == [
            "bzip2 1.0.8 false", "ncurses 6.6 false", "libedit 20260512-3.1 false", "xcodegen 2.46.0 false",
            "libffi 3.8.0 true", "libarchive 3.8.11 false", "node 26.13.0_2 false",
        ])
        #expect(snapshot.casks.map { "\($0.token) \($0.version)" } == [
            "clickhouse 26.10.2.103-stable", "puremac 3.2.0", "codex 0.166.0",
        ])
        #expect(snapshot.casks[1].apps == ["PureMac.app"])
        #expect(snapshot.casks[0].binaries == ["clickhouse"])
    }

    @Test func emptyFileGivesEmptyLists() throws {
        let snapshot = try #require(try StateReader.read(path: fixture("state-empty.json")))
        #expect(snapshot.formulae.isEmpty && snapshot.casks.isEmpty)
    }

    @MainActor @Test func missingFileGivesNotSetUp() {
        let model = AppModel(statePath: "/nonexistent/state.json", nbPath: nil)
        model.reload()
        #expect(model.notSetUp)
        #expect(model.snapshot == nil)
    }

    @MainActor @Test func brokenFileGivesErrorAndKeepsTheEarlierSnapshot() throws {
        let dir = try scratchDir()
        let path = dir.appendingPathComponent("state.json").path
        try FileManager.default.copyItem(atPath: fixture("state.json"), toPath: path)
        let model = AppModel(statePath: path, nbPath: nil)
        model.reload()
        #expect(model.snapshot?.formulae.count == 7)
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.copyItem(atPath: fixture("state-broken.json"), toPath: path)
        model.reload()
        #expect(model.stateError != nil)
        #expect(model.snapshot?.formulae.count == 7)
        #expect(!model.notSetUp)
    }
}

@Suite struct LocatorTests {
    func makeFile(_ dir: URL, _ name: String, executable: Bool) throws -> String {
        let path = dir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: executable ? 0o755 : 0o644])
        return path
    }

    @Test func followsTheOrderAndSkipsNonExecutables() throws {
        let dir = try scratchDir()
        let arg = try makeFile(dir, "arg", executable: true)
        let saved = try makeFile(dir, "saved", executable: true)
        let opt = try makeFile(dir, "opt", executable: true)
        let local = try makeFile(dir, "local", executable: true)
        let plain = try makeFile(dir, "plain", executable: false)
        let missing = dir.appendingPathComponent("missing").path
        #expect(NBLocator.locate(argument: arg, saved: saved, places: [opt, local]) == arg)
        #expect(NBLocator.locate(argument: plain, saved: saved, places: [opt, local]) == saved)
        #expect(NBLocator.locate(argument: nil, saved: missing, places: [opt, local]) == opt)
        #expect(NBLocator.locate(argument: nil, saved: nil, places: [plain, local]) == local)
        #expect(NBLocator.locate(argument: missing, saved: plain, places: [missing, dir.path]) == nil)
    }

    @Test func defaultPlacesAreOptThenLocalBin() {
        #expect(NBLocator.defaultPlaces == ["/opt/nanobrew/prefix/bin/nb", NSHomeDirectory() + "/.local/bin/nb"])
    }

    @MainActor @Test func nothingFoundGivesNotInstalled() {
        #expect(AppModel(statePath: fixture("state.json"), nbPath: nil).notInstalled)
    }
}
