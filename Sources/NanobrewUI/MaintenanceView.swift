import NanobrewKit
import SwiftUI

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @State private var probePackage = ""
    @State private var dryRunDone = false
    @State private var pruneKegs = false
    @State private var autoupdate: AutoupdateStatus?
    @State private var alsoUpgrade = false
    @State private var pattern = ""
    @State private var leavesTree = false

    var body: some View {
        Form {
            SwiftUI.Section("Health") {
                HStack {
                    Button("Doctor") { model.request(.doctor) }.disabled(model.inProgress.contains(.doctor))
                    Button("Doctor Probe") { model.request(.doctorProbe(probePackage.isEmpty ? nil : probePackage)) }
                    TextField("Package (optional)", text: $probePackage)
                }
            }
            SwiftUI.Section("Cleanup") {
                HStack {
                    Toggle("Prune old kegs (--prune-kegs)", isOn: $pruneKegs)
                        .onChange(of: pruneKegs) { dryRunDone = false } // the dry run must match the real run
                    Button("Dry Run") {
                        Task {
                            let dryRun = NBCommand.cleanupDryRun(pruneKegs: pruneKegs)
                            await model.run(dryRun).value
                            dryRunDone = model.lastRunSucceeded(dryRun) // not after a failure or a cancel
                        }
                    }
                    Button("Clean Up…") {
                        dryRunDone = false
                        model.request(.cleanup(pruneKegs: pruneKegs))
                    }
                    .disabled(!dryRunDone)
                    Text(dryRunDone ? "Check the dry run in the console first." : "Run a dry run first.")
                        .foregroundStyle(.secondary)
                }
            }
            SwiftUI.Section("Update") {
                HStack {
                    Button("Update nanobrew") { model.request(.update) }
                    Button("Update Registry") { model.request(.updateRegistry) }
                }
            }
            SwiftUI.Section("Auto-update") {
                Text(autoupdate.map { "Installed: \($0.installed ? "yes" : "no"), enabled: \($0.enabled ? "yes" : "no")" }
                     ?? "Status unknown")
                HStack {
                    Toggle("Also upgrade packages (--upgrade)", isOn: $alsoUpgrade)
                    Button("Status") { model.request(.autoupdateStatus) }
                    Button("Enable") { model.request(.autoupdate(.enable, upgrade: alsoUpgrade)) }
                    Button("Disable") { model.request(.autoupdate(.disable, upgrade: false)) }
                    Button("Run Now") { model.request(.autoupdate(.run, upgrade: alsoUpgrade)) }
                }
            }
            SwiftUI.Section("Find") {
                HStack {
                    TextField("Pattern", text: $pattern)
                    Button("Where") { model.request(.where(pattern)) }.disabled(pattern.isEmpty)
                }
                HStack {
                    Toggle("Tree", isOn: $leavesTree)
                    Button("Leaves") { model.request(.leaves(tree: leavesTree)) }
                }
            }
        }
        .formStyle(.grouped)
        .task { autoupdate = await model.autoupdateStatus() }
        .onChange(of: model.running) { _, running in
            if running == nil { Task { autoupdate = await model.autoupdateStatus() } }
        }
    }
}
