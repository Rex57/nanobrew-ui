import AppKit
import Testing
@testable import NanobrewKit

@Suite struct IconTests {
    @Test func eachIconAndTheLogoLoadOnce() {
        for icon in Icon.allCases { #expect(icon.image === icon.image, "\(icon)") }
        #expect(nanobrewLogo === nanobrewLogo)
    }

    @Test func everyIconTheAppNamesLoadsAsATemplateImage() {
        for icon in Icon.allCases {
            let image = icon.image
            #expect(image != nil, "\(icon.rawValue).svg")
            #expect(image?.isTemplate == true, "\(icon.rawValue).svg")
        }
    }

    @Test func theLogoLoads() {
        #expect(nanobrewLogo != nil)
    }
}

@MainActor @Suite struct UpdatesCountTests {
    @Test func countIsOutdatedFormulaePlusOutdatedCasks() async throws {
        // outdated.txt: node, libffi (formulae; puremac is skipped there); outdated_--cask.txt: puremac, nanobrew-ui.
        let model = try FakeNB().model()
        #expect(model.updatesCount == nil)
        await model.checkOutdated()
        #expect(model.updatesCount == 4)
    }

    @Test func noCountWhenNothingIsOutdated() async throws {
        let nb = try FakeNB()
        let live = nb.dir.appendingPathComponent("live")
        try FileManager.default.createDirectory(at: live.appendingPathComponent("nb-output"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: fixture("fake-nb"), toPath: live.appendingPathComponent("nb").path)
        for (from, to) in [("outdated-live", "outdated"), ("outdated-cask-live", "outdated_--cask")] {
            try FileManager.default.copyItem(atPath: fixture("nb-output/\(from).txt"),
                                             toPath: live.appendingPathComponent("nb-output/\(to).txt").path)
        }
        let model = AppModel(statePath: fixture("state.json"), nbPath: live.appendingPathComponent("nb").path)
        await model.checkOutdated()
        #expect(model.updatesCount == nil)
    }

    @Test func noCountWhenOutdatedFails() async throws {
        let nb = try FakeNB()
        try nb.exit("outdated", code: 1)
        let model = nb.model()
        await model.checkOutdated()
        #expect(model.updatesCount == nil)
    }
}

@MainActor @Suite struct OutdatedCheckTests {
    @Test func aFailedCheckKeepsNbErrorText() async throws {
        let nb = try FakeNB()
        try nb.exit("outdated", code: 1)
        try nb.stderr("outdated", text: "nb: could not open database\n")
        let model = nb.model()
        #expect(!model.outdatedChecked)
        await model.checkOutdated()
        #expect(model.outdatedChecked)
        #expect(model.outdatedError == "nb: could not open database")
        #expect(model.outdatedPackages.isEmpty)
    }

    @Test func aGoodCheckClearsTheError() async throws {
        let nb = try FakeNB()
        try nb.exit("outdated", code: 1)
        let model = nb.model()
        await model.checkOutdated()
        try FileManager.default.removeItem(at: nb.dir.appendingPathComponent("exit-outdated"))
        await model.checkOutdated()
        #expect(model.outdatedError == nil)
        #expect(model.outdatedPackages.map(\.name) == ["node", "libffi", "puremac", "nanobrew-ui"])
    }
}
