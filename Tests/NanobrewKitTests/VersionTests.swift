import Foundation
import Testing
@testable import NanobrewKit

@Suite struct VersionTests {
    @Test func snapshotGivesEarlierVersionsFromHistory() throws {
        let snapshot = try #require(try StateReader.read(path: fixture("state.json")))
        // From the history in Tests/Fixtures/state.json, newest first, with the install times.
        #expect(snapshot.earlierVersions(of: "libffi").map(\.version) == ["3.7.1", "3.6.0"])
        #expect(snapshot.earlierVersions(of: "node") == [
            HistoryEntry(version: "26.12.1_1", installedAt: 1_792_980_495),
            HistoryEntry(version: "26.12.0", installedAt: 1_792_483_964),
            HistoryEntry(version: "26.10.0_1", installedAt: 1_790_302_011),
            HistoryEntry(version: "26.9.0", installedAt: 1_790_042_677),
        ])
        #expect(snapshot.earlierVersions(of: "xcodegen").map(\.version) == ["2.45.4"])
        #expect(snapshot.earlierVersions(of: "bzip2") == [])
    }

    @Test func historyEntryOfTheInstalledVersionIsNotEarlier() throws {
        let json = #"{"kegs":[{"name":"a","version":"2","pinned":false,"installed_at":2}],"casks":[],"#
            + #""history":{"a":[{"version":"1","installed_at":1},{"version":"2","installed_at":2}]}}"#
        let path = try scratchDir().appendingPathComponent("state.json").path
        try json.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(try StateReader.read(path: path)?.earlierVersions(of: "a") == [HistoryEntry(version: "1", installedAt: 1)])
    }

    @Test func catalogueGivesRollbackAndSwitch() {
        #expect(NBCommand.rollback("jq") == NBCommand(args: ["rollback", "jq"], changes: true, confirmation: .ask))
        #expect(NBCommand.switchVersion("jq", to: "1.7.1") == NBCommand(args: ["switch", "jq@1.7.1"], changes: true))
    }
}
