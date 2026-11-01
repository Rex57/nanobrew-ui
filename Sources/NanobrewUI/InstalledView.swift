import NanobrewKit
import SwiftUI

/// A package picked in a list: a formula by name or a cask by token.
struct PackageRef: Hashable {
    let name: String
    let cask: Bool
}

struct InstalledView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var selection: PackageRef?

    var body: some View {
        if model.notSetUp {
            ContentUnavailableView("nanobrew is not set up", systemImage: "shippingbox")
        } else {
            let snapshot = model.snapshot
            let match = { (name: String) in filter.isEmpty || name.localizedCaseInsensitiveContains(filter) }
            HSplitView {
                List(selection: $selection) {
                    SwiftUI.Section("Formulae") {
                        ForEach((snapshot?.formulae ?? []).filter { match($0.name) }) { f in
                            PackageRow(name: f.name, version: f.version, pinned: f.pinned)
                                .tag(PackageRef(name: f.name, cask: false))
                        }
                    }
                    SwiftUI.Section("Casks") {
                        ForEach((snapshot?.casks ?? []).filter { match($0.token) }) { c in
                            PackageRow(name: c.token, version: c.version, pinned: false)
                                .tag(PackageRef(name: c.token, cask: true))
                        }
                    }
                }
                .frame(minWidth: 220)
                Group {
                    if let selection { PackageDetailView(package: selection) } else {
                        ContentUnavailableView("Select a package", systemImage: "shippingbox")
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            .searchable(text: $filter, prompt: "Filter")
        }
    }
}

struct PackageRow: View {
    let name: String
    let version: String
    let pinned: Bool

    var body: some View {
        HStack {
            Text(name)
            Text(version).foregroundStyle(.secondary)
            if pinned { Label("pinned", systemImage: "pin.fill").foregroundStyle(.orange) }
        }
    }
}

/// Info and dependency tree of one package, from nb. Discover reuses it.
struct PackageDetailView: View {
    @Environment(AppModel.self) private var model
    let package: PackageRef
    @State private var detail: PackageDetail?

    private var formula: Formula? { package.cask ? nil : model.snapshot?.formulae.first { $0.name == package.name } }
    private var installed: Bool {
        package.cask ? model.snapshot?.casks.contains { $0.token == package.name } == true : formula != nil
    }

    private var actions: some View {
        HStack {
            Button("Remove") { model.request(package.cask ? .removeCask(package.name) : .remove(package.name)) }
            if let formula {
                Button(formula.pinned ? "Unpin" : "Pin") { model.request(formula.pinned ? .unpin(formula.name) : .pin(formula.name)) }
                Button("Link") { model.request(.link(formula.name)) }
                Button("Unlink") { model.request(.unlink(formula.name)) }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if installed { actions }
                if let detail {
                    if let info = detail.info {
                        Text("\(info.name) \(info.version)").font(.title2)
                        if !info.description.isEmpty { Text(info.description) }
                        if !info.homepage.isEmpty, let url = URL(string: info.homepage) { Link(info.homepage, destination: url) }
                        if !info.trust.isEmpty { Text("Trust: \(info.trust)") }
                        if !package.cask {
                            Text("Dependencies: " + (info.dependencies.isEmpty ? "none" : info.dependencies.joined(separator: ", ")))
                        }
                        if !info.artifacts.isEmpty { Text("Artifacts:\n" + info.artifacts.joined(separator: "\n")) }
                        if let tree = detail.tree {
                            Text("Dependency tree").font(.headline)
                            Text(tree).font(.system(.body, design: .monospaced))
                        }
                    } else {
                        Text(detail.error ?? "").foregroundStyle(.red)
                    }
                } else {
                    ProgressView()
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .task(id: package) {
            detail = nil
            detail = await model.detail(name: package.name, cask: package.cask)
        }
    }
}
