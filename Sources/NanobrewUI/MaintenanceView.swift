import NanobrewKit
import SwiftUI

/// Maintenance as settings rows (app-screens.md §8.2): a title and a grey description, the controls on the right.
struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @State private var probePackage = ""
    @State private var pruneKegs = false
    @State private var autoupdate: AutoupdateStatus?
    @State private var alsoUpgrade = false
    @State private var pattern = ""
    @State private var leavesTree = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Maintenance") { Text(subline) }.padding(.bottom, 12)
                SettingsRow(title: "Doctor", description: "Checks the install for problems.", help: Self.help["Doctor"]) {
                    if let result = model.doctorResult { resultText(result) }
                    Button("Doctor") { model.request(.doctor) }.disabled(model.inProgress.contains(.doctor))
                }
                SettingsRow(title: "Probe", description: "Tests that packages still run.", help: Self.help["Probe"]) {
                    TextField("Package (optional)", text: $probePackage).themedField(width: 180)
                    Button("Probe") { model.request(.doctorProbe(probePackage.isEmpty ? nil : probePackage)) }
                }
                SettingsRow(title: "Cleanup", description: "Frees disk space.", help: Self.help["Cleanup"]) {
                    if model.canCleanUp(pruneKegs: pruneKegs), let result = model.cleanupDryRunResult {
                        resultText(result)
                    } else {
                        Text("Dry run first").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Toggle(isOn: $pruneKegs) { flagLabel("Remove phantom keg entries", "--prune-kegs") }
                    Button("Dry Run") { model.dryRunCleanup(pruneKegs: pruneKegs) }
                    Button("Clean Up…") { model.cleanUp(pruneKegs: pruneKegs) }
                        .disabled(!model.canCleanUp(pruneKegs: pruneKegs))
                }
                SettingsRow(title: "Update nb", description: "Updates nanobrew itself.", help: Self.help["Update nb"]) {
                    Button("Update nanobrew") { model.request(.update) }
                }
                SettingsRow(title: "Update registry", description: "Gets the newest package list.", help: Self.help["Update registry"]) {
                    Button("Update Registry") { model.request(.updateRegistry) }
                }
                SettingsRow(title: "Auto-update", description: autoupdateText, help: Self.help["Auto-update"]) {
                    Toggle(isOn: $alsoUpgrade) { flagLabel("Also upgrade packages", "--upgrade") }
                    Button("Status") { model.request(.autoupdateStatus) }
                    Button("Enable") { model.request(.autoupdate(.enable, upgrade: alsoUpgrade)) }
                    Button("Disable") { model.request(.autoupdate(.disable, upgrade: false)) }
                    Button("Run Now") { model.request(.autoupdate(.run, upgrade: alsoUpgrade)) }
                }
                SettingsRow(title: "Where", description: "Finds the package that owns a file.", help: Self.help["Where"]) {
                    TextField("Pattern", text: $pattern).themedField(width: 180)
                    Button("Where") { model.request(.where(pattern)) }.disabled(pattern.isEmpty)
                }
                SettingsRow(title: "Leaves", description: "Lists packages nothing depends on.", help: Self.help["Leaves"]) {
                    Toggle(isOn: $leavesTree) { flagLabel("Show as a tree", "--tree") }
                    Button("Leaves") { model.request(.leaves(tree: leavesTree)) }
                }
            }
            .padding(24)
        }
        .onDisappear { model.forgetCleanupDryRun() }
        .task(id: model.commandsEnded) {
            let status = await model.autoupdateStatus()
            // A newer command end cancelled this load: keep what shows.
            if !Task.isCancelled { autoupdate = status }
        }
    }

    private var subline: String {
        "\(model.snapshot.map { "\($0.formulae.count + $0.casks.count)" } ?? "No") packages in /opt/nanobrew · auto-update "
            + (autoupdate.map { $0.enabled ? "on" : "off" } ?? "status unknown")
    }

    private var autoupdateText: String {
        "Updates on a schedule. " + (autoupdate.map { $0.enabled ? "Now: on" : "Now: off" } ?? "Status unknown")
    }

    /// D4: a result beside its button, "Can free 41.4 MB · 14:32", in the colour of its dot (amber text for attention).
    private func resultText(_ result: CommandStatus) -> some View {
        Text(result.shortText + " · " + result.time.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 12))
            .foregroundStyle(result.kind == .attention ? Theme.amberText : StatusLine.color(result.kind))
    }

    /// D10: the full text of each row, in its ? popover.
    static let help = [
        "Doctor": "Runs nb doctor. It checks the nanobrew folders, links and package records, and names each problem it finds. It changes nothing.",
        "Probe": "Runs nb doctor --probe. It starts each package's health probe and records the result. Type a package name to probe only that one; leave it empty to probe all.",
        "Cleanup": "Removes old downloads, caches and unused store files. Dry Run shows how much space Clean Up frees and changes nothing. Clean Up stays off until a dry run with the same switch ends well. \"Remove phantom keg entries\" (--prune-kegs) also removes the records of packages whose files are gone.",
        "Update nb": "Runs nb update. It installs the newest nanobrew release. Your packages do not change.",
        "Update registry": "Runs nb update-registry. It downloads the newest package index, so Discover and Updates see the newest versions.",
        "Auto-update": "Runs nb update on a schedule. With \"Also upgrade packages\" (--upgrade) it also upgrades your packages. Status asks nb if auto-update is installed and enabled.",
        "Where": "Runs nb where. Type a file path or a command name, and nb names the package that installed it.",
        "Leaves": "Runs nb leaves. It lists the installed packages that no other package needs: mostly the ones you installed yourself. \"Show as a tree\" (--tree) also shows what each one needs.",
    ]
}
