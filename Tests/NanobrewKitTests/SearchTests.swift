import Foundation
import Testing
@testable import NanobrewKit

@Suite struct SearchTests {
    @Test func parsesFormulaAndCaskRows() throws {
        let rows = SearchResult.parse(try recorded("search_iterm2"))
        #expect(rows.count == 8)
        #expect(rows[0] == SearchResult(name: "gptline", version: "1.0.8_25",
                                        description: "ChatGPT client with native iTerm2 support", isCask: false, installed: false))
        #expect(rows[1] == SearchResult(name: "iterm2", version: "3.7.6",
                                        description: "Terminal emulator as alternative to Apple's Terminal app", isCask: true, installed: false))
    }

    @Test func parsesTheInstalledTag() throws {
        #expect(SearchResult.parse(try recorded("search_puremac")) == [
            SearchResult(name: "puremac", version: "3.2.0", description: "Open-source application manager and system cleaner",
                         isCask: true, installed: true),
        ])
        let sl = SearchResult.parse(try recorded("search_sl"))
        #expect(sl.count == 328)
        #expect(sl.first { $0.name == "sl" } == SearchResult(name: "sl", version: "5.02",
            description: "Prints a steam locomotive if you type sl instead of ls", isCask: false, installed: false))
        #expect(sl.first { $0.name == "brotli" }?.installed == true)
    }

    @Test func noResultGivesAnEmptyList() throws {
        #expect(SearchResult.parse(try recorded("search_zzqqxxnothing")).isEmpty)
    }

    @Test func catalogueBuildsEveryInstallForm() {
        #expect(NBCommand.search("sl") == NBCommand(args: ["search", "sl"], changes: false))
        #expect(NBCommand.install("sl").args == ["install", "sl"])
        #expect(NBCommand.install("iterm2", cask: true).args == ["install", "--cask", "iterm2"])
        #expect(NBCommand.install("sl", shims: true).args == ["install", "--shims", "sl"])
        #expect(NBCommand.install("sl", trustedOnly: true).args == ["install", "--trusted-only", "sl"])
        #expect(NBCommand.install("sl", trusted: true).args == ["install", "sl@trusted"])
        #expect(NBCommand.install("user/tap/name").args == ["install", "user/tap/name"])
        #expect(NBCommand.install("sl", cask: true, shims: true, trustedOnly: true, trusted: true).changes)
        #expect(NBCommand.install("sl").changes && NBCommand.install("sl").confirmation == .none)
    }
}
