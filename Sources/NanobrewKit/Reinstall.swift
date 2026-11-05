import Foundation

/// A cask that `nb upgrade` skipped (nanobrew main.zig runUpgrade):
/// `    <token> (<old> -> <new>) [unsupported, skipping: <reason>]`.
public struct UnsupportedSkip: Equatable, Sendable {
    public var token: String
    /// The installed (old) version: the verdict's key with the token (DD24).
    public var installed: String
    public var reason: String

    public static func parse(_ lines: [String]) -> [UnsupportedSkip] {
        lines.compactMap { line in
            guard let m = line.trimmingCharacters(in: .whitespaces)
                .wholeMatch(of: /(\S+) \((.+) -> .+?\) \[unsupported, skipping: (.+)\]/) else { return nil }
            return UnsupportedSkip(token: String(m.1), installed: String(m.2), reason: String(m.3))
        }
    }

    /// nb's reason in plain words for the badge (nanobrew src/cask/upgrade.zig unsupportedReason); nil when it has
    /// none, and the badge then says only "Can't upgrade in place". nb gives the download-format reason only for
    /// .dmg and .unknown downloads, and installs .unknown as a disk image (src/api/cask.zig, src/cask/install.zig).
    public static func plain(_ reason: String) -> String? {
        switch reason {
        case "this download format does not support staged upgrades yet": "disk image"
        case "external installers cannot be rolled back": "external installer"
        case "package installer receipts cannot be rolled back": "installer receipts"
        default: nil
        }
    }
}

/// What an ended upgrade did (D14): the casks nb skipped as unsupported, and whether it replaced Nanobrew UI itself
/// (D20). Any other command has no outcome.
public struct UpgradeOutcome: Equatable, Sendable {
    public var skips: [UnsupportedSkip]
    public var replacedSelf: Bool

    public init(skips: [UnsupportedSkip], replacedSelf: Bool) {
        self.skips = skips
        self.replacedSelf = replacedSelf
    }

    /// `exitCode` nil: cancelled or ended by a signal. `casks`: state.json read after the run; `appVersion`: the
    /// running app's. Skips come from the output whatever the exit code; only a success offers the restart.
    public init(command: NBCommand, output: [String], exitCode: Int32?, casks: [Cask]?, appVersion: String?) {
        guard command.verb == "upgrade" else { self.init(skips: [], replacedSelf: false); return }
        let token = "nanobrew-ui"
        // A tap install records the full name, for example Rex57/tap/nanobrew-ui.
        let isSelf = { (name: String) in name == token || name.hasSuffix("/" + token) }
        // Every matching record counts: a short-name and a tap install can both be in state.json.
        let replaced = exitCode == 0 && appVersion != nil && (casks ?? []).contains {
            isSelf($0.token) && (command.names.isEmpty || command.names.contains($0.token)) && $0.version != appVersion
        }
        self.init(skips: UnsupportedSkip.parse(output), replacedSelf: replaced)
    }
}

extension AppModel {
    private static func verdictKey(_ token: String) -> String { "ReinstallVerdict.\(token)" }

    /// DD15, DD24: remembers nb's verdict per cask and installed version in the app's own preferences. The skip
    /// line's new version can differ from outdated's (nb's trust fallback); the installed version is the same in both.
    func record(_ skips: [UnsupportedSkip]) {
        for skip in skips {
            defaults.set(["installed": skip.installed, "reason": skip.reason], forKey: Self.verdictKey(skip.token))
        }
        if !skips.isEmpty { verdictsRecorded += 1 }
    }

    /// nb's reason when it skipped this cask, at this installed version, as unsupported; none once the installed
    /// version changed (an upgrade or a reinstall). A read never deletes: the next skip of the token overwrites it.
    public func verdict(for row: OutdatedPackage) -> String? {
        _ = verdictsRecorded
        guard row.isCask, let saved = defaults.dictionary(forKey: Self.verdictKey(row.name)) as? [String: String],
              saved["installed"] == row.installed else { return nil }
        return saved["reason"]
    }

    /// The rows "Upgrade <n>" upgrades: not pinned, not known as unsupported.
    public func readyUpdates(_ rows: [OutdatedPackage]) -> [OutdatedPackage] {
        rows.filter { !$0.pinned && verdict(for: $0) == nil }
    }

    /// "Upgrade <n>": one upgrade of the ready formulae and one of the ready casks, by name.
    public func upgradeReady(_ rows: [OutdatedPackage]) -> [NBCommand] {
        let ready = readyUpdates(rows)
        let formulae = ready.filter { !$0.isCask }.map(\.name)
        let casks = ready.filter(\.isCask).map(\.name)
        return (formulae.isEmpty ? [] : [NBCommand(args: ["upgrade"] + formulae, changes: true)])
            + (casks.isEmpty ? [] : [NBCommand(args: ["upgrade", "--cask"] + casks, changes: true)])
    }

    /// "Upgrade All Casks" by name, so a cask with an unsupported verdict is never part of it; nil: none ready.
    public func upgradeAllCasks(_ rows: [OutdatedPackage]) -> NBCommand? {
        let casks = readyUpdates(rows).filter(\.isCask).map(\.name)
        return casks.isEmpty ? nil : NBCommand(args: ["upgrade", "--cask"] + casks, changes: true)
    }

    /// D32: removes the cask, and installs it again only when the remove exited 0. A failed install says the cask
    /// is gone, in the console and the status line.
    @discardableResult
    public func reinstall(_ token: String) -> Task<Void, Never> {
        reinstalling.insert(token)
        return Task {
            defer { reinstalling.remove(token) }
            let remove = NBCommand.removeCask(token)
            await run(remove).value
            guard lastRunSucceeded(remove) else { return }
            let install = NBCommand.install(token, cask: true)
            await run(install).value
            guard !lastRunSucceeded(install) else { return }
            let text = "\(token) was removed, but the new version did not install. Install it again from Discover."
            reportFailure(text)
        }
    }
}
