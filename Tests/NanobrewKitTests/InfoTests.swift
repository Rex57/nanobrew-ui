import Foundation
import Testing
@testable import NanobrewKit

func recorded(_ name: String) throws -> [String] {
    try String(contentsOfFile: fixture("nb-output/\(name).txt"), encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

@Suite struct InfoTests {
    @Test func parsesFormulaInfo() throws {
        let info = try #require(PackageInfo.parse(try recorded("info_node")))
        #expect(info.name == "node")
        #expect(info.version == "26.13.0_2")
        #expect(info.description == "Open-source, cross-platform JavaScript runtime environment")
        #expect(info.homepage == "https://nodejs.org/")
        #expect(info.trust == "install-verified (local probe: passed, 1793511319)")
        #expect(info.dependencies == ["abseil", "ada-url", "brotli", "c-ares", "hdrhistogram_c", "icu4c@79", "libffi",
                                      "libnghttp2", "libuv", "llhttp", "merve", "nbytes", "openssl@4", "simdjson",
                                      "simdutf", "sqlite", "uvwasi", "zstd", "highway", "python"])
        #expect(info.artifacts.isEmpty)
    }

    @Test func parsesFormulaWithNoDeps() throws {
        let info = try #require(PackageInfo.parse(try recorded("info_tree")))
        #expect(info.name == "tree" && info.version == "2.3.2")
        #expect(info.description == "Display directories as trees (with optional color/HTML output)")
        #expect(info.dependencies.isEmpty)
    }

    @Test func parsesCaskInfo() throws {
        let info = try #require(PackageInfo.parse(try recorded("info_--cask_iterm2")))
        #expect(info.name == "iTerm2")
        #expect(info.version == "3.7.6")
        #expect(info.description == "Terminal emulator as alternative to Apple's Terminal app")
        #expect(info.homepage == "https://iterm2.com/")
        #expect(info.trust == "checksum-verified (local probe: not recorded; run `nb doctor --probe iterm2`)")
        #expect(info.artifacts == ["uninstall quit: com.googlecode.iterm2", "app: iTerm.app"])
    }

    @Test func errorTextIsNotInfo() {
        #expect(PackageInfo.parse(["nb: formula 'nosuch' not found"]) == nil)
    }

    @Test func catalogueHasReadOnlyInfoAndDeps() {
        #expect(NBCommand.info("jq") == NBCommand(args: ["info", "jq"], changes: false))
        #expect(NBCommand.caskInfo("iterm2") == NBCommand(args: ["info", "--cask", "iterm2"], changes: false))
        #expect(NBCommand.depsTree("jq") == NBCommand(args: ["deps", "--tree", "jq"], changes: false))
    }

    @MainActor @Test func detailOfAFormulaHasInfoAndTree() async throws {
        let nb = try FakeNB()
        let detail = await nb.model().detail(name: "node", cask: false)
        #expect(detail.info?.name == "node")
        #expect(detail.tree?.hasPrefix("node\n├── abseil\n├── ada-url\n│   ├── fmt") == true)
        #expect(nb.argvs == [["info", "node"], ["deps", "--tree", "node"]])
    }

    @MainActor @Test func detailOfACaskHasNoTree() async throws {
        let nb = try FakeNB()
        let detail = await nb.model().detail(name: "puremac", cask: true)
        #expect(detail.info?.artifacts == ["app: PureMac.app"])
        #expect(detail.tree == nil)
        #expect(nb.argvs == [["info", "--cask", "puremac"]])
    }

    @MainActor @Test func detailShowsNbErrorText() async throws {
        let nb = try FakeNB()
        try nb.stderr("info", text: "nb: formula 'nosuch' not found\n")
        try nb.exit("info", code: 1)
        let detail = await nb.model().detail(name: "nosuch", cask: false)
        #expect(detail.info == nil)
        #expect(detail.error == "nb: formula 'nosuch' not found")
    }

    @MainActor @Test func aCancelledDetailFetchIsNoExitZeroFailure() async throws {
        let nb = try FakeNB()
        try nb.wait("info", seconds: 30)
        let model = nb.model()
        let task = Task { await model.detail(name: "node", cask: false) }
        await eventually { nb.log.contains { $0.first == "CHILD" } }
        task.cancel()
        let detail = await task.value
        nb.killChildren()
        #expect(detail.info == nil)
        #expect(detail.error != "nb info failed (exit code 0)")
    }

    @MainActor @Test func notFoundWithExitZeroIsStillAnError() async throws {
        // Real nb 0.1.214 prints "not found" to stderr and exits 0.
        let nb = try FakeNB()
        try nb.stderr("info", text: "nb: formula 'nosuch' not found\n")
        let detail = await nb.model().detail(name: "nosuch", cask: false)
        #expect(detail.error == "nb: formula 'nosuch' not found")
    }
}
