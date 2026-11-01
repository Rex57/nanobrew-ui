import Foundation
import Testing
@testable import NanobrewKit

@MainActor @Suite struct ActionTests {
    @Test func catalogueGivesInstalledActions() {
        #expect(NBCommand.remove("jq") == NBCommand(args: ["remove", "jq"], changes: true, confirmation: .ask))
        #expect(NBCommand.removeCask("iterm2") == NBCommand(args: ["remove", "--cask", "iterm2"], changes: true, confirmation: .ask))
        #expect(NBCommand.pin("jq") == NBCommand(args: ["pin", "jq"], changes: true))
        #expect(NBCommand.unpin("jq") == NBCommand(args: ["unpin", "jq"], changes: true))
        #expect(NBCommand.link("jq") == NBCommand(args: ["link", "jq"], changes: true))
        #expect(NBCommand.unlink("jq") == NBCommand(args: ["unlink", "jq"], changes: true))
    }

    @Test func removeWaitsForConfirmation() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        #expect(model.request(.remove("jq")) == nil)
        #expect(model.pendingConfirmation == .remove("jq"))
        try await Task.sleep(for: .milliseconds(300))
        #expect(nb.argvs.isEmpty)
        await model.confirm()?.value
        #expect(model.pendingConfirmation == nil)
        #expect(nb.argvs == [["remove", "jq"]])
    }

    @Test func declinedConfirmationRunsNothing() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        model.request(.removeCask("iterm2"))
        model.decline()
        #expect(model.pendingConfirmation == nil)
        #expect(model.confirm() == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(nb.argvs.isEmpty)
    }

    @Test func commandWithoutConfirmationRunsAtOnce() async throws {
        let nb = try FakeNB()
        await nb.model().request(.pin("jq"))?.value
        #expect(nb.argvs == [["pin", "jq"]])
    }
}
