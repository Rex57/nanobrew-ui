import Foundation

public struct PackageDetail: Equatable, Sendable {
    public var info: PackageInfo?
    public var tree: String?
    public var error: String?
}

/// `nb info <name>` and `nb info --cask <token>` (nanobrew main.zig runInfo, showCaskInfo).
public struct PackageInfo: Equatable, Sendable {
    public var name = ""
    public var version = ""
    public var description = ""
    public var homepage = ""
    public var license = ""
    public var trust = ""
    public var dependencies: [String] = []
    public var artifacts: [String] = []

    static let keys = ["homepage:", "license:", "trust:", "url:", "sha256:", "deps:", "build deps:", "source:",
                       "artifacts:", "caveats:", "security warnings:"]

    /// nil when the text is not info (for example nb's "nb: formula 'x' not found").
    public static func parse(_ lines: [String]) -> PackageInfo? {
        guard let header = lines.first, !header.isEmpty, !header.hasPrefix(" "), !header.hasPrefix("nb: "),
              let space = header.replacing(" (bottled)", with: "").lastIndex(of: " ") else { return nil }
        let head = header.replacing(" (bottled)", with: "")
        var info = PackageInfo(name: String(head[..<space]), version: String(head[head.index(after: space)...]))
        var section = ""
        for (index, line) in lines.dropFirst().enumerated() {
            if line.hasPrefix("    ") {
                if section == "artifacts:" { info.artifacts.append(line.trimmingCharacters(in: .whitespaces)) }
                continue
            }
            guard line.hasPrefix("  ") else { continue }
            let text = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            section = keys.first { text.hasPrefix($0) } ?? ""
            let value = text.dropFirst(section.count).trimmingCharacters(in: .whitespaces)
            switch section {
            case "": if index == 0 { info.description = text }
            case "homepage:": info.homepage = value
            case "license:": info.license = value
            case "trust:": info.trust = value
            case "deps:": info.dependencies = value.split(separator: ", ").map(String.init)
            default: break
            }
        }
        return info
    }
}

/// nb's trust line in plain words: `source-verified (local probe: not recorded; run …)` reads
/// "Source verified · not probed yet".
public struct Trust: Equatable, Sendable {
    public enum Probe: Sendable { case passed, failed, notProbed, unknown }
    public let level: String
    public let probe: Probe

    public init?(_ line: String) {
        let word = line.prefix { $0 != " " && $0 != "(" }
        guard !word.isEmpty else { return nil }
        let level = word.replacingOccurrences(of: "-", with: " ")
        self.level = level.prefix(1).uppercased() + level.dropFirst()
        probe = line.contains("local probe: passed") ? .passed : line.contains("local probe: failed") ? .failed
            : line.contains("local probe: not recorded") ? .notProbed : .unknown
    }

    public var text: String {
        switch probe {
        case .passed: "\(level) · local probe passed"
        case .failed: "\(level) · local probe failed"
        case .notProbed: "\(level) · not probed yet"
        case .unknown: level
        }
    }
}

/// One row of `nb search` (nanobrew main.zig runSearch): `name version[ [installed]][ (cask)] - desc`.
public struct SearchResult: Equatable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var description: String
    public var isCask: Bool
    public var installed: Bool

    public init(name: String, version: String, description: String, isCask: Bool, installed: Bool) {
        self.name = name
        self.version = version
        self.description = description
        self.isCask = isCask
        self.installed = installed
    }

    public static func parse(_ lines: [String]) -> [SearchResult] {
        lines.compactMap { line in
            guard !line.hasPrefix("==>"), let dash = line.range(of: " - ") ?? (line.hasSuffix(" -") ? line.range(of: " -", options: .backwards) : nil)
            else { return nil }
            let words = line[..<dash.lowerBound].split(separator: " ").map(String.init)
            guard words.count >= 2 else { return nil }
            return SearchResult(name: words[0], version: words[1],
                                description: String(line[dash.upperBound...]).trimmingCharacters(in: .whitespaces),
                                isCask: words.contains("(cask)"), installed: words.contains("[installed]"))
        }
    }
}

/// One row of `nb outdated` (nanobrew main.zig runOutdated): `name (old -> new)[ (cask)][ [pinned]]`.
public struct OutdatedPackage: Equatable, Hashable, Sendable {
    public var name: String
    public var installed: String
    public var latest: String
    public var isCask: Bool
    public var pinned: Bool

    public init(name: String, installed: String, latest: String, isCask: Bool, pinned: Bool) {
        self.name = name
        self.installed = installed
        self.latest = latest
        self.isCask = isCask
        self.pinned = pinned
    }

    public static func parse(_ lines: [String]) -> [OutdatedPackage] {
        lines.compactMap { line in
            guard let m = line.wholeMatch(of: /(\S+) \((.+) -> (.+?)\)( \(cask\))?( \[pinned\])?/) else { return nil }
            return OutdatedPackage(name: String(m.1), installed: String(m.2), latest: String(m.3),
                                   isCask: m.4 != nil, pinned: m.5 != nil)
        }
    }
}

/// One row of `nb services list` (nanobrew main.zig runServices): `  name (formula) [running|stopped]`.
public struct Service: Equatable, Hashable, Sendable {
    public var name: String
    public var formula: String
    public var running: Bool

    public init(name: String, formula: String, running: Bool) {
        self.name = name
        self.formula = formula
        self.running = running
    }

    public static func parse(_ lines: [String]) -> [Service] {
        lines.compactMap { line in
            guard let m = line.wholeMatch(of: /\ \ (\S+) \((.*)\) \[(running|stopped)\]/) else { return nil }
            return Service(name: String(m.1), formula: String(m.2), running: m.3 == "running")
        }
    }
}

/// `nb autoupdate status` (nanobrew main.zig:3698-3700): `==> Auto-update is [not ]installed, [not ]enabled`.
public struct AutoupdateStatus: Equatable, Sendable {
    public var installed: Bool
    public var enabled: Bool

    public init(installed: Bool, enabled: Bool) {
        self.installed = installed
        self.enabled = enabled
    }

    public static func parse(_ lines: [String]) -> AutoupdateStatus? {
        for line in lines {
            if let m = line.wholeMatch(of: /==> Auto-update is (not )?installed, (not )?enabled/) {
                return AutoupdateStatus(installed: m.1 == nil, enabled: m.2 == nil)
            }
        }
        return nil
    }
}

/// `nb telemetry status` (nanobrew main.zig:5956): true for "Telemetry is on.", false for "off", nil otherwise.
public func parseTelemetry(_ lines: [String]) -> Bool? {
    lines.lazy.compactMap { $0.wholeMatch(of: /Telemetry is (on|off)\./).map { $0.1 == "on" } }.first
}

/// The nb version this app was tested with (D18).
public let testedNBVersion = "0.1.214"

/// `nb version` prints the bare version, for example `0.1.214`.
public func parseNBVersion(_ lines: [String]) -> String? {
    lines.lazy.compactMap { $0.trimmingCharacters(in: .whitespaces).wholeMatch(of: /\d+(\.\d+)+/).map { String($0.0) } }.first
}
