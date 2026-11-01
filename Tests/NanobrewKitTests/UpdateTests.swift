import Foundation
import Testing
@testable import NanobrewKit

@Suite struct OutdatedParserTests {
    @Test func parsesRowsWithCaskAndPinnedTags() throws {
        // Fixture built from the row format in nanobrew main.zig:5759-5765.
        #expect(OutdatedPackage.parse(try recorded("outdated")) == [
            OutdatedPackage(name: "node", installed: "26.13.0_2", latest: "26.14.0", isCask: false, pinned: false),
            OutdatedPackage(name: "libffi", installed: "3.8.0", latest: "3.9.0", isCask: false, pinned: true),
            OutdatedPackage(name: "puremac", installed: "3.2.0", latest: "3.3.0", isCask: true, pinned: false),
        ])
    }

    @Test func upToDateGivesAnEmptyList() throws {
        #expect(OutdatedPackage.parse(try recorded("outdated-live")).isEmpty)
        #expect(OutdatedPackage.parse(try recorded("outdated-cask-live")).isEmpty)
    }

    @Test func aTapCaskRowHasItsFullName() {
        // nb prints the canonical token (nanobrew main.zig:5759-5763).
        #expect(OutdatedPackage.parse(["Rex57/tap/nanobrew-ui (1.0.0 -> 1.0.1) (cask)"]).map(\.name) == ["Rex57/tap/nanobrew-ui"])
    }

    @Test func catalogueGivesOutdatedAndUpgrade() {
        #expect(NBCommand.outdated == NBCommand(args: ["outdated"], changes: false))
        #expect(NBCommand.outdatedCasks == NBCommand(args: ["outdated", "--cask"], changes: false))
        #expect(NBCommand.upgrade("node") == NBCommand(args: ["upgrade", "node"], changes: true))
        #expect(NBCommand.upgradeCask("puremac") == NBCommand(args: ["upgrade", "--cask", "puremac"], changes: true))
        #expect(NBCommand.upgradeAll == NBCommand(args: ["upgrade"], changes: true))
    }
}

@MainActor @Suite struct UpdatesModelTests {
    @Test func outdatedListsFormulaeFromOutdatedAndCasksFromOutdatedCask() async throws {
        let nb = try FakeNB()
        let rows = try await nb.model().outdated()
        #expect(rows.map(\.name) == ["node", "libffi", "puremac", "nanobrew-ui"])
        #expect(Set(nb.argvs) == [["outdated"], ["outdated", "--cask"]])
    }

    /// Copies `name` (default: nanobrew-ui 1.0.1) as state.json; the app runs 1.0.0.
    func selfUpgradeModel(_ nb: FakeNB, state name: String = "state-self-upgraded.json") throws -> AppModel {
        let state = nb.dir.appendingPathComponent("state.json").path
        try FileManager.default.copyItem(atPath: fixture(name), toPath: state)
        let model = AppModel(statePath: state, nbPath: nb.path, appVersion: "1.0.0")
        model.reload()
        return model
    }

