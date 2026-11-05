import Foundation
import Testing
@testable import NanobrewKit

@Suite struct AboutTests {
    @Test func readsTheNbVersion() throws {
        #expect(parseNBVersion(try recorded("version")) == "0.1.214")
        #expect(parseNBVersion(["nb: error"]) == nil)
        #expect(NBCommand.version == NBCommand(args: ["version"], changes: false))
    }

    @Test func testedNbVersionIs0_1_215() {
        #expect(testedNBVersion == "0.1.215")
    }

    /// nb 0.1.215's rollback exits 1 on a failure (0.1.214 exited 0), so the status line says Failed.
    @MainActor @Test func aFailedRollbackShowsFailed() async throws {
        let nb = try FakeNB()
        try nb.exit("rollback", code: 1)
        try nb.stderr("rollback", text: "nb: the payload for jq 1.7 is no longer on disk; try `nb install jq@1.7`\n")
        let model = nb.model()
        await model.run(.rollback("jq")).value
        #expect(model.status?.text == "Failed: nb rollback jq (exit code 1)")
        #expect(model.console.contains("nb: the payload for jq 1.7 is no longer on disk; try `nb install jq@1.7`"))
    }

    @MainActor @Test func modelAsksNbForItsVersion() async throws {
        let nb = try FakeNB()
        #expect(await nb.model().nbVersion() == "0.1.214")
        #expect(nb.argvs == [["version"]])
    }
}
