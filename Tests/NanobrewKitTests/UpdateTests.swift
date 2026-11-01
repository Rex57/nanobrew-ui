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

    @Test func catalogueGivesOutdatedAndUpgrade() {
        #expect(NBCommand.outdated == NBCommand(args: ["outdated"], changes: false))
        #expect(NBCommand.outdatedCasks == NBCommand(args: ["outdated", "--cask"], changes: false))
        #expect(NBCommand.upgrade("node") == NBCommand(args: ["upgrade", "node"], changes: true))
        #expect(NBCommand.upgradeCask("puremac") == NBCommand(args: ["upgrade", "--cask", "puremac"], changes: true))
        #expect(NBCommand.upgradeAll == NBCommand(args: ["upgrade"], changes: true))
        #expect(NBCommand.upgradeAllCasks == NBCommand(args: ["upgrade", "--cask"], changes: true))
    }
}

@MainActor @Suite struct UpdatesModelTests {
    @Test func outdatedListsFormulaeFromOutdatedAndCasksFromOutdatedCask() async throws {
        let nb = try FakeNB()
        let rows = await nb.model().outdated()
        #expect(rows.map(\.name) == ["node", "libffi", "puremac", "nanobrew-ui"])
        #expect(Set(nb.argvs) == [["outdated"], ["outdated", "--cask"]])
    }

    /// The state file says nanobrew-ui 1.0.1 once the upgrade is done; the app runs 1.0.0.
    func selfUpgradeModel(_ nb: FakeNB) throws -> AppModel {
        let state = nb.dir.appendingPathComponent("state.json").path
        try FileManager.default.copyItem(atPath: fixture("state-self-upgraded.json"), toPath: state)
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
        await model.run(.upgradeAllCasks).value
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
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, appVersion: "1.0.0")
        await model.run(.upgradeCask("nanobrew-ui")).value
        #expect(!model.restartOffered)
    }
}
