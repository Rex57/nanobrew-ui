import NanobrewKit
import SwiftUI

/// Services in the theme (app-screens.md §7): h1, a subline about the data, a table with one status pill per row.
struct ServicesView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var rows: [Service]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle(title: "Services") { Text(subline) }
            if let error {
                Text(error).foregroundStyle(Theme.negative).textSelection(.enabled).padding(.top, 20)
                Spacer()
            } else if let rows {
                if rows.isEmpty {
                    Text("No service runs here. A formula that has a service shows up once it is installed.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    row(name: Text("Name"), formula: Text("Formula")) { Text("Status") } actions: { Text("Actions") }
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).frame(height: 36).padding(.top, 20)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows, id: \.self) { service in
                                row(name: Text(service.name).fontWeight(.medium),
                                    formula: Text(service.formula).foregroundStyle(Theme.muted)) {
                                    StatusPill(running: service.running)
                                } actions: {
                                    Button("Start") { model.request(.services(.start, service.name)) }
                                    Button("Stop") { model.request(.services(.stop, service.name)) }
                                    Button("Restart") { model.request(.services(.restart, service.name)) }
                                }
                                .font(.system(size: 14)).foregroundStyle(Theme.text)
                                .frame(height: 44)
                                .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 0, trailing: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .onChange(of: model.running) { _, running in if running == nil { Task { await load() } } }
    }

    private var subline: String {
        guard let rows else { return error == nil ? " " : "The service list did not load" }
        guard !rows.isEmpty else { return "No services" }
        let running = rows.filter(\.running).count
        return "\(rows.count) \(rows.count == 1 ? "service" : "services"), \(running) running"
    }

    private func row(name: Text, formula: Text, @ViewBuilder status: () -> some View,
                     @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 16) {
            name.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            formula.lineLimit(1).frame(width: 200, alignment: .leading)
            HStack { status() }.frame(width: 110, alignment: .leading)
            HStack(spacing: 16) { actions() }.buttonStyle(TextButtonStyle()).frame(width: 200, alignment: .trailing)
        }
        .padding(.horizontal, 12)
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

/// running: the positive pale pair; stopped: neutral. nb's list knows no error state (Service.parse).
struct StatusPill: View {
    let running: Bool

    var body: some View {
        Text(running ? "Running" : "Stopped")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(running ? Theme.positive : Theme.pillInk)
            .padding(.horizontal, 8).frame(height: 20)
            .background(running ? Theme.positiveBg : Theme.pillBg, in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }
}
