import Foundation

/// What the status line shows: a dot by `kind`, the text and the time of day.
public struct CommandStatus: Equatable, Sendable {
    public enum Kind: Sendable { case running, success, failure, cancelled }
    public let kind: Kind
    public let text: String
    public let time: Date

    public init(kind: Kind, text: String, time: Date = Date()) {
        self.kind = kind
        self.text = text
        self.time = time
    }

    /// The verbs of the commands that say what they did ("Installed jq in 0.84 s").
    static let verbs = ["install": "Installed", "remove": "Removed", "upgrade": "Upgraded", "pin": "Pinned",
                        "unpin": "Unpinned", "link": "Linked", "unlink": "Unlinked", "rollback": "Rolled back",
                        "switch": "Switched to"]

    /// The result of an ended command; `exitCode` nil is a signal. `skipped`: casks nb skipped as unsupported, left
    /// out of the names and named after the time.
    init(command: NBCommand, exitCode: Int32?, cancelled: Bool, duration: Duration, skipped: [String] = []) {
        if cancelled {
            self.init(kind: .cancelled, text: "Cancelled: \(command.title)")
        } else if exitCode != 0 {
            self.init(kind: .failure, text: "Failed: \(command.title) (exit code \(exitCode.map(String.init) ?? "signal"))")
        } else {
            let names = command.args.dropFirst().filter { !$0.hasPrefix("-") && !skipped.contains($0) }
            let verb = command.program == nil ? command.args.first.flatMap { Self.verbs[$0] } : nil
            let what = verb.map { names.isEmpty ? nil : "\($0) \(names.joined(separator: " "))" } ?? nil
            let skips = skipped.isEmpty ? "" : "; skipped \(skipped.joined(separator: ", ")) (can't upgrade in place)"
            self.init(kind: .success, text: "\(what ?? "\(command.title) finished") in \(formatDuration(duration))" + skips)
        }
    }
}

/// Under 0.1 s in ms, under 10 s with two decimals, under 1 min with one, from 1 min as "1 m 05 s".
/// The ticket's examples set the 0.1 s step: 84 ms reads "84 ms", 840 ms reads "0.84 s" (DD4).
public func formatDuration(_ duration: Duration) -> String {
    let ms = Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    switch ms {
    case ..<100: return "\(ms) ms"
    case ..<10_000: return String(format: "%.2f s", Double(ms) / 1000)
    case ..<60_000: return String(format: "%.1f s", Double(ms) / 1000)
    default:
        let seconds = (ms + 500) / 1000
        return "\(seconds / 60) m " + String(format: "%02d s", seconds % 60)
    }
}
