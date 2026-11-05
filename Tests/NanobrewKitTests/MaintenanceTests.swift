import Foundation
import Testing
@testable import NanobrewKit

@Suite struct MaintenanceTests {
    @Test func catalogueGivesMaintenanceCommands() {
        #expect(NBCommand.doctorProbe(nil) == NBCommand(args: ["doctor", "--probe"], changes: true))
        #expect(NBCommand.doctorProbe("jq") == NBCommand(args: ["doctor", "--probe", "jq"], changes: true))
        #expect(NBCommand.cleanupDryRun(pruneKegs: false) == NBCommand(args: ["cleanup", "--dry-run"], changes: false))
        #expect(NBCommand.cleanupDryRun(pruneKegs: true) == NBCommand(args: ["cleanup", "--dry-run", "--prune-kegs"], changes: false))
        #expect(NBCommand.cleanup(pruneKegs: false) == NBCommand(args: ["cleanup"], changes: true, confirmation: .ask))
        #expect(NBCommand.cleanup(pruneKegs: true) == NBCommand(args: ["cleanup", "--prune-kegs"], changes: true, confirmation: .ask))
        #expect(NBCommand.update == NBCommand(args: ["update"], changes: true))
        #expect(NBCommand.updateRegistry == NBCommand(args: ["update-registry"], changes: true))
        #expect(NBCommand.autoupdateStatus == NBCommand(args: ["autoupdate", "status"], changes: false))
        #expect(NBCommand.autoupdate(.enable, upgrade: false) == NBCommand(args: ["autoupdate", "enable"], changes: true))
        #expect(NBCommand.autoupdate(.enable, upgrade: true) == NBCommand(args: ["autoupdate", "enable", "--upgrade"], changes: true))
        #expect(NBCommand.autoupdate(.disable, upgrade: false) == NBCommand(args: ["autoupdate", "disable"], changes: true))
        #expect(NBCommand.autoupdate(.run, upgrade: true) == NBCommand(args: ["autoupdate", "run", "--upgrade"], changes: true))
        #expect(NBCommand.where("jq") == NBCommand(args: ["where", "jq"], changes: false))
        #expect(NBCommand.leaves(tree: false) == NBCommand(args: ["leaves"], changes: false))
        #expect(NBCommand.leaves(tree: true) == NBCommand(args: ["leaves", "--tree"], changes: false))
    }

    @Test func parsesAutoupdateStatus() throws {
        #expect(AutoupdateStatus.parse(try recorded("autoupdate_status")) == AutoupdateStatus(installed: false, enabled: false))
        // Wording from nanobrew main.zig:3698-3700.
        #expect(AutoupdateStatus.parse(["==> Auto-update is installed, enabled"]) == AutoupdateStatus(installed: true, enabled: true))
        #expect(AutoupdateStatus.parse(["==> Auto-update is installed, not enabled"]) == AutoupdateStatus(installed: true, enabled: false))
        #expect(AutoupdateStatus.parse(["nb: autoupdate status failed: X"]) == nil)
    }

    @MainActor @Test func whereOutputHasNoAnsiInTheConsole() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.run(.where("jq")).value
        #expect(model.console.contains("==> installed matching \"jq\":"))
        #expect(!model.console.contains { $0.contains("\u{1B}") })
    }
}

@MainActor @Suite struct LastRunTests {
    @Test func onlyAnExitZeroCountsAsSucceeded() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        let dryRun = NBCommand.cleanupDryRun(pruneKegs: false)
        #expect(!model.lastRunSucceeded(dryRun))
        await model.run(dryRun).value
        #expect(model.lastRunSucceeded(dryRun))
        try nb.exit("cleanup", code: 1)
        await model.run(dryRun).value
        #expect(!model.lastRunSucceeded(dryRun))
    }

    @Test func aCancelledRunDidNotSucceed() async throws {
        let nb = try FakeNB()
        try nb.wait("cleanup", seconds: 30)
        let model = nb.model()
        let dryRun = NBCommand.cleanupDryRun(pruneKegs: false)
        let task = model.run(dryRun)
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        model.cancel()
        await task.value
        #expect(!model.lastRunSucceeded(dryRun))
    }
}

/// D8: Clean Up only after a successful dry run with the same --prune-kegs setting.
@MainActor @Suite struct CleanupRuleTests {
    @Test func cleanUpIsAllowedOnlyAfterAGoodDryRunWithTheSameSetting() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        #expect(!model.canCleanUp(pruneKegs: false), "no dry run yet")
        await model.dryRunCleanup(pruneKegs: false).value
        #expect(model.canCleanUp(pruneKegs: false))
        #expect(!model.canCleanUp(pruneKegs: true), "the dry run had the other setting")
        // Clean Up uses the dry run up: the next one needs a new dry run.
        model.cleanUp(pruneKegs: false)
        #expect(model.pendingConfirmation == .cleanup(pruneKegs: false))
        #expect(!model.canCleanUp(pruneKegs: false))
    }

    @Test func aFailedDryRunAllowsNoCleanUp() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.dryRunCleanup(pruneKegs: true).value
        #expect(model.canCleanUp(pruneKegs: true))
        try nb.exit("cleanup", code: 1)
        await model.dryRunCleanup(pruneKegs: true).value
        #expect(!model.canCleanUp(pruneKegs: true), "a failed dry run also ends the earlier good one")
    }

    @Test func aCancelledDryRunAllowsNoCleanUp() async throws {
        let nb = try FakeNB()
        try nb.wait("cleanup", seconds: 30)
        let model = nb.model()
        let task = model.dryRunCleanup(pruneKegs: false)
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        model.cancel()
        await task.value
        #expect(!model.canCleanUp(pruneKegs: false))
    }

    @Test func aSwitchChangeDuringTheDryRunAllowsCleanUpOnlyWithTheSettingItRan() async throws {
        let nb = try FakeNB()
        try nb.wait("cleanup", seconds: 1)
        let model = nb.model()
        // The switch moves to on while the dry run without --prune-kegs runs.
        await model.dryRunCleanup(pruneKegs: false).value
        #expect(!model.canCleanUp(pruneKegs: true))
        #expect(model.canCleanUp(pruneKegs: false))
    }
}
