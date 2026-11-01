import NanobrewKit
import SwiftUI

struct ServicesView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var rows: [Service]?

    var body: some View {
        Group {
            if let error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding()
            } else if let rows {
                if rows.isEmpty {
                    ContentUnavailableView("No services found", systemImage: "gearshape.2")
                } else {
                    List(rows, id: \.self) { row in
                        HStack {
                            Text(row.name)
                            Text(row.formula).foregroundStyle(.secondary)
                            Text(row.running ? "running" : "stopped").foregroundStyle(row.running ? .green : .secondary)
                            Spacer()
                            Button("Start") { model.request(.services(.start, row.name)) }
                            Button("Stop") { model.request(.services(.stop, row.name)) }
                            Button("Restart") { model.request(.services(.restart, row.name)) }
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
            rows = try await model.services()
            error = nil
        } catch {
            rows = nil
            self.error = error.localizedDescription
        }
    }
}
