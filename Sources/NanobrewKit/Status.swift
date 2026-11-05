import Foundation

/// What the status line shows: a dot by `kind`, the text and the time of day.
public struct CommandStatus: Equatable, Sendable {
    /// `skipped`: nb ended well but did nothing (every named cask was skipped as unsupported). `attention`: nb
    /// ended well and found something to look at (a Doctor with problems: nb exits 0, F5).
    public enum Kind: Sendable { case running, success, failure, cancelled, skipped, attention }
    public let kind: Kind
    public let text: String
    public let time: Date
    /// nb's answer read from its summary line ("can free 41.4 MB", "found 2 problems"); nil for other results.
    public let answer: String?

    /// A Maintenance row's words (F6): nb's answer ("Can free 41.4 MB"), else "Done" for a success, else the
    /// failure or cancel text as it is.
    public var shortText: String {
        if let answer { return answer.prefix(1).uppercased() + answer.dropFirst() }
        return kind == .success ? "Done" : text
    }

    public init(kind: Kind, text: String, time: Date = Date(), answer: String? = nil) {
        self.kind = kind
        self.text = text
        self.time = time
        self.answer = answer
    }

    /// The verbs of the commands that say what they did ("Installed jq in 0.84 s").
    static let verbs = ["install": "Installed", "remove": "Removed", "upgrade": "Upgraded", "pin": "Pinned",
                        "unpin": "Unpinned", "link": "Linked", "unlink": "Unlinked", "rollback": "Rolled back",
                        "switch": "Switched to"]

    /// What nb's summary line of a cleanup or a Doctor says (D4, F5).
    public struct Summary: Equatable, Sendable {
        public let kind: Kind
        /// "can free 41.4 MB", "nothing to clean up", "freed 0.2 MB", "no problems found", "found 2 problems".
        public let phrase: String
    }

    /// The label of a command whose result is read from nb's summary line; nil for every other command.
    static func summaryLabel(_ command: NBCommand) -> String? {
        switch command.verb {
        case "cleanup": command.args.contains("--dry-run") ? "Dry run" : "Cleanup"
        case "doctor": command.args.contains("--probe") ? nil : "Doctor"
        default: nil
        }
    }

    /// nb's summary line (nanobrew main.zig: "==> Would reclaim 41.4 MB", "==> Reclaimed 0.2 MB", "==> Nothing to
    /// clean up", "==> No issues found. …", "==> Found 2 issue(s). …"); nil for any other line or command.
    public static func summary(of command: NBCommand, line: String) -> Summary? {
        guard let label = summaryLabel(command) else { return nil }
        let line = stripANSI(line).trimmingCharacters(in: .whitespaces)
        if label == "Doctor" {
            if line.hasPrefix("==> No issues found") { return Summary(kind: .success, phrase: "no problems found") }
            guard let count = line.prefixMatch(of: /==> Found (\d+) issue\(s\)/)?.1 else { return nil }
            return Summary(kind: .attention, phrase: "found \(count) problem\(count == "1" ? "" : "s")")
        }
        if line == "==> Nothing to clean up" { return Summary(kind: .success, phrase: "nothing to clean up") }
        let (said, phrase) = label == "Dry run" ? ("==> Would reclaim ", "can free ") : ("==> Reclaimed ", "freed ")
        guard line.hasPrefix(said), line.count > said.count else { return nil }
        return Summary(kind: .success, phrase: phrase + line.dropFirst(said.count))
    }

    /// The result of an ended command; `exitCode` nil is a signal. `skipped`: casks nb skipped as unsupported, left
    /// out of the names and named after the time. `summary`: nb's summary line, for the commands that have one.
    init(command: NBCommand, exitCode: Int32?, cancelled: Bool, duration: Duration, skipped: [String] = [],
         summary: String? = nil) {
        if cancelled {
            self.init(kind: .cancelled, text: "Cancelled: \(command.title)")
        } else if exitCode != 0 {
            self.init(kind: .failure, text: "Failed: \(command.title) (exit code \(exitCode.map(String.init) ?? "signal"))")
        } else if let summary, let found = Self.summary(of: command, line: summary), let label = Self.summaryLabel(command) {
            self.init(kind: found.kind, text: "\(label): \(found.phrase) in \(formatDuration(duration))", answer: found.phrase)
        } else {
            let named = command.names
            let names = named.filter { !skipped.contains($0) }
            let skips = skipped.isEmpty ? "" : "skipped \(skipped.joined(separator: ", ")) (can't upgrade in place)"
            guard names.count > 0 || named.isEmpty || skipped.isEmpty else {
                self.init(kind: .skipped, text: "Nothing upgraded; " + skips)
                return
            }
            let verb = command.verb.flatMap { Self.verbs[$0] }
            let what = verb.map { names.isEmpty ? nil : "\($0) \(names.joined(separator: " "))" } ?? nil
            self.init(kind: .success, text: "\(what ?? "\(command.title) finished") in \(formatDuration(duration))"
                      + (skips.isEmpty ? "" : "; " + skips))
        }
    }
}

/// Under 0.1 s in ms, under 10 s with two decimals, under 1 min with one, from 1 min as "1 m 05 s". The unit is
/// chosen after rounding: 9 996 ms reads "10.0 s", 59 960 ms "1 m 00 s".
/// The ticket's examples set the 0.1 s step: 84 ms reads "84 ms", 840 ms reads "0.84 s" (DD4).
public func formatDuration(_ duration: Duration) -> String {
    let ms = Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    switch ms {
    case ..<100: return "\(ms) ms"
    case ..<9_995: return String(format: "%.2f s", Double(ms) / 1000)
    case ..<59_950: return String(format: "%.1f s", Double(ms) / 1000)
    default:
        let seconds = (ms + 500) / 1000
        return "\(seconds / 60) m " + String(format: "%02d s", seconds % 60)
    }
}
