import AppKit
import NanobrewKit
import SwiftUI

struct BundleView: View {
    @Environment(AppModel.self) private var model
    @State private var status = ""

    var body: some View {
        Form {
            SwiftUI.Section("Bundle") {
                HStack {
                    Button("Dump to File…", action: dump)
                    Button("Install from File…", action: install)
                }
                if !status.isEmpty { Text(status).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
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
        Form {
            SwiftUI.Section("Telemetry") {
                HStack {
                    Text("Telemetry: " + (telemetry.map { $0 ? "on" : "off" } ?? "unknown"))
                    Button("On") { model.request(.telemetry(on: true)) }
                    Button("Off") { model.request(.telemetry(on: false)) }
                }
            }
            SwiftUI.Section("Shell completions") {
                HStack {
                    Picker("Shell", selection: $shell) {
                        ForEach(["zsh", "bash", "fish"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(completions, forType: .string)
                    }
                    .disabled(completions.isEmpty)
                }
                ScrollView {
                    Text(completions).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            }
            SwiftUI.Section("Trust attest") {
                HStack {
                    TextField("Package", text: $attestPackage)
                    Toggle("Cask", isOn: $attestCask)
                    TextField("Output file (optional)", text: $attestOutput)
                    Button("Attest") {
                        model.request(.trustAttest(attestPackage, cask: attestCask, output: attestOutput.isEmpty ? nil : attestOutput))
                    }
                    .disabled(attestPackage.isEmpty)
                }
            }
            SwiftUI.Section("Danger zone") {
                HStack {
                    Button("Migrate from Homebrew…") { model.request(.migrate) }
                    Button("Remove nanobrew (nuke)…") { model.request(.nuke) }
                }
            }
            SwiftUI.Section("nb path") {
                HStack {
                    TextField("Path to nb (empty: default places)", text: $nbPath)
                    Button("Save") { model.saveNBPath(nbPath) }
                }
                Text("Using: " + (model.nbPath ?? "nb not found")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { telemetry = await model.telemetryEnabled() }
        .task(id: shell) { completions = await model.capture(.completions(shell)).lines.joined(separator: "\n") }
        .onChange(of: model.running) { _, running in
            if running == nil { Task { telemetry = await model.telemetryEnabled() } }
        }
    }
}
