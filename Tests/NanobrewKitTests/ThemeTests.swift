import AppKit
import Testing
@testable import NanobrewKit

@Suite struct IconTests {
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
