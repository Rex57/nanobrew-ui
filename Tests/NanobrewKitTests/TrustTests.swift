import Testing
@testable import NanobrewKit

@Suite struct TrustTests {
    func trust(_ name: String) throws -> Trust? {
        Trust(try #require(PackageInfo.parse(try recorded(name))).trust)
    }

    @Test func installVerifiedWithAPassedProbe() throws {
        let trust = try trust("info_node")
        #expect(trust?.text == "Install verified · local probe passed")
        #expect(trust?.probe == .passed)
    }

    @Test func sourceVerifiedNotProbed() throws {
        let trust = try trust("info_tree")
        #expect(trust?.text == "Source verified · not probed yet")
        #expect(trust?.probe == .notProbed)
    }

    @Test func checksumVerifiedNotProbed() throws {
        let trust = try trust("info_--cask_iterm2")
        #expect(trust?.text == "Checksum verified · not probed yet")
        #expect(trust?.probe == .notProbed)
    }

    @Test func checksumVerifiedWithAFailedProbe() throws {
        let trust = try trust("info_libffi")
        #expect(trust?.text == "Checksum verified · local probe failed")
        #expect(trust?.probe == .failed)
    }

    @Test func noTrustLineGivesNothing() {
        #expect(Trust("") == nil)
    }

    @Test func theLicenseIsKept() throws {
        #expect(try #require(PackageInfo.parse(try recorded("info_node"))).license == "MIT")
    }
}
