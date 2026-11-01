import NanobrewKit
import SwiftUI

/// mockups/Updates.dc.html and Reinstall.dc.html.
struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    /// The text of the top-bar search field.
    let filter: String
    /// The row whose Reinstall dialog is open; the dialog belongs to the window's root (ContentView).
    @Binding var reinstalling: OutdatedPackage?

    /// One source with the sidebar count and Installed: the model's last outdated check.
    private var rows: [OutdatedPackage]? { model.outdatedChecked && model.outdatedError == nil ? model.outdatedPackages : nil }
    private var error: String? { model.outdatedError }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ScreenTitle(title: "Updates") { Text(subline) }
                HStack(spacing: 16) {
                    Button("Check Again") { Task { await model.refresh() } }
                    Button("Upgrade All") { model.request(.upgradeAll) }
                        .help("nb upgrade: every outdated formula and cask that nb can upgrade")
                    Button("Upgrade All Casks") { if let command = model.upgradeAllCasks(rows ?? []) { model.request(command) } }
                        .disabled(model.upgradeAllCasks(rows ?? []) == nil)
                        .help("The casks that are ready; never one that needs a reinstall")
                }
                .buttonStyle(TextButtonStyle(color: Theme.muted))
                .padding(.top, 6)
                let ready = model.readyUpdates(rows ?? []).count
                Button("Upgrade \(ready)") { model.upgradeReady(rows ?? []).forEach { model.request($0) } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(ready == 0)
            }
            if let error {
                Text(error).foregroundStyle(Theme.negative).textSelection(.enabled).padding(.top, 20)
                Spacer()
            } else if let rows {
                if rows.isEmpty {
                    Text("All packages are up to date.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    UpdateRow(name: Text("Package"), kind: Text("Kind"), from: Text("Installed"), to: Text("Available")) {
                        Text("Status")
                    } action: {
                        Text("Action")
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(height: 36).padding(.top, 20)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) },
                                    id: \.self, content: row)
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Each visit checks again, as in the parent run; the model's one list keeps the sidebar count the same.
        .task { await model.checkOutdated() }
    }

    /// "4 updates: 2 ready, 1 pinned, 1 needs a reinstall"; parts at 0 are left out.
    private var subline: String {
        guard let rows, !rows.isEmpty else { return rows == nil ? " " : "Nothing to upgrade" }
        let ready = model.readyUpdates(rows).count
        let pinned = rows.filter(\.pinned).count
        let reinstall = rows.count - ready - pinned
        let parts = [ready > 0 ? "\(ready) ready" : nil, pinned > 0 ? "\(pinned) pinned" : nil,
                     reinstall > 0 ? "\(reinstall) \(reinstall == 1 ? "needs" : "need") a reinstall" : nil]
        return "\(rows.count) \(rows.count == 1 ? "update" : "updates"): " + parts.compactMap { $0 }.joined(separator: ", ")
    }

    private func row(_ row: OutdatedPackage) -> some View {
        let reason = row.pinned ? nil : model.verdict(for: row)
        return UpdateRow(name: Text(row.name).fontWeight(.medium),
                         kind: Text(row.isCask ? "cask" : "formula").font(.system(size: 13)).foregroundStyle(Theme.muted),
                         from: Text(row.installed).foregroundStyle(Theme.muted),
                         to: Text(row.latest).fontWeight(.medium).foregroundStyle(row.pinned ? Theme.muted : Theme.amberText)) {
            if row.pinned {
                Pill(text: "Pinned, skipped", height: 22)
            } else if let reason {
                HStack(spacing: 6) {
                    IconView(icon: .triangleAlert, size: 14)
                    Text("Can't upgrade in place" + (UnsupportedSkip.plain(reason).map { ": \($0)" } ?? "")).lineLimit(1)
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.amberText)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Theme.amberBg, in: RoundedRectangle(cornerRadius: 4))
                .help("nb: \(reason)")
            } else {
                Text("Ready").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        } action: {
            if row.pinned {
                Button("Unpin") { model.request(.unpin(row.name)) }
                    .buttonStyle(TextButtonStyle())
            } else if reason != nil {
                Button("Reinstall…") { reinstalling = row }.buttonStyle(OutlinedButtonStyle())
                    .disabled(model.reinstalling.contains(row.name))
            } else {
                Button("Upgrade") { model.request(row.isCask ? .upgradeCask(row.name) : .upgrade(row.name)) }
                    .buttonStyle(OutlinedButtonStyle())
            }
        }
        .font(.system(size: 14)).foregroundStyle(Theme.text)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

/// The Updates columns: Package (the most width), Kind, Installed and Available (right-aligned), Status, Action.
struct UpdateRow<Status: View, Action: View>: View {
    let name: Text
    let kind: Text
    let from: Text
    let to: Text
    @ViewBuilder let status: Status
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 16) {
            name.lineLimit(1).frame(minWidth: 80, maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            kind.frame(width: 72, alignment: .leading)
            from.lineLimit(1).frame(width: 110, alignment: .trailing)
            to.lineLimit(1).frame(width: 110, alignment: .trailing)
            HStack { status }.frame(width: 290, alignment: .leading)
            HStack { action }.frame(width: 116, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, 12)
    }
}

/// D32, mockups/Reinstall.dc.html: says the cask is removed first and stays removed if the install fails. Cancel
/// is the default; "Remove and Reinstall" is outlined in the negative colour.
struct ReinstallDialog: View {
    @Environment(AppModel.self) private var model
    let row: OutdatedPackage
    let close: () -> Void

    /// The mockup's words for a disk image; nb's own reason otherwise.
    private var why: String {
        let reason = model.verdict(for: row) ?? "unsupported"
        return UnsupportedSkip.plain(reason) == "disk image"
            ? "nb can't upgrade \(row.name) in place, because it comes as a disk image."
            : "nb can't upgrade \(row.name) in place: \(reason)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconView(icon: .triangleAlert, size: 20).foregroundStyle(Theme.amber)
                Text("Reinstall \(row.name)?").font(.system(size: 16, weight: .semibold))
            }
            Text(why + " Reinstall removes \(row.name) \(row.installed) first, then installs \(row.latest).")
            Text("If the install fails, for example with no network, \(row.name) stays removed until you install it "
                 + "again. Your settings in ~/Library stay.")
            Text("Quit \(row.name) before you continue.").fontWeight(.semibold)
            HStack(spacing: 8) {
                Spacer()
                Button("Remove and Reinstall") {
                    close()
                    model.reinstall(row.name)
                }
                .buttonStyle(OutlinedButtonStyle(color: Theme.negative, border: Theme.negative, height: 32))
                Button("Cancel", action: close)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0)
            }
            .padding(.top, 4)
        }
        .font(.system(size: 13)).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.text)
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))
        .frame(width: 460)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 16)
        .padding(.top, 132)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { Theme.scrim.contentShape(Rectangle()).onTapGesture(perform: close) }
        .accessibilityAddTraits(.isModal)
    }
}
