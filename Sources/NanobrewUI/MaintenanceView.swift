import NanobrewKit
import SwiftUI

/// Maintenance as settings rows (app-screens.md §8.2): a title and a grey description, the controls on the right.
struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @State private var probePackage = ""
    /// The --prune-kegs setting of the last successful dry run; Clean Up runs only with that same setting.
    @State private var dryRunFor: Bool?
    @State private var pruneKegs = false
    @State private var autoupdate: AutoupdateStatus?
    @State private var alsoUpgrade = false
    @State private var pattern = ""
    @State private var leavesTree = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Maintenance") { Text(subline) }.padding(.bottom, 12)
                SettingsRow(title: "Doctor", description: "Checks the nanobrew installation and reports problems.") {
                    Button("Doctor") { model.request(.doctor) }.disabled(model.inProgress.contains(.doctor))
                }
                SettingsRow(title: "Probe",
                            description: "Runs the packages' health probes and records the result. Leave the name empty for all.") {
                    TextField("Package (optional)", text: $probePackage).themedField(width: 180)
                    Button("Probe") { model.request(.doctorProbe(probePackage.isEmpty ? nil : probePackage)) }
                }
                SettingsRow(title: "Cleanup", description: "Removes old downloads and unused files. "
                            + (dryRunFor == pruneKegs ? "Check the dry run in the console first." : "Run a dry run first.")) {
                    Toggle(isOn: $pruneKegs) { flagLabel("Remove phantom keg entries", "--prune-kegs") }
                    Button("Dry Run") {
                        Task {
                            let prune = pruneKegs // the setting this dry run shows, even if the switch moves meanwhile
                            let dryRun = NBCommand.cleanupDryRun(pruneKegs: prune)
                            await model.run(dryRun).value
                            dryRunFor = model.lastRunSucceeded(dryRun) ? prune : nil // not after a failure or a cancel
                        }
                    }
                    Button("Clean Up…") {
                        dryRunFor = nil
                        model.request(.cleanup(pruneKegs: pruneKegs))
                    }
                    .disabled(dryRunFor != pruneKegs)
                }
                SettingsRow(title: "Update nb", description: "Updates nanobrew itself to its newest release.") {
                    Button("Update nanobrew") { model.request(.update) }
                }
                SettingsRow(title: "Update registry", description: "Downloads the newest package index.") {
                    Button("Update Registry") { model.request(.updateRegistry) }
                }
                SettingsRow(title: "Auto-update", description: autoupdateText) {
                    Toggle(isOn: $alsoUpgrade) { flagLabel("Also upgrade packages", "--upgrade") }
                    Button("Status") { model.request(.autoupdateStatus) }
                    Button("Enable") { model.request(.autoupdate(.enable, upgrade: alsoUpgrade)) }
                    Button("Disable") { model.request(.autoupdate(.disable, upgrade: false)) }
                    Button("Run Now") { model.request(.autoupdate(.run, upgrade: alsoUpgrade)) }
                }
                SettingsRow(title: "Where", description: "Finds the package that owns a file or a command.") {
                    TextField("Pattern", text: $pattern).themedField(width: 180)
                    Button("Where") { model.request(.where(pattern)) }.disabled(pattern.isEmpty)
                }
                SettingsRow(title: "Leaves", description: "Lists the packages that nothing else depends on.") {
                    Toggle(isOn: $leavesTree) { flagLabel("Show as a tree", "--tree") }
                    Button("Leaves") { model.request(.leaves(tree: leavesTree)) }
                }
            }
            .padding(24)
        }
        .task(id: model.commandsEnded) { autoupdate = await model.autoupdateStatus() }
    }

    private var subline: String {
        "\(model.snapshot.map { "\($0.formulae.count + $0.casks.count)" } ?? "No") packages in /opt/nanobrew · auto-update "
            + (autoupdate.map { $0.enabled ? "on" : "off" } ?? "status unknown")
    }

    private var autoupdateText: String {
        guard let autoupdate else { return "Runs nb update and, if you choose, upgrades on a schedule. Status unknown." }
        return "Runs nb update and, if you choose, upgrades on a schedule. Now: "
            + (autoupdate.installed ? "installed" : "not installed") + ", " + (autoupdate.enabled ? "enabled." : "not enabled.")
    }
}
