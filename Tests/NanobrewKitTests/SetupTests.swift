import Foundation
import Testing
@testable import NanobrewKit

@MainActor @Suite struct SetupTests {
    @Test func nukeRunsOnlyWhenTheTypedTextIsExactlyYes() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        #expect(NBCommand.nuke == NBCommand(args: ["nuke", "--yes"], changes: true, confirmation: .typeYes))
        for typed in ["", "no", "Yes", "YES", "yes ", " yes", "y"] {
            model.request(.nuke)
            #expect(model.pendingConfirmation == .nuke)
            #expect(model.confirm(typed: typed) == nil, "typed \(typed)")
            #expect(model.pendingConfirmation == nil)
        }
        model.request(.nuke)
        #expect(model.confirm() == nil, "a plain yes button is not enough")
        try await Task.sleep(for: .milliseconds(300))
        #expect(nb.argvs.isEmpty)
        model.request(.nuke)
        await model.confirm(typed: "yes")?.value
        #expect(nb.argvs == [["nuke", "--yes"]])
    }

    @Test func migrateIsChangingAndNeedsConfirmation() {
        #expect(NBCommand.migrate == NBCommand(args: ["migrate"], changes: true, confirmation: .ask))
    }

    @Test func adminCommandPassesTheNbPathAsItsOwnArgument() throws {
        let path = #"/Applications/My "nb" dir/bin/it's nb; rm -rf ~"#
        let command = NBCommand.initNanobrew(nbPath: path)
        #expect(command.program == "/usr/bin/osascript")
        #expect(command.args.last == path)
        #expect(!command.args.dropLast().joined().contains("My"))
        #expect(command.args.dropLast().joined().contains("quoted form of"))
        #expect(command.args.dropLast().joined().contains("with administrator privileges"))
        #expect(command.changes && command.title == "sudo \(path) init")
    }

    /// The app's real admin argv, through the real osascript, with one script edit applied.
    func runAdminArgs(nbPath: String, replacing old: String, with new: String) async throws -> (lines: [String], code: Int32?) {
        var args = NBCommand.initNanobrew(nbPath: nbPath).args
        // A hard stop: with the edit not applied, osascript would open a real admin password dialog.
        try #require(args[1].contains(old))
        args[1] = args[1].replacingOccurrences(of: old, with: new)
        let process = try NBProcess(path: "/usr/bin/osascript", args: args)
        var lines: [String] = []
        for await batch in process.lines { lines += batch }
        return (lines, process.exitCode)
    }

    @Test func theAdminScriptRunsNbWithAPathWithSpacesAndQuotes() async throws {
        // Only the admin clause is removed, so no password dialog shows.
        let nb = try FakeNB()
        let odd = nb.dir.appendingPathComponent(#"my "odd" nb's dir"#)
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        let link = odd.appendingPathComponent("nb").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fixture("fake-nb"))
        let result = try await runAdminArgs(nbPath: link, replacing: " with administrator privileges", with: "")
        #expect(result.code == 0)
        let log = try String(contentsOf: odd.appendingPathComponent("fake-nb.log"), encoding: .utf8)
        #expect(log.hasPrefix("START\tinit\n"))
    }

    @Test func dontAllowInTheAdminDialogEndsAsCancelledNotFailed() async throws {
        // Error -128 is what "Don't Allow" raises; the test raises it in place of the dialog.
        let nb = try FakeNB()
        let result = try await runAdminArgs(
            nbPath: nb.path,
            replacing: #"do shell script (quoted form of (item 1 of argv)) & " init" with administrator privileges"#,
            with: "error number -128")
        #expect(result.code == 0)
        #expect(result.lines == ["Set-up cancelled"])
        #expect(nb.argvs.isEmpty)
    }

    @Test func modelRunsTheAdminCommandWithItsProgram() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        // A fake program in place of osascript: it logs its argv like nb.
        await model.run(NBCommand(program: nb.path, args: ["init-through-fake"], changes: true, label: "x")).value
        #expect(nb.argvs == [["init-through-fake"]])
    }

    @Test func checkAgainFindsNbAndTheStateAgain() async throws {
        let nb = try FakeNB()
        var found: String? = nil
        let model = AppModel(statePath: "/nonexistent/state.json", nbPath: nil, locate: { found })
        model.checkAgain()
        #expect(model.notInstalled && model.notSetUp)
        found = nb.path
        model.checkAgain()
        #expect(!model.notInstalled)
    }

    @Test func afterNukeTheModelChecksNbAgain() async throws {
        let nb = try FakeNB()
        var found: String? = nb.path
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, locate: { found })
        found = nil // nuke removed nb
        model.request(.nuke)
        await model.confirm(typed: "yes")?.value
        #expect(model.notInstalled)
    }
}
