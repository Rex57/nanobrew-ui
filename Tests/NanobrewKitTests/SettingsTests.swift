import Foundation
import Testing
@testable import NanobrewKit

@Suite struct SettingsTests {
    @Test func catalogueGivesBundleAndSettingsCommands() {
        #expect(NBCommand.bundleDump == NBCommand(args: ["bundle", "dump"], changes: false))
        #expect(NBCommand.bundleInstall("/tmp/My Nanobrew") ==
                NBCommand(args: ["bundle", "install", "/tmp/My Nanobrew"], changes: true, confirmation: .ask))
        #expect(NBCommand.telemetryStatus == NBCommand(args: ["telemetry", "status"], changes: false))
        #expect(NBCommand.telemetry(on: true) == NBCommand(args: ["telemetry", "on"], changes: true))
        #expect(NBCommand.telemetry(on: false) == NBCommand(args: ["telemetry", "off"], changes: true))
        for shell in ["zsh", "bash", "fish"] {
            #expect(NBCommand.completions(shell) == NBCommand(args: ["completions", shell], changes: false))
        }
        #expect(NBCommand.trustAttest("jq", cask: false, output: nil).args == ["trust", "attest", "jq"])
        #expect(NBCommand.trustAttest("iterm2", cask: true, output: nil).args == ["trust", "attest", "iterm2", "--cask"])
        #expect(NBCommand.trustAttest("jq", cask: false, output: "/tmp/a.json").args == ["trust", "attest", "jq", "--output", "/tmp/a.json"])
        #expect(NBCommand.trustAttest("iterm2", cask: true, output: "/tmp/a.json").args ==
                ["trust", "attest", "iterm2", "--cask", "--output", "/tmp/a.json"])
        #expect(NBCommand.trustAttest("jq", cask: false, output: nil).changes)
    }

    @Test func parsesTelemetryStatus() throws {
        #expect(parseTelemetry(try recorded("telemetry_status")) == true)
        // Wording from nanobrew main.zig:5956.
        #expect(parseTelemetry(["Telemetry is off."]) == false)
        #expect(parseTelemetry(["nb: something failed"]) == nil)
    }

    @MainActor @Test func savedNbPathIsUsedBeforeTheDefaultPlaces() throws {
        let nb = try FakeNB()
        let defaults = try #require(UserDefaults(suiteName: "nbui-test-\(UUID().uuidString)"))
        let model = AppModel(statePath: fixture("state.json"), nbPath: nil)
        model.saveNBPath(nb.path, defaults: defaults)
        #expect(defaults.string(forKey: NBLocator.savedPathKey) == nb.path)
        #expect(NBLocator.locate(defaults: defaults) == nb.path)
        #expect(model.nbPath == nb.path)
        model.saveNBPath("", defaults: defaults)
        #expect(defaults.string(forKey: NBLocator.savedPathKey) == nil)
    }

    @MainActor @Test func bundleDumpWritesNbOutputToTheFile() async throws {
        let nb = try FakeNB()
        let file = nb.dir.appendingPathComponent("My Nanobrew")
        try await nb.model().bundleDump(to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == String(contentsOfFile: fixture("nb-output/bundle_dump.txt"), encoding: .utf8))
        #expect(nb.argvs == [["bundle", "dump"]])
    }

    @MainActor @Test func failedBundleDumpThrowsAndWritesNothing() async throws {
        let nb = try FakeNB()
        try nb.exit("bundle", code: 1)
        let file = nb.dir.appendingPathComponent("Nanobrew")
        await #expect(throws: (any Error).self) { try await nb.model().bundleDump(to: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
