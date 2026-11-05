import Foundation
import Testing
@testable import NanobrewKit

/// P-5 (D4, F5): nb's last summary line of cleanup and doctor becomes the result.
@Suite struct SummaryTests {
    static let dryRun = NBCommand.cleanupDryRun(pruneKegs: false)
    static let cleanup = NBCommand.cleanup(pruneKegs: false)

    func summary(_ command: NBCommand, _ line: String) -> CommandStatus.Summary? {
        CommandStatus.summary(of: command, line: line)
    }

    @Test func readsTheRecordedLines() throws {
        #expect(summary(Self.dryRun, try recorded("cleanup_--dry-run")[47]) == .init(kind: .success, phrase: "can free 41.4 MB"))
        #expect(summary(.doctor, try recorded("doctor")[4]) == .init(kind: .success, phrase: "no problems found"))
        #expect(summary(.doctor, try recorded("doctor-issues")[5]) == .init(kind: .attention, phrase: "found 2 problems"))
    }

    @Test func readsEachForm() {
        #expect(summary(Self.dryRun, "==> Nothing to clean up") == .init(kind: .success, phrase: "nothing to clean up"))
        #expect(summary(Self.cleanup, "==> Reclaimed 0.2 MB") == .init(kind: .success, phrase: "freed 0.2 MB"))
        #expect(summary(Self.cleanup, "==> Nothing to clean up") == .init(kind: .success, phrase: "nothing to clean up"))
        #expect(summary(.doctor, "==> Found 1 issue(s). Run `nb cleanup` to fix some of them.") == .init(kind: .attention, phrase: "found 1 problem"))
        #expect(summary(.doctor, "==> No issues found. Your nanobrew installation is healthy!") == .init(kind: .success, phrase: "no problems found"))
    }

    @Test func readsLinesWithAnsiCodes() {
        #expect(summary(Self.dryRun, "\u{1B}[1;34m==>\u{1B}[0m \u{1B}[1mWould reclaim 41.4 MB\u{1B}[0m") == .init(kind: .success, phrase: "can free 41.4 MB"))
        #expect(summary(.doctor, "\u{1B}[1m==> Found 2 issue(s).\u{1B}[0m Run `nb cleanup` to fix some of them.") == .init(kind: .attention, phrase: "found 2 problems"))
    }

    @Test func refusesOtherLinesAndCommands() {
        #expect(summary(.doctor, "==> Checking nanobrew installation...") == nil)
        #expect(summary(Self.dryRun, "    (run with --prune-kegs to also remove phantom DB entries flagged by `nb doctor`)") == nil)
        #expect(summary(Self.dryRun, "==> Reclaimed 0.2 MB") == nil, "a dry run never reclaims")
        #expect(summary(Self.cleanup, "==> Would reclaim 41.4 MB") == nil)
        #expect(summary(.doctorProbe(nil), "==> No issues found. Your nanobrew installation is healthy!") == nil)
        #expect(summary(.leaves(tree: false), "==> Nothing to clean up") == nil)
        #expect(summary(.doctor, "==> Found many issue(s).") == nil)
        #expect(summary(.doctor, "") == nil)
    }
}

@MainActor @Suite struct SummaryStatusTests {
    @Test func aDryRunSaysWhatItCanFree() async throws {
        let nb = try FakeNB()
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now)
        await model.run(.cleanupDryRun(pruneKegs: false)).value
        #expect(model.status?.text == "Dry run: can free 41.4 MB in 84 ms")
        #expect(model.status?.kind == .success)
    }

    @Test func aDoctorWithProblemsNeedsAttention() async throws {
        let nb = try FakeNB()
        try nb.output("doctor", recorded: "doctor-issues")
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now)
        await model.run(.doctor).value
        #expect(model.status?.text == "Doctor: found 2 problems in 84 ms")
        #expect(model.status?.kind == .attention)
    }

    @Test func aHealthyDoctorSaysSo() async throws {
        let nb = try FakeNB()
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now)
        await model.run(.doctor).value
        #expect(model.status?.text == "Doctor: no problems found in 84 ms")
        #expect(model.status?.kind == .success)
    }

    @Test func aProbeAFailedDoctorAndACancelledDryRunKeepTodaysTexts() async throws {
        let nb = try FakeNB()
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now)
        await model.run(.doctorProbe(nil)).value
        #expect(model.status?.text == "nb doctor --probe finished in 84 ms")
        try nb.exit("doctor", code: 1)
        await model.run(.doctor).value
        #expect(model.status?.text == "Failed: nb doctor (exit code 1)")
        try nb.wait("cleanup", seconds: 30)
        let dryRun = model.run(.cleanupDryRun(pruneKegs: false))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        model.cancel()
        await dryRun.value
        #expect(model.status?.text == "Cancelled: nb cleanup --dry-run")
    }
}
