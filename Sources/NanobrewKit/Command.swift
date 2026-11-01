/// The command catalogue: every nb command the app runs, with its exact argv (D5, D8).
public struct NBCommand: Equatable, Hashable, Sendable {
    public enum Confirmation: Sendable { case none, ask, typeYes }

    public let args: [String]
    /// True when the command changes the system: it then waits its turn in the serial queue.
    public let changes: Bool
    public let confirmation: Confirmation

    public init(args: [String], changes: Bool, confirmation: Confirmation = .none) {
        self.args = args
        self.changes = changes
        self.confirmation = confirmation
    }

    /// The command as a person would type it.
    public var title: String { (["nb"] + args).joined(separator: " ") }

    public static let doctor = NBCommand(args: ["doctor"], changes: false)
    public static func info(_ name: String) -> NBCommand { NBCommand(args: ["info", name], changes: false) }
    public static func caskInfo(_ token: String) -> NBCommand { NBCommand(args: ["info", "--cask", token], changes: false) }
    public static func depsTree(_ name: String) -> NBCommand { NBCommand(args: ["deps", "--tree", name], changes: false) }
}
