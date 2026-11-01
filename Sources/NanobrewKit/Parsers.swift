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
            case "trust:": info.trust = value
            case "deps:": info.dependencies = value.split(separator: ", ").map(String.init)
            default: break
            }
        }
        return info
    }
}
