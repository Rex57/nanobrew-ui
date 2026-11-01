import NanobrewKit
import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [SearchResult]?
    @State private var selection: SearchResult?
    @State private var tapName = ""
    @State private var tapCask = false
    @State private var shims = false
    @State private var trustedOnly = false
    @State private var trusted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Search formulae and casks", text: $query).onSubmit(search)
                Button("Search", action: search).disabled(query.isEmpty)
            }
            .padding(8)
            HStack {
                Toggle("--shims", isOn: $shims)
                Toggle("--trusted-only", isOn: $trustedOnly)
                Toggle("@trusted", isOn: $trusted)
                Spacer()
                TextField("user/tap/name", text: $tapName).frame(maxWidth: 220)
                Toggle("Cask", isOn: $tapCask)
                Button("Install from tap") { install(tapName, cask: tapCask) }.disabled(tapName.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            Divider()
            HSplitView {
                Group {
                    if let results, results.isEmpty {
                        ContentUnavailableView("No results", systemImage: "magnifyingglass")
                    } else {
                        List(results ?? [], id: \.self, selection: $selection) { r in
                            HStack {
                                Text(r.name)
                                Text(r.version).foregroundStyle(.secondary)
                                Text(r.isCask ? "cask" : "formula").foregroundStyle(.secondary)
                                if r.installed { Text("installed").foregroundStyle(.green) }
                                Text(r.description).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(minWidth: 260, maxHeight: .infinity)
                VStack(alignment: .leading) {
                    if let selection {
                        Button("Install \(selection.name)") { install(selection.name, cask: selection.isCask) }
                            .padding([.top, .horizontal])
                        PackageDetailView(package: PackageRef(name: selection.name, cask: selection.isCask))
                    } else {
                        ContentUnavailableView("Select a result", systemImage: "shippingbox")
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func search() {
        guard !query.isEmpty else { return }
        let q = query
        Task { results = await model.search(q) }
    }

    private func install(_ name: String, cask: Bool) {
        model.request(.install(name, cask: cask, shims: shims, trustedOnly: trustedOnly, trusted: trusted))
    }
}
