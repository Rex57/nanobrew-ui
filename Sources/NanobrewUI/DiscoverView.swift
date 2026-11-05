import NanobrewKit
import SwiftUI

/// mockups/Discover.dc.html: results of the top-bar search, the selected result's detail, install options in plain
/// words with the flag after them (DD6), and Install from a tap.
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    /// The text of the top-bar search field.
    let query: String
    /// Return in the top-bar field: search again.
    let submits: Int
    @State private var results: [SearchResult]?
    @State private var error: String?
    @State private var searched: (query: String, time: Duration)?
    /// The detail pane's width: the mockup's at start, then where the user drags it.
    @State private var detailWidth: CGFloat = 420
    @State private var selection: SearchResult?
    @State private var tapName = ""
    @State private var tapCask = false
    @State private var shims = false
    @State private var trustedOnly = false
    @State private var trusted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Discover") { Text(subline) }
                Group {
                    if let error {
                        Text(error).foregroundStyle(Theme.negative).textSelection(.enabled)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) { ForEach(results ?? [], id: \.self) { row($0).id($0) } }
                        }
                        .modifier(ArrowSelection(selection: $selection, items: results ?? []))
                    }
                }
                .padding(.top, 16)
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            ResizeEdge(axis: .horizontal, size: $detailWidth, range: 300...640)
            Group {
                if let selection {
                    PackageDetailView(package: PackageRef(name: selection.name, cask: selection.isCask),
                                      footer: AnyView(installSection(selection)))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select a result to see its details and install it.")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                            installSection(nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                    }
                }
            }
            .frame(width: detailWidth)
        }
        .task(id: "\(query)\u{0}\(submits)\u{0}\(model.commandsEnded)") { await search() }
    }

    private var subline: String {
        guard let searched else { return "Search nanobrew's formulae and casks in the field at the top." }
        let count = results?.count ?? 0
        return "\(count) \(count == 1 ? "result" : "results") for “\(searched.query)” · searched in "
            + formatDuration(searched.time)
    }

    private func row(_ r: SearchResult) -> some View {
        Button { selection = r } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    Text(r.version).font(.system(size: 13)).foregroundStyle(Theme.muted).monospacedDigit()
                    Spacer()
                    if r.installed { Pill(text: "Installed") }
                    Text(r.isCask ? "cask" : "formula").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Text(r.description).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(selection == r ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == r ? .isSelected : [])
    }

    /// Install options, the primary for the selected result, and Install from a tap.
    private func installSection(_ selected: SearchResult?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Install options").font(.system(size: 14, weight: .semibold)).padding(.bottom, 6)
                option("Keep dependency tools private", flag: "--shims", isOn: $shims)
                option("Only verified packages", flag: "--trusted-only", isOn: $trustedOnly)
                option("Newest verified build", flag: "@trusted", isOn: $trusted)
            }
            .padding(.top, 4)
            if let selected {
                let busy = installing(selected.name)
                Button(busy ? "Installing \(selected.name)…" : "Install \(selected.name)") {
                    install(selected.name, cask: selected.isCask)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Install from a tap").font(.system(size: 13, weight: .medium))
                HStack(spacing: 0) {
                    TextField("user/tap/name", text: $tapName).textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).frame(height: 32)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6)
                            .strokeBorder(Theme.control))
                        .onSubmit { if !tapName.isEmpty { install(tapName, cask: tapCask) } }
                    Button("Install") { install(tapName, cask: tapCask) }
                        .buttonStyle(TapButtonStyle())
                        .disabled(tapName.isEmpty)
                }
                Toggle("It is a cask", isOn: $tapCask).toggleStyle(.checkbox).tint(Theme.primary).font(.system(size: 13))
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Theme.text)
    }

    private func option(_ words: String, flag: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(words)
                Text(flag).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            }
            .font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .tint(Theme.primary)
        .frame(minHeight: 26)
    }

    /// True while an install of `name` (with any options) runs or waits.
    private func installing(_ name: String) -> Bool {
        (model.inProgress + model.waiting).contains {
            $0.verb == "install" && $0.names == [name]
        }
    }

    private func search() async {
        guard !query.isEmpty else { results = nil; error = nil; searched = nil; return }
        // A short pause while the user types; a newer query cancels this task.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let q = query
        let start = ContinuousClock.now
        do {
            let rows = try await model.search(q)
            guard !Task.isCancelled else { return }
            results = rows
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = nil
            self.error = error.localizedDescription
        }
        searched = (q, ContinuousClock.now - start)
    }

    private func install(_ name: String, cask: Bool) {
        model.request(.install(name, cask: cask, shims: shims, trustedOnly: trustedOnly, trusted: trusted))
    }
}

/// The right half of the tap field's joined button.
private struct TapButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Theme.sheet, in: UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
            .overlay(UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6).strokeBorder(Theme.control))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
