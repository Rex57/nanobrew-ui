import Foundation
import Testing
@testable import NanobrewKit

@Suite struct ServicesTests {
    @Test func parsesServiceRows() throws {
        // Fixture built from the row format in nanobrew main.zig:5899-5902.
        #expect(Service.parse(try recorded("services_list")) == [
            Service(name: "postgresql@17", formula: "postgresql@17", running: true),
            Service(name: "redis", formula: "redis", running: false),
        ])
    }

    @Test func noServicesGivesAnEmptyList() throws {
        #expect(Service.parse(try recorded("services_list-live")).isEmpty)
    }

    @Test func catalogueGivesServiceCommands() {
        #expect(NBCommand.servicesList == NBCommand(args: ["services", "list"], changes: false))
        #expect(NBCommand.services(.start, "redis") == NBCommand(args: ["services", "start", "redis"], changes: true))
        #expect(NBCommand.services(.stop, "redis") == NBCommand(args: ["services", "stop", "redis"], changes: true))
        #expect(NBCommand.services(.restart, "redis") == NBCommand(args: ["services", "restart", "redis"], changes: true))
    }

    @MainActor @Test func modelListsServicesThroughNb() async throws {
        let nb = try FakeNB()
        #expect(try await nb.model().services().map(\.name) == ["postgresql@17", "redis"])
        #expect(nb.argvs == [["services", "list"]])
    }
}

@MainActor @Suite struct FailedListTests {
    @Test func failedServicesListThrowsNbErrorText() async throws {
        let nb = try FakeNB()
        try nb.exit("services", code: 1)
        try nb.stderr("services", text: "nb: failed to discover services\n")
        await #expect(throws: AppModel.CommandFailed(text: "nb: failed to discover services")) { try await nb.model().services() }
    }

    @Test func failedSearchThrowsNbErrorText() async throws {
        let nb = try FakeNB()
        try nb.exit("search", code: 1)
        try nb.stderr("search", text: "nb: search failed: ConnectionRefused\n")
        await #expect(throws: AppModel.CommandFailed(text: "nb: search failed: ConnectionRefused")) { try await nb.model().search("sl") }
    }
}
