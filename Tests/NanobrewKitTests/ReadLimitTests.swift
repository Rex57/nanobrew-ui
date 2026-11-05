import Foundation
import Testing
@testable import NanobrewKit

/// P-1 (D5): the app's background nb reads end when their caller stops waiting, give up after the read limit,
/// and end at quit; console commands get neither rule.
@MainActor @Suite struct ReadLimitTests {
    static let oneSecondTimeout = AppModel.CommandFailed(
        text: "nb did not answer in 1 s. Another nb command may be running, or the network does not answer.")

    /// Waits for the first sleeping run, cancels `task`, and expects no process of that run alive within 6 s.
    func expectCancelEndsTheRun<T>(_ nb: FakeNB, _ task: Task<T, any Error>) async throws {
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        let group = try #require(nb.firstSleeperGroup())
        let start = ContinuousClock.now
        task.cancel()
        _ = try? await task.value
        await eventually { kill(-group, 0) != 0 }
        #expect(kill(-group, 0) != 0, "no process of the cancelled run is alive")
        #expect(ContinuousClock.now - start < .seconds(6))
    }

    @Test func aCancelledServicesReadEndsItsRun() async throws {
        let nb = try FakeNB()
        try nb.wait("services", seconds: 30)
        let model = nb.model()
        try await expectCancelEndsTheRun(nb, Task { try await model.services() })
    }

    @Test func aCancelledDetailFetchEndsItsRun() async throws {
        let nb = try FakeNB()
        try nb.wait("info", seconds: 30)
        let model = nb.model()
        try await expectCancelEndsTheRun(nb, Task { await model.detail(name: "node", cask: false) })
    }

    @Test func aCancelledSearchEndsItsRun() async throws {
        let nb = try FakeNB()
        try nb.wait("search", seconds: 30)
        let model = nb.model()
        try await expectCancelEndsTheRun(nb, Task { try await model.search("sl") })
    }

    @Test func aHangingReadFailsWithTheTimeoutTextAfterTheLimit() async throws {
        let nb = try FakeNB()
        try nb.wait("services", seconds: 30)
        let model = nb.model(readLimit: .seconds(1))
        let start = ContinuousClock.now
        await #expect(throws: Self.oneSecondTimeout) { try await model.services() }
        let took = ContinuousClock.now - start
        #expect(took >= .seconds(1) && took < .seconds(7), "past the 1 s window, well before the 30 s sleep: \(took)")
        let group = try #require(nb.firstSleeperGroup())
        await eventually { kill(-group, 0) != 0 }
        #expect(kill(-group, 0) != 0)
    }

    @Test func aReadInsideTheLimitReturnsItsRows() async throws {
        let nb = try FakeNB()
        #expect(try await nb.model(readLimit: .seconds(1)).services().map(\.name) == ["postgresql@17", "redis"])
    }

    @Test func aHangingReadThatIgnoresSigtermIsKilledAndTimesOut() async throws {
        let nb = try FakeNB()
        try nb.wait("services", seconds: 30)
        try nb.ignoreTerm("services")
        let model = nb.model(readLimit: .seconds(1))
        let start = ContinuousClock.now
        await #expect(throws: Self.oneSecondTimeout) { try await model.services() }
        let took = ContinuousClock.now - start
        #expect(took >= .seconds(6) && took < .seconds(8), "1 s limit, then SIGKILL 5 s after SIGTERM: \(took)")
        let child = try #require(nb.log.first { $0.first == "CHILD" }.flatMap { Int32($0[1]) })
        await eventually { kill(child, 0) != 0 }
        #expect(kill(child, 0) != 0)
    }

    @Test func aBundleDumpPastTheLimitWritesNoFile() async throws {
        let nb = try FakeNB()
        try nb.wait("bundle", seconds: 30)
        let file = nb.dir.appendingPathComponent("Nanobrew")
        await #expect(throws: Self.oneSecondTimeout) { try await nb.model(readLimit: .seconds(1)).bundleDump(to: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theQuitCallEndsBackgroundReadsAndLeavesConsoleCommandsAlone() async throws {
        let nb = try FakeNB()
        try nb.wait("services", seconds: 30)
        try nb.wait("install", seconds: 5)
        let model = nb.model()
        let read = Task { try await model.services() }
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        let group = try #require(nb.firstSleeperGroup())
        let install = model.run(.install("sl"))
        let pin = model.run(.pin("jq"))
        await eventually { nb.log.filter { $0.first == "CHILD" }.count == 2 }
        model.endBackgroundReads()
        await #expect(throws: AppModel.CommandFailed.self) { try await read.value }
        await eventually { kill(-group, 0) != 0 }
        #expect(kill(-group, 0) != 0, "the services run is ended")
        await install.value
        await pin.value
        #expect(model.console.contains("Done: nb install sl"))
        #expect(model.console.contains("Done: nb pin jq"))
        #expect(nb.log.contains(["END", "install", "sl"]))
    }

    /// F3: the limit in whole seconds.
    @Test func theDefaultTimeoutTextSays60Seconds() {
        #expect(AppModel(statePath: fixture("state.json"), nbPath: nil).readTimeoutText
                == "nb did not answer in 60 s. Another nb command may be running, or the network does not answer.")
    }

    /// F2: the limit fires on time, not seconds late.
    @Test func aHangingReadFailsOnTime() async throws {
        let nb = try FakeNB()
        try nb.wait("services", seconds: 30)
        let model = nb.model(readLimit: .seconds(2))
        let start = ContinuousClock.now
        await #expect(throws: AppModel.CommandFailed.self) { try await model.services() }
        let took = ContinuousClock.now - start
        // 3 s: the SIGTERM, exit and reap of the fake nb run slow under the parallel suites (facts file trap).
        #expect(took >= .seconds(2) && took < .seconds(3), "\(took)")
    }

    /// F1: time while the app's own changing command runs does not count (nb's lock holds the read behind it).
    @Test func aReadDuringTheAppsOwnCommandIsNotEndedByTheLimit() async throws {
        let nb = try FakeNB()
        try nb.wait("install", seconds: 4)
        try nb.wait("info", seconds: 3)
        let model = nb.model(readLimit: .seconds(1))
        let install = model.run(.install("sl"))
        await eventually { model.running != nil }
        let detail = await model.detail(name: "node", cask: false)
        #expect(model.running != nil, "the install still runs: the read ran past the 1 s window during it")
        #expect(detail.error == nil)
        #expect(detail.info != nil)
        await install.value
    }

    @Test func aReadThatStillHangsAfterTheCommandEndsTimesOutAfterTheLimit() async throws {
        let nb = try FakeNB()
        try nb.wait("install", seconds: 3)
        try nb.wait("info", seconds: 30)
        let model = nb.model(readLimit: .seconds(1))
        let install = model.run(.install("sl"))
        await eventually { model.running != nil }
        let detail = Task { await model.detail(name: "node", cask: false) }
        await install.value
        let ended = ContinuousClock.now
        #expect(await detail.value.error == Self.oneSecondTimeout.text)
        let took = ContinuousClock.now - ended
        #expect(took < .milliseconds(1600), "about the limit after the install's end: \(took)")
    }

    @Test func theDefaultReadLimitIs60Seconds() {
        #expect(AppModel(statePath: fixture("state.json"), nbPath: nil).readLimit == .seconds(60))
    }

    @Test func aConsoleCommandHasNoReadLimit() async throws {
        let nb = try FakeNB()
        try nb.wait("doctor", seconds: 3)
        let model = nb.model(readLimit: .seconds(1))
        await model.run(.doctor).value
        #expect(model.console.last == "Done: nb doctor")
    }
}
