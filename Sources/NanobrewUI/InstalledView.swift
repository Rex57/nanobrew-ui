import NanobrewKit
import SwiftUI

struct InstalledView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        if model.notSetUp {
            ContentUnavailableView("nanobrew is not set up", systemImage: "shippingbox")
        } else {
            let snapshot = model.snapshot
            let match = { (name: String) in filter.isEmpty || name.localizedCaseInsensitiveContains(filter) }
            List {
                SwiftUI.Section("Formulae") {
                    ForEach((snapshot?.formulae ?? []).filter { match($0.name) }) { f in
                        PackageRow(name: f.name, version: f.version, pinned: f.pinned)
                    }
                }
                SwiftUI.Section("Casks") {
                    ForEach((snapshot?.casks ?? []).filter { match($0.token) }) { c in
                        PackageRow(name: c.token, version: c.version, pinned: false)
                    }
                }
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
