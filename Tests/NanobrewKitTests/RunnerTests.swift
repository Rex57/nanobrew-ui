import Foundation
import Testing
@testable import NanobrewKit

@MainActor @Suite struct RunnerTests {
    @Test func catalogueHasDoctorAsReadOnly() {
        #expect(NBCommand.doctor.args == ["doctor"])
        #expect(!NBCommand.doctor.changes)
        #expect(NBCommand.doctor.confirmation == .none)
    }

    @Test func anArgumentWithSpacesQuotesAndSemicolonStaysOneArgument() async throws {
        let nb = try FakeNB()
        let odd = #"a b "c" 'd'; rm -rf x"#
        await nb.model().run(NBCommand(args: ["info", odd], changes: false)).value
        #expect(nb.argvs == [["info", odd]])
    }

    @Test func changingCommandsRunOneAfterTheOtherAndReadOnlyRunsAtOnce() async throws {
        let nb = try FakeNB()
        try nb.wait("pin", seconds: 1)
        let model = nb.model()
        let first = model.run(NBCommand(args: ["pin", "a"], changes: true))
        let second = model.run(NBCommand(args: ["pin", "b"], changes: true))
        await eventually { nb.argvs.count == 1 }
        let doctor = model.run(.doctor)
        await doctor.value
        await first.value
        await second.value
        let events = nb.log.filter { $0.first != "CHILD" }.map { $0.joined(separator: " ") }
        #expect(events == ["START pin a", "START doctor", "END doctor", "END pin a", "START pin b", "END pin b"])
    }

    @Test func cancelStopsTheProcessGroupAndTheNextQueuedCommandRuns() async throws {
        let nb = try FakeNB()
        try nb.wait("link", seconds: 30)
        let model = nb.model()
        let first = model.run(NBCommand(args: ["link", "a"], changes: true))
        let second = model.run(NBCommand(args: ["unlink", "a"], changes: true))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        let child = try #require(nb.log.first { $0.first == "CHILD" }.flatMap { Int32($0[1]) })
        model.cancel()
        await first.value
        await second.value
        #expect(kill(child, 0) != 0, "the sleep child must be gone")
        #expect(model.console.contains("Cancelled: nb link a"))
        #expect(nb.argvs == [["link", "a"], ["unlink", "a"]])
        #expect(!nb.log.contains(["END", "link", "a"]))
    }

    @Test func consoleLinesHaveNoAnsiCodes() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        await model.run(NBCommand(args: ["install", "sl"], changes: true)).value
        #expect(model.console.contains("    ✓ sl"))
        #expect(!model.console.contains { $0.contains("\u{1B}") })
    }

    @Test func nonZeroExitIsReportedAsFailureWithItsCode() async throws {
        let nb = try FakeNB()
        try nb.exit("doctor", code: 3)
        let model = nb.model()
        await model.run(.doctor).value
        #expect(model.console.last == "Failed: nb doctor (exit code 3)")
    }

    @Test func snapshotIsReadAgainAfterACommand() async throws {
        let nb = try FakeNB()
        try nb.wait("pin", seconds: 1)
        let state = nb.dir.appendingPathComponent("state.json").path
        try FileManager.default.copyItem(atPath: fixture("state-empty.json"), toPath: state)
        let model = nb.model(statePath: state)
        model.reload()
        #expect(model.snapshot?.formulae.count == 0)
        let task = model.run(NBCommand(args: ["pin", "a"], changes: true))
        await eventually { !nb.argvs.isEmpty }
        try FileManager.default.removeItem(atPath: state)
        try FileManager.default.copyItem(atPath: fixture("state.json"), toPath: state)
        await task.value
        #expect(model.snapshot?.formulae.count == 7)
    }

    @Test func askBeforeQuitWhileAChangingCommandRunsOrWaits() async throws {
        let nb = try FakeNB()
        try nb.wait("pin", seconds: 1)
        let model = nb.model()
        #expect(!model.askBeforeQuit)
        let doctor = model.run(.doctor)
        #expect(!model.askBeforeQuit)
        await doctor.value
        let first = model.run(NBCommand(args: ["pin", "a"], changes: true))
        let second = model.run(NBCommand(args: ["pin", "b"], changes: true))
        #expect(model.askBeforeQuit)
        await first.value
        #expect(model.askBeforeQuit)
        await second.value
        #expect(!model.askBeforeQuit)
    }
}