    @Test func restartOfferAfterASuccessfulSelfUpgrade() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb)
        #expect(!model.restartOffered)
        await model.run(.upgradeCask("nanobrew-ui")).value
        #expect(model.restartOffered)
    }

    @Test func restartOfferAfterASuccessfulUpgradeAll() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb)
        // Upgrade All Casks as the app sends it: the ready casks by name.
        let rows = try await model.outdated()
        let command = try #require(model.upgradeAllCasks(rows))
        #expect(command == NBCommand(args: ["upgrade", "--cask", "puremac", "nanobrew-ui"], changes: true))
        await model.run(command).value
        #expect(model.restartOffered)
    }

    @Test func noRestartOfferAfterAFailure() async throws {
        let nb = try FakeNB()
        try nb.exit("upgrade", code: 1)
        let model = try selfUpgradeModel(nb)
        await model.run(.upgradeCask("nanobrew-ui")).value
        #expect(!model.restartOffered)
    }

    @Test func noRestartOfferForOtherPackages() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb)
        await model.run(.upgradeCask("puremac")).value
        #expect(!model.restartOffered)
    }

    @Test func noRestartOfferWhenTheVersionDidNotChange() async throws {
        let nb = try FakeNB()
        // state.json still holds nanobrew-ui 1.0.0, the version of the running app.
        let model = AppModel(statePath: fixture("state-self-current.json"), nbPath: nb.path, appVersion: "1.0.0")
        model.reload()
        await model.run(.upgradeCask("nanobrew-ui")).value
        #expect(!model.restartOffered)
    }

    // A tap install: nb records the cask as Rex57/tap/nanobrew-ui (token and canonical_token).
    let tapToken = "Rex57/tap/nanobrew-ui"
    let tapRows = [OutdatedPackage(name: "puremac", installed: "3.2.0", latest: "3.3.0", isCask: true, pinned: false),
                   OutdatedPackage(name: "Rex57/tap/nanobrew-ui", installed: "1.0.0", latest: "1.0.1", isCask: true,
                                   pinned: false)]

    @Test func restartOfferAfterASuccessfulTapSelfUpgrade() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb, state: "state-self-tap-upgraded.json")
        await model.run(.upgradeCask(tapToken)).value
        #expect(model.restartOffered)
    }

    @Test func restartOfferAfterUpgradeAllCasksWithTheTapCask() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb, state: "state-self-tap-upgraded.json")
        let command = try #require(model.upgradeAllCasks(tapRows))
        #expect(command == NBCommand(args: ["upgrade", "--cask", "puremac", tapToken], changes: true))
        await model.run(command).value
        #expect(model.restartOffered)
    }

    @Test func noRestartOfferForTheTapCaskWhenTheVersionDidNotChange() async throws {
        let nb = try FakeNB()
        let model = try selfUpgradeModel(nb, state: "state-self-tap-current.json")
        await model.run(try #require(model.upgradeAllCasks(tapRows))).value
        #expect(!model.restartOffered)
    }

    func cask(_ token: String, _ version: String, app: String = "Nanobrew UI.app") -> [String: Any] {
        ["token": token, "canonical_token": token, "version": version, "sha256": "x", "probe_success": true,
         "probed_at": 0, "probe_schema": 3, "probe_platform": 1, "apps": [app], "binaries": [String]()]
    }

    /// state-self-tap-upgraded.json with its nanobrew-ui casks replaced by `selfCasks`; the app runs 1.0.0.
    func model(_ nb: FakeNB, _ selfCasks: [[String: Any]]) throws -> AppModel {
        let data = try Data(contentsOf: URL(fileURLWithPath: fixture("state-self-tap-upgraded.json")))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let casks = try #require(json["casks"] as? [[String: Any]])
        json["casks"] = casks.filter { !(($0["token"] as? String) ?? "").hasSuffix("nanobrew-ui") } + selfCasks
        let state = nb.dir.appendingPathComponent("state.json")
        try JSONSerialization.data(withJSONObject: json).write(to: state)
        let model = AppModel(statePath: state.path, nbPath: nb.path, appVersion: "1.0.0")
        model.reload()
        return model
    }

    @Test func restartOfferWhenAnEarlierShortNameRecordStillHoldsTheRunningVersion() async throws {
        let nb = try FakeNB()
        let model = try model(nb, [cask("nanobrew-ui", "1.0.0"), cask(tapToken, "1.0.1")])
        await model.run(.upgradeCask(tapToken)).value
        #expect(model.restartOffered)
    }

    @Test func restartOfferWhenAnotherTapRecordComesFirst() async throws {
        let nb = try FakeNB()
        let model = try model(nb, [cask("alice/tap/nanobrew-ui", "1.0.0", app: "Alice.app"), cask(tapToken, "1.0.1")])
        await model.run(.upgradeCask(tapToken)).value
        #expect(model.restartOffered)
    }

    @Test func failedOutdatedThrowsNbErrorText() async throws {
        let nb = try FakeNB()
        try nb.exit("outdated", code: 1)
        try nb.stderr("outdated", text: "nb: could not open database\n")
        await #expect(throws: AppModel.CommandFailed(text: "nb: could not open database")) { try await nb.model().outdated() }
    }
}
