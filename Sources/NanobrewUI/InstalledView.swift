import NanobrewKit
import SwiftUI

/// A package picked in a list: a formula by name or a cask by token.
struct PackageRef: Hashable {
    let name: String
    let cask: Bool
}

/// mockups/Main.dc.html: title and subline, Formulae and Casks tabs, the table, the detail pane.
struct InstalledView: View {
    @Environment(AppModel.self) private var model
    /// The text of the top-bar search field.
    let filter: String
    @Binding var section: Section?
    @State private var casks = false
    @State private var selection: PackageRef?

    var body: some View {
        let snapshot = model.snapshot
        let match = { (name: String) in filter.isEmpty || name.localizedCaseInsensitiveContains(filter) }
        let formulae = snapshot?.formulae ?? []
        let caskList = snapshot?.casks ?? []
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Installed") {
                    HStack(spacing: 0) {
                        Text("\(formulae.count) formulae · \(caskList.count) casks")
                        if let count = model.updatesCount {
                            Text(" · ")
                            Button("\(count) \(count == 1 ? "update" : "updates") waiting") { section = .updates }
                                .buttonStyle(TextButtonStyle(color: Theme.amberText))
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                HStack(spacing: 24) {
                    tab("Formulae", count: formulae.count, selected: !casks) { casks = false }
                    tab("Casks", count: caskList.count, selected: casks) { casks = true }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
                .padding(.top, 16)
                TableRow(name: Text("Name"), version: Text("Version"), date: Text("Installed"), status: Text("Status"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(height: 36)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if casks {
                            ForEach(caskList.filter { match($0.token) }) { c in
                                row(PackageRef(name: c.token, cask: true), version: c.version, date: "", pinned: false)
                            }
                        } else {
                            ForEach(formulae.filter { match($0.name) }) { f in
                                row(PackageRef(name: f.name, cask: false), version: f.version,
                                    date: isoDate(f.installedAt), pinned: f.pinned)
                            }
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Theme.border.frame(width: 1)
            Group {
                if let selection { PackageDetailView(package: selection) } else {
                    Text("Select a package to see its details.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 400)
        }
        .onChange(of: model.snapshot) { _, snapshot in
            // A removed package leaves the detail pane.
            guard let selected = selection else { return }
            let present = selected.cask ? snapshot?.casks.contains { $0.token == selected.name }
                                        : snapshot?.formulae.contains { $0.name == selected.name }
            if present != true { selection = nil }
        }
    }

    private func tab(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).fontWeight(selected ? .semibold : .regular)
                Text("\(count)").foregroundStyle(Theme.muted).monospacedDigit()
            }
            .font(.system(size: 14))
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            .frame(height: 36)
            .overlay(alignment: .bottom) { (selected ? Theme.amber : .clear).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ ref: PackageRef, version: String, date: String, pinned: Bool) -> some View {
        let update = model.outdatedPackages.first { $0.name == ref.name && $0.isCask == ref.cask }
        return Button { selection = ref } label: {
            TableRow(name: Text(ref.name).fontWeight(.medium), version: Text(version),
                     date: Text(date).font(.system(size: 13)).foregroundStyle(Theme.muted)) {
                if pinned {
                    Pill(text: "Pinned")
                } else if let update {
                    HStack(spacing: 6) {
                        IconView(icon: .circleArrowUp, size: 14)
                        Text("Update \(update.latest)")
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.amberText)
                }
            }
            .font(.system(size: 14)).foregroundStyle(Theme.text)
            .frame(height: 44)
            .background(selection == ref ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == ref ? .isSelected : [])
    }
}

/// The Installed table's columns: Name (the most width), Version, Installed (both right-aligned), Status.
struct TableRow<Status: View>: View {
    let name: Text
    let version: Text
    let date: Text
    @ViewBuilder let status: Status

    init(name: Text, version: Text, date: Text, @ViewBuilder status: () -> Status) {
        self.name = name
        self.version = version
        self.date = date
        self.status = status()
    }

    var body: some View {
        HStack(spacing: 16) {
            name.lineLimit(1).truncationMode(.tail).frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            version.lineLimit(1).frame(width: 130, alignment: .trailing)
            date.lineLimit(1).frame(width: 110, alignment: .trailing)
            HStack { status }.frame(width: 150, alignment: .leading)
        }
        .monospacedDigit()
        .padding(.horizontal, 12)
    }
}

extension TableRow where Status == Text {
    init(name: Text, version: Text, date: Text, status: Text) {
        self.init(name: name, version: version, date: date) { status }
    }
}

/// Info and dependency tree of one package, from nb, in the mockup's order. Discover reuses it.
struct PackageDetailView: View {
    @Environment(AppModel.self) private var model
    let package: PackageRef
    @State private var detail: PackageDetail?

    private var formula: Formula? { package.cask ? nil : model.snapshot?.formulae.first { $0.name == package.name } }
    private var installed: Bool {
        package.cask ? model.snapshot?.casks.contains { $0.token == package.name } == true : formula != nil
    }
    private var update: OutdatedPackage? {
        model.outdatedPackages.first { $0.name == package.name && $0.isCask == package.cask && !$0.pinned }
    }

    @ViewBuilder private var actions: some View {
        if let update {
            Button("Upgrade to \(update.latest)") {
                model.request(package.cask ? .upgradeCask(package.name) : .upgrade(package.name))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        HStack(spacing: 16) {
            if let formula {
                Button(formula.pinned ? "Unpin" : "Pin") {
                    model.request(formula.pinned ? .unpin(formula.name) : .pin(formula.name))
                }
                Button("Link") { model.request(.link(formula.name)) }
                Button("Unlink") { model.request(.unlink(formula.name)) }
            }
            Spacer()
            Button("Remove…") { model.request(package.cask ? .removeCask(package.name) : .remove(package.name)) }
                .buttonStyle(TextButtonStyle(color: Theme.negative))
        }
        .buttonStyle(TextButtonStyle())
    }

    @ViewBuilder private var versions: some View {
        if let formula, let earlier = model.snapshot?.earlierVersions(of: formula.name), let last = earlier.last {
            HStack(alignment: .firstTextBaseline) {
                Text("Earlier versions").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Roll back to \(last)") { model.request(.rollback(formula.name)) }
            }
            .padding(.top, 6)
            VStack(spacing: 0) {
                let entries = (model.snapshot?.history[formula.name] ?? []).filter { $0.version != formula.version }
                ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 12) {
                        Text(entry.version).frame(maxWidth: .infinity, alignment: .leading)
                        Text(isoDate(entry.installedAt)).foregroundStyle(Theme.muted).frame(width: 90, alignment: .trailing)
                        Button("Switch") { model.request(.switchVersion(formula.name, to: entry.version)) }
                            .frame(width: 56, alignment: .trailing)
                    }
                    .font(.system(size: 13)).monospacedDigit()
                    .frame(height: 30)
                    .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
                }
            }
            .padding(.top, -6)
        }
    }

    private func field(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label).foregroundStyle(Theme.muted).frame(width: 72, alignment: .leading)
            value()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let detail {
                    if let info = detail.info {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(info.name).font(.system(size: 18, weight: .semibold))
                            Text(info.version).font(.system(size: 14)).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        if !info.description.isEmpty { Text(info.description).font(.system(size: 14)).padding(.top, -6) }
                        VStack(alignment: .leading, spacing: 6) {
                            if !info.homepage.isEmpty, let url = URL(string: info.homepage) {
                                field("Homepage") {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Text(url.host() ?? info.homepage)
                                            IconView(icon: .externalLink, size: 12).foregroundStyle(Theme.muted)
                                        }
                                    }
                                    .foregroundStyle(Theme.text)
                                    .help(info.homepage)
                                }
                            }
                            if !info.license.isEmpty { field("License") { Text(info.license) } }
                            if let trust = Trust(info.trust) {
                                field("Trust") {
                                    HStack(spacing: 8) {
                                        Text(trust.text).help(info.trust)
                                        if installed {
                                            Button("Probe") { model.request(.doctorProbe(package.name)) }
                                                .buttonStyle(TextButtonStyle(color: Theme.muted))
                                        }
                                    }
                                }
                            }
                        }
                        .font(.system(size: 13))
                        if installed { actions }
                        if !info.artifacts.isEmpty {
                            Text("Artifacts").font(.system(size: 14, weight: .semibold)).padding(.top, 6)
                            Text(info.artifacts.joined(separator: "\n")).font(.system(size: 13)).padding(.top, -6)
                        }
                        if let tree = detail.tree, !package.cask {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Dependencies").font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text(info.dependencies.isEmpty ? "none" : "\(info.dependencies.count) direct")
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            .padding(.top, 6)
                            if !info.dependencies.isEmpty {
                                ScrollView([.vertical, .horizontal]) {
                                    Text(tree).font(.system(size: 12, design: .monospaced)).lineSpacing(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                                }
                                .frame(maxHeight: 144)
                                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.top, -4)
                            }
                        }
                        if installed { versions }
                    } else {
                        Text(detail.error ?? "").foregroundStyle(Theme.negative)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(TextButtonStyle())
            .foregroundStyle(Theme.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .task(id: package) {
            detail = nil
            detail = await model.detail(name: package.name, cask: package.cask)
        }
        // A probe, a link or an upgrade changes what nb info says.
        .onChange(of: model.inProgress.count) { old, new in
            guard new < old else { return }
            Task { detail = await model.detail(name: package.name, cask: package.cask) }
        }
    }
}
