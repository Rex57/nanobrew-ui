import Foundation
import Testing
@testable import NanobrewKit

@Suite struct MaintenanceTests {
    @Test func catalogueGivesMaintenanceCommands() {
        #expect(NBCommand.doctorProbe(nil) == NBCommand(args: ["doctor", "--probe"], changes: true))
        #expect(NBCommand.doctorProbe("jq") == NBCommand(args: ["doctor", "--probe", "jq"], changes: true))
        #expect(NBCommand.cleanupDryRun == NBCommand(args: ["cleanup", "--dry-run"], changes: false))
        #expect(NBCommand.cleanup == NBCommand(args: ["cleanup"], changes: true, confirmation: .ask))
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
