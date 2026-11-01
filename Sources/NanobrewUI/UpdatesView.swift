import NanobrewKit
import SwiftUI

struct UpdatesView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var rows: [OutdatedPackage]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Check Again") { Task { await load() } }
                Spacer()
                Button("Upgrade All") { model.request(.upgradeAll) }
                Button("Upgrade All Casks") { model.request(.upgradeAllCasks) }
            }
            .padding(8)
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding()
            } else if let rows {
                if rows.isEmpty {
                    ContentUnavailableView("All packages are up to date", systemImage: "checkmark.circle")
                } else {
                    List(rows, id: \.self) { row in
                        HStack {
                            Text(row.name)
                            Text("\(row.installed) → \(row.latest)").foregroundStyle(.secondary)
                            if row.isCask { Text("cask").foregroundStyle(.secondary) }
                            if row.pinned { Label("pinned", systemImage: "pin.fill").foregroundStyle(.orange) }
                            Spacer()
                            Button("Upgrade") { model.request(row.isCask ? .upgradeCask(row.name) : .upgrade(row.name)) }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .onChange(of: model.running) { _, running in if running == nil { Task { await load() } } }
    }

    private func load() async {
        do {
            rows = try await model.outdated()
            error = nil
        } catch {
            rows = nil
            self.error = error.localizedDescription
        }
    }
}
