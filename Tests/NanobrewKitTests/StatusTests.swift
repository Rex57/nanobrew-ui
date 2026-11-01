import Foundation
import Testing
@testable import NanobrewKit

/// A monotonic clock for tests: each reading is `step` later than the one before.
@MainActor final class StepClock {
    private var instant = ContinuousClock.now
    private let step: Duration
    init(_ step: Duration) { self.step = step }
    func now() -> ContinuousClock.Instant {
        defer { instant += step }
        return instant
    }
}

@MainActor @Suite struct StatusTests {
    func model(_ nb: FakeNB, step: Duration) -> AppModel {
        let clock = StepClock(step)
        return AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: clock.now)
    }

    @Test(arguments: [
        (Duration.milliseconds(84), "Installed jq in 84 ms"),
        (.milliseconds(840), "Installed jq in 0.84 s"),
        (.milliseconds(12_300), "Installed jq in 12.3 s"),
        (.seconds(65), "Installed jq in 1 m 05 s"),
    ])
    func aSuccessNamesWhatHappenedAndHowLongItTook(step: Duration, text: String) async throws {
        let nb = try FakeNB()
        let model = model(nb, step: step)
        await model.run(.install("jq")).value
        #expect(model.status?.text == text)
        #expect(model.status?.kind == .success)
    }

    @Test func aCommandWithoutItsOwnVerbFinishes() async throws {
        let nb = try FakeNB()
        let model = model(nb, step: .milliseconds(7))
        await model.run(.doctor).value
        #expect(model.status?.text == "nb doctor finished in 7 ms")
    }

    @Test func aFailureNamesTheCommandAndItsExitCode() async throws {
        let nb = try FakeNB()
        try nb.exit("upgrade", code: 1)
        let model = model(nb, step: .milliseconds(84))
        await model.run(.upgrade("node")).value
        #expect(model.status?.text == "Failed: nb upgrade node (exit code 1)")
        #expect(model.status?.kind == .failure)
    }

    @Test func aCancelNamesTheCommand() async throws {
        let nb = try FakeNB()
        try nb.wait("install", seconds: 30)
        let model = model(nb, step: .milliseconds(84))
        let task = model.run(.install("jq"))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        #expect(model.status?.kind == .running)
        model.cancel()
        await task.value
        #expect(model.status?.text == "Cancelled: nb install jq")
        #expect(model.status?.kind == .cancelled)
    }

    @Test func theLaunchCheckCountsThePackages() async throws {
        // state.json: 7 formulae and 3 casks.
        let nb = try FakeNB()
        let model = model(nb, step: .milliseconds(7))
        model.reload()
        await model.checkOutdated(report: true)
        #expect(model.status?.text == "Checked 10 packages in 7 ms")
    }
}

@MainActor @Suite struct ConsoleStateTests {
    @Test func closedAtStartOpenWhileACommandRunsClosedAfter() async throws {
        let nb = try FakeNB()
        try nb.wait("install", seconds: 1)
        let model = nb.model()
        #expect(!model.consoleShown)
        let task = model.run(.install("jq"))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        #expect(model.consoleShown)
        await task.value
        #expect(!model.consoleShown)
    }

    @Test func staysOpenWhenPinned() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        model.consolePinned = true
        await model.run(.install("jq")).value
        #expect(model.consoleShown)
    }

    @Test func theToggleFlipsIt() {
        let model = AppModel(statePath: fixture("state.json"), nbPath: nil)
        model.toggleConsole()
        #expect(model.consoleShown)
        model.toggleConsole()
        #expect(!model.consoleShown)
    }
}
