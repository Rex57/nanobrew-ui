import AppKit
import NanobrewKit
import SwiftUI

/// Bundle in the theme (app-screens.md §8.2): two settings rows.
struct BundleView: View {
    @Environment(AppModel.self) private var model
    @State private var status = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Bundle") {
                    Text("A bundle file lists packages, so you can install the same set on another Mac.")
                }
                .padding(.bottom, 12)
                SettingsRow(title: "Export to a file",
                            description: "Writes the list of what nanobrew has installed (nb bundle dump) to a file you choose.") {
                    Button("Export…", action: dump)
                }
                SettingsRow(title: "Install from a file",
                            description: "Installs every package a bundle file lists (nb bundle install). Asks first.") {
                    Button("Install…", action: install)
                }
                if !status.isEmpty {
                    Text(status).font(.system(size: 13)).foregroundStyle(Theme.muted).textSelection(.enabled).padding(.top, 12)
                }
            }
            .padding(24)
        }
    }

    private func dump() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Nanobrew"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await model.bundleDump(to: url)
                status = "Saved to \(url.path)"
            } catch {
                status = "nb bundle dump failed: \(error.localizedDescription)"
            }
        }
    }

    private func install() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.request(.bundleInstall(url.path))
    }
}

/// Settings in the theme (app-screens.md §8.2): two-column rows, then the Danger zone last.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var telemetry: Bool?
    @State private var shell = "zsh"
    @State private var completions = ""
    @State private var attestPackage = ""
    @State private var attestCask = false
    @State private var attestOutput = ""
    @State private var nbPath = UserDefaults.standard.string(forKey: NBLocator.savedPathKey) ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Settings") { Text("Where the app finds nb, and nb's own settings.") }
                    .padding(.bottom, 12)
                SettingsRow(title: "nb path", description: "Empty: the default places. Using: "
                            + (model.nbPath ?? "nb not found")) {
                    TextField("Path to nb", text: $nbPath).themedField(width: 260)
                    Button("Save") { model.saveNBPath(nbPath) }
                }
                SettingsRow(title: "Telemetry", description: "nanobrew's anonymous usage reports. Now: "
                            + (telemetry.map { $0 ? "on." : "off." } ?? "unknown.")) {
                    Button("On") { model.request(.telemetry(on: true)) }
                    Button("Off") { model.request(.telemetry(on: false)) }
                }
                SettingsRow(title: "Shell completions", description: "The completion script for your shell, to copy into its setup.") {
                    Picker("Shell", selection: $shell) {
                        ForEach(["zsh", "bash", "fish"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(completions, forType: .string)
                    }
                    .disabled(completions.isEmpty)
                }
                ScrollView {
                    Text(completions).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(height: 120)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .padding(.vertical, 12)
                SettingsRow(title: "Trust attest", description: "Writes a verification record of a package, for nanobrew's maintainers to review and sign.") {
                    TextField("Package", text: $attestPackage).themedField(width: 140)
                    Toggle(isOn: $attestCask) { Text("Cask").font(.system(size: 13)) }
                    TextField("Output file (optional)", text: $attestOutput).themedField(width: 180)
                    Button("Attest") {
                        model.request(.trustAttest(attestPackage, cask: attestCask, output: attestOutput.isEmpty ? nil : attestOutput))
                    }
                    .disabled(attestPackage.isEmpty)
                }
                Text("Danger zone").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.top, 32)
                if model.askBeforeQuit {
                    Text("Wait until no command runs.").font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
                // Only on an idle app: a queued nuke could not be withdrawn (Cancel would start it).
                Group {
                    SettingsRow(title: "Migrate from Homebrew",
                                description: "Imports the packages Homebrew installed into nanobrew's database. This changes what nanobrew manages. Asks first.") {
                        Button("Migrate from Homebrew…") { model.request(.migrate) }
                            .buttonStyle(OutlinedButtonStyle(color: Theme.negative, border: Theme.negative))
                    }
                    SettingsRow(title: "Remove nanobrew",
                                description: "Deletes nanobrew and every package it installed, for good. You type yes to confirm.") {
                        Button("Remove nanobrew (nuke)…") { model.request(.nuke) }
                            .buttonStyle(OutlinedButtonStyle(color: Theme.negative, border: Theme.negative))
                    }
                }
                .disabled(model.askBeforeQuit)
            }
            .padding(24)
        }
        .task { telemetry = await model.telemetryEnabled() }
        .task(id: shell) { completions = await model.completions(shell) ?? "" }
        .onChange(of: model.running) { _, running in
            if running == nil { Task { telemetry = await model.telemetryEnabled() } }
        }
    }
}
