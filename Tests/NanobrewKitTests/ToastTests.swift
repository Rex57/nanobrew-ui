import Foundation
import Testing
@testable import NanobrewKit

/// P-7 (D3): a console command that ends while the console is closed becomes the toast.
@MainActor @Suite struct ToastTests {
    func model(_ nb: FakeNB) -> AppModel {
        AppModel(statePath: fixture("state.json"), nbPath: nb.path, now: StepClock(.milliseconds(84)).now)
    }

    @Test func anInstallThatEndsWithTheConsoleClosedMakesAToast() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        await model.run(.install("jq")).value
        let toast = try #require(model.toast)
        #expect(toast.kind == .success)
        #expect(toast.text == "Installed jq")
        #expect(toast.detail == "nb install jq · 84 ms")
    }

    @Test func aDryRunToastSaysItsAnswer() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        await model.run(.cleanupDryRun(pruneKegs: false)).value
        #expect(model.toast?.text == "Dry run: can free 41.4 MB")
        #expect(model.toast?.detail == "nb cleanup --dry-run · 84 ms")
    }

    @Test func noToastWithTheConsoleOpen() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        model.toggleConsole()
        await model.run(.install("jq")).value
        #expect(model.toast == nil)
    }

    @Test func backgroundReadsMakeNoToast() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        await model.checkOutdated()
        _ = try await model.services()
        _ = await model.detail(name: "node", cask: false)
        #expect(model.toast == nil)
    }

    @Test func aNewerEndReplacesTheToastAndDismissAndViewClearIt() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        await model.run(.install("jq")).value
        await model.run(.pin("jq")).value
        #expect(model.toast?.text == "Pinned jq")
        model.dismissToast()
        #expect(model.toast == nil)
        #expect(!model.consoleShown)
        await model.run(.doctor).value
        #expect(model.toast != nil)
        model.viewToast()
        #expect(model.toast == nil)
        #expect(model.consoleShown)
    }

    @Test func aFailureAndACancelMakeAToast() async throws {
        let nb = try FakeNB()
        let model = model(nb)
        try nb.exit("install", code: 1)
        await model.run(.install("jq")).value
        #expect(model.toast?.kind == .failure)
        #expect(model.toast?.text == "Failed: nb install jq (exit code 1)")
        try nb.wait("link", seconds: 30)
        let link = model.run(.link("a"))
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        model.cancel()
        await link.value
        #expect(model.toast?.kind == .cancelled)
        #expect(model.toast?.text == "Cancelled: nb link a")
    }
}
