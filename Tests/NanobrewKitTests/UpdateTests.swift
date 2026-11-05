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
        #expect(Set(nb.allArgvs) == [["outdated"], ["outdated", "--cask"]])
    }

    @Test func onlyAChangingCommandChecksOutdatedAfterIt() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        for command in [NBCommand.doctor, .where("jq"), .leaves(tree: false), .cleanupDryRun(pruneKegs: false)] {
            await model.run(command).value
        }
        #expect(model.commandsEnded == 4, "the signal changes once per ended read-only command")
        try nb.exit("pin", code: 1)
        await model.run(.pin("a")).value
        await model.run(.unpin("a")).value
        #expect(model.commandsEnded == 6, "and once per ended changing command, failed or not")
        // The unpin's check replaces the pin's: the pin's nb runs still end by themselves, and their result is
        // dropped. So exactly two pairs run, and none for the four read-only commands before them.
        let ends = { nb.log.filter { $0.first == "END" && $0[1] == "outdated" }.count }
        await eventually { model.outdatedChecked && ends() == 4 }
        let checks = nb.allArgvs.filter { $0.first == "outdated" }
        #expect(checks.filter { $0 == ["outdated"] }.count == 2)
        #expect(checks.filter { $0 == ["outdated", "--cask"] }.count == 2)
        #expect(ends() == 4)
    }

    @Test func aChangingCommandStartsExactlyOneOutdatedCheck() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.run(.pin("a")).value
        await eventually { model.outdatedChecked }
        #expect(model.updatesCount == 4)
        #expect(nb.allArgvs.filter { $0.first == "outdated" }.sorted { $0.count < $1.count } == [["outdated"], ["outdated", "--cask"]])
    }

    @Test func comingToTheFrontReadsStateAndChecksOutdated() async throws {
        let nb = try FakeNB()
        let state = nb.dir.appendingPathComponent("state.json").path
        try FileManager.default.copyItem(atPath: fixture("state-empty.json"), toPath: state)
        let model = nb.model(statePath: state)
        model.reload()
        try FileManager.default.removeItem(atPath: state)
        try FileManager.default.copyItem(atPath: fixture("state.json"), toPath: state)
        // Twice in a row: the second check replaces the first.
        model.becameActive()
        model.becameActive()
        #expect(model.snapshot?.formulae.count == 7)
        await eventually { model.outdatedChecked }
        #expect(model.updatesCount == 4)
        #expect(model.commandsEnded == 0, "no command ended")
    }

    func pairs(_ nb: FakeNB) -> Int { nb.allArgvs.filter { $0 == ["outdated", "--cask"] }.count }
    func allEnded(_ nb: FakeNB) -> Bool {
        nb.log.filter { $0.first == "END" && $0[1] == "outdated" }.count == nb.allArgvs.filter { $0.first == "outdated" }.count
    }

    @Test func launchWithAnActivationAtOnceStartsOneCheck() async throws {
        let nb = try FakeNB()
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(81)).now)
        // The window's first task and the app's first activation come together at launch.
        model.becameActive()
        model.becameActive()
        await eventually { model.outdatedChecked && allEnded(nb) }
        #expect(nb.allArgvs.filter { $0.first == "outdated" }.sorted { $0.count < $1.count } == [["outdated"], ["outdated", "--cask"]])
        #expect(model.status?.text == "Checked 10 packages in 81 ms", "the launch check keeps its status line")
        // An activation after that check ended starts one more pair.
        model.becameActive()
        await eventually { pairs(nb) == 2 && allEnded(nb) }
        #expect(nb.allArgvs.filter { $0 == ["outdated"] }.count == 2)
        #expect(pairs(nb) == 2)
    }

    @Test func refreshesAndAnActivationDuringACheckShareIt() async throws {
        let nb = try FakeNB()
        try nb.wait("outdated", seconds: 3)
        let model = nb.model()
        let first = Task { await model.refresh() }
        await eventually { pairs(nb) == 1 }
        let second = Task { await model.refresh() }
        let third = Task { await model.refresh() }
        model.becameActive()
        for task in [first, second, third] {
            await task.value
            #expect(model.updatesCount == 4, "every caller sees the one check's result")
        }
        #expect(nb.allArgvs.filter { $0.first == "outdated" }.sorted { $0.count < $1.count } == [["outdated"], ["outdated", "--cask"]])
    }

    @Test func aRefreshThatJoinedACheckReportsIt() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.checkOutdated()
        try nb.wait("outdated", seconds: 3)
        model.becameActive()  // not the session's first check: it reports nothing itself
        await eventually { pairs(nb) == 2 }
        #expect(model.status == nil)
        await model.refresh()
        #expect(pairs(nb) == 2, "the refresh joined the running check")
        #expect(model.status?.text.hasPrefix("Checked 10 packages in ") == true)
        // After the joined check ended, the next refresh starts its own.
        await model.refresh()
        #expect(pairs(nb) == 3)
    }

    @Test func aChangingCommandDuringAnActivationCheckGetsItsOwnCheck() async throws {
        let nb = try FakeNB()
        try nb.wait("outdated", seconds: 1)
        let model = nb.model()
        model.becameActive()
        await eventually { pairs(nb) == 1 }
        await model.run(.pin("a")).value
        await eventually { pairs(nb) == 2 && allEnded(nb) && model.outdatedChecked }
        #expect(pairs(nb) == 2)
        #expect(nb.allArgvs.filter { $0 == ["outdated"] }.count == 2)
    }

    @Test func aCancelledOutdatedCheckKeepsThePreviousList() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.checkOutdated()
        #expect(model.updatesCount == 4)
        try nb.wait("outdated", seconds: 30)
        let task = Task { await model.checkOutdated() }
        await eventually { nb.log.filter { $0.first == "CHILD" }.count == 2 }
        task.cancel()
        await task.value
        nb.killChildren()
        #expect(model.outdatedPackages.map(\.name) == ["node", "libffi", "puremac", "nanobrew-ui"])
        #expect(model.updatesCount == 4)
        #expect(model.outdatedError == nil)
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

    @Test func noRestartOfferAfterACancel() async throws {
        let nb = try FakeNB()
        try nb.wait("upgrade", seconds: 30)
        let model = try selfUpgradeModel(nb)
        let task = model.run(.upgradeCask("nanobrew-ui"))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        model.cancel()
        await task.value
        #expect(model.status?.kind == .cancelled)
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

/// D7: Restart asks the quit question first and opens the new copy only after a yes.
@MainActor @Suite struct RestartTests {
    struct OpenFailed: Error, LocalizedError { var errorDescription: String? { "open exited with code 1" } }

    @Test func keepRunningOpensNoSecondCopy() {
        let model = AppModel(statePath: fixture("state.json"), nbPath: nil)
        var steps: [String] = []
        model.restart(mayQuit: { steps.append("ask"); return false }, open: { steps.append("open") }, quit: { steps.append("quit") })
        #expect(steps == ["ask"])
    }

    @Test func aYesOpensTheNewCopyThenQuits() {
        let model = AppModel(statePath: fixture("state.json"), nbPath: nil)
        var steps: [String] = []
        model.restart(mayQuit: { steps.append("ask"); return true }, open: { steps.append("open") }, quit: { steps.append("quit") })
        #expect(steps == ["ask", "open", "quit"])
    }

    @Test func aFailedOpenShowsAFailureAndTheAppKeepsRunning() {
        let model = AppModel(statePath: fixture("state.json"), nbPath: nil)
        var quit = false
        model.restart(mayQuit: { true }, open: { throw OpenFailed() }, quit: { quit = true })
        #expect(!quit)
        #expect(model.status?.kind == .failure)
        #expect(model.status?.text == "Restart failed: the new copy did not open (open exited with code 1)")
    }
}
