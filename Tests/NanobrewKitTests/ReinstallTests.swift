import Foundation
import Testing
@testable import NanobrewKit

/// One fixed preferences domain for the verdict tests (so a verdict never reaches the test runner's own
/// defaults), emptied before and after each test; the tests that use it run one at a time.
final class ScratchDefaults {
    static let name = "nanobrew-ui-tests"
    let defaults = UserDefaults(suiteName: ScratchDefaults.name)!

    init() { defaults.removePersistentDomain(forName: Self.name) }
    deinit { defaults.removePersistentDomain(forName: Self.name) }
}

let firefoxReason = "this download format does not support staged upgrades yet"

@Suite struct UnsupportedSkipTests {
    @Test func parsesTheUnsupportedLineOfRecordedUpgradeOutput() throws {
        #expect(UnsupportedSkip.parse(try recorded("upgrade_--cask_firefox_puremac")) == [
            UnsupportedSkip(token: "firefox", latest: "145.0.1", reason: firefoxReason),
        ])
    }

    @Test func plainWordsForTheReason() {
        // nb gives this reason only for .dmg and .unknown downloads, and installs .unknown as a disk image.
        #expect(UnsupportedSkip.plain(firefoxReason) == "disk image")
        #expect(UnsupportedSkip.plain("external installers cannot be rolled back") == "external installer")
        // No plain words: the badge says only "Can't upgrade in place".
        #expect(UnsupportedSkip.plain("artifact requires side effects without rollback support") == nil)
    }
}

@MainActor @Suite(.serialized) struct VerdictTests {
    let firefox = OutdatedPackage(name: "firefox", installed: "144.0", latest: "145.0.1", isCask: true, pinned: false)

    @Test func anUpgradeThatSkipsACaskGivesAVerdictForThatVersion() async throws {
        let nb = try FakeNB()
        let scratch = ScratchDefaults()
        let defaults = scratch.defaults
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, defaults: defaults)
        #expect(model.verdict(for: firefox) == nil)
        await model.run(NBCommand(args: ["upgrade", "--cask", "firefox", "puremac"], changes: true)).value
        #expect(model.verdict(for: firefox) == firefoxReason)
        // After a restart: a new model on the same preferences.
        let again = AppModel(statePath: fixture("state.json"), nbPath: nb.path, defaults: defaults)
        #expect(again.verdict(for: firefox) == firefoxReason)
        // A new version of the same cask has no verdict; reading it with stale rows does not delete the verdict.
        var newer = firefox
        newer.latest = "146.0"
        #expect(again.verdict(for: newer) == nil)
        #expect(again.verdict(for: firefox) == firefoxReason)
    }

    @Test func theStatusLeavesOutASkippedCaskAndSaysItWasSkipped() async throws {
        let nb = try FakeNB()
        let scratch = ScratchDefaults()
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now,
                             defaults: scratch.defaults)
        await model.run(NBCommand(args: ["upgrade", "--cask", "firefox", "puremac"], changes: true)).value
        #expect(model.status?.text == "Upgraded puremac in 84 ms; skipped firefox (can't upgrade in place)")
    }

    @Test func upgradeReadyAndUpgradeAllCasksLeaveOutPinnedAndUnsupported() async throws {
        let nb = try FakeNB()
        let scratch = ScratchDefaults()
        let defaults = scratch.defaults
        let model = AppModel(statePath: fixture("state.json"), nbPath: nb.path, defaults: defaults)
        await model.run(NBCommand(args: ["upgrade", "--cask", "firefox", "puremac"], changes: true)).value
        let rows = [
            OutdatedPackage(name: "node", installed: "26.13.0_2", latest: "26.14.0", isCask: false, pinned: false),
            OutdatedPackage(name: "libffi", installed: "3.8.0", latest: "3.9.0", isCask: false, pinned: true),
            OutdatedPackage(name: "puremac", installed: "3.2.0", latest: "3.3.0", isCask: true, pinned: false),
            firefox,
        ]
        #expect(model.readyUpdates(rows).map(\.name) == ["node", "puremac"])
        #expect(model.upgradeReady(rows) == [
            NBCommand(args: ["upgrade", "node"], changes: true),
            NBCommand(args: ["upgrade", "--cask", "puremac"], changes: true),
        ])
        #expect(model.upgradeAllCasks(rows) == NBCommand(args: ["upgrade", "--cask", "puremac"], changes: true))
        #expect(model.upgradeAllCasks([firefox]) == nil)
    }
}

@MainActor @Suite struct ReinstallTests {
    /// A reinstall writes no preferences (no upgrade runs).
    func model(_ nb: FakeNB) -> AppModel { nb.model() }

    @Test func aGoodReinstallRunsRemoveThenInstall() async throws {
        let nb = try FakeNB()
        await model(nb).reinstall("firefox").value
        #expect(nb.argvs == [["remove", "--cask", "firefox"], ["install", "--cask", "firefox"]])
    }

    @Test func aFailedRemoveNeverStartsTheInstall() async throws {
        let nb = try FakeNB()
        try nb.exit("remove", code: 1)
        let model = model(nb)
        await model.reinstall("firefox").value
        #expect(nb.argvs == [["remove", "--cask", "firefox"]])
        #expect(model.status?.text == "Failed: nb remove --cask firefox (exit code 1)")
    }

    @Test func aFailedInstallSaysTheCaskWasRemoved() async throws {
        let nb = try FakeNB()
        try nb.exit("install", code: 1)
        let model = model(nb)
        await model.reinstall("firefox").value
        let text = "firefox was removed, but the new version did not install. Install it again from Discover."
        #expect(nb.argvs == [["remove", "--cask", "firefox"], ["install", "--cask", "firefox"]])
        #expect(model.console.last == text)
        #expect(model.status?.text == text)
        #expect(model.status?.kind == .failure)
    }
}

@MainActor @Suite struct LastRunResetTests {
    @Test func aRunThatCannotStartForgetsTheEarlierSuccess() async throws {
        let nb = try FakeNB()
        let model = nb.model()
        let remove = NBCommand.removeCask("firefox")
        await model.run(remove).value
        #expect(model.lastRunSucceeded(remove))
        try FileManager.default.removeItem(atPath: nb.path)
        await model.run(remove).value
        #expect(!model.lastRunSucceeded(remove))
    }
}
