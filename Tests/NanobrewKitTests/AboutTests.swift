import Foundation
import Testing
@testable import NanobrewKit

@Suite struct AboutTests {
    @Test func readsTheNbVersion() throws {
        #expect(parseNBVersion(try recorded("version")) == "0.1.214")
        #expect(parseNBVersion(["nb: error"]) == nil)
        #expect(NBCommand.version == NBCommand(args: ["version"], changes: false))
    }

    @Test func testedNbVersionIs0_1_214() {
        #expect(testedNBVersion == "0.1.214")
    }

    @MainActor @Test func modelAsksNbForItsVersion() async throws {
        let nb = try FakeNB()
        #expect(await nb.model().nbVersion() == "0.1.214")
        #expect(nb.argvs == [["version"]])
    }
}
