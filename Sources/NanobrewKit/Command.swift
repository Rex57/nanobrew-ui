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
    public static func remove(_ name: String) -> NBCommand { NBCommand(args: ["remove", name], changes: true, confirmation: .ask) }
    public static func removeCask(_ token: String) -> NBCommand {
        NBCommand(args: ["remove", "--cask", token], changes: true, confirmation: .ask)
    }
    public static func pin(_ name: String) -> NBCommand { NBCommand(args: ["pin", name], changes: true) }
    public static func unpin(_ name: String) -> NBCommand { NBCommand(args: ["unpin", name], changes: true) }
    public static func link(_ name: String) -> NBCommand { NBCommand(args: ["link", name], changes: true) }
    public static func unlink(_ name: String) -> NBCommand { NBCommand(args: ["unlink", name], changes: true) }
    public static func rollback(_ name: String) -> NBCommand {
        NBCommand(args: ["rollback", name], changes: true, confirmation: .ask)
    }
    public static func switchVersion(_ name: String, to version: String) -> NBCommand {
        NBCommand(args: ["switch", "\(name)@\(version)"], changes: true)
    }
    public static func depsTree(_ name: String) -> NBCommand { NBCommand(args: ["deps", "--tree", name], changes: false) }
}
