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
        #expect(command.changes && command.title == "sudo nb init")
    }

    @Test func theAdminScriptRunsNbWithAPathWithSpacesAndQuotes() async throws {
        // The same script without the admin clause, through the real osascript.
        let nb = try FakeNB()
        let odd = nb.dir.appendingPathComponent(#"my "odd" nb's dir"#)
        try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
        let link = odd.appendingPathComponent("nb").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: fixture("fake-nb"))
        let process = try NBProcess(path: "/usr/bin/osascript", args: ["-e", NBCommand.initScript(admin: false), link])
        for await _ in process.lines {}
        #expect(process.exitCode == 0)
        let log = try String(contentsOf: odd.appendingPathComponent("fake-nb.log"), encoding: .utf8)
        #expect(log.hasPrefix("START\tinit\n"))
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
