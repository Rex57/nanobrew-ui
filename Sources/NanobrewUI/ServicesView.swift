import NanobrewKit
import SwiftUI

/// Services in the theme (app-screens.md §7): h1, a subline about the data, a table with one status pill per row.
struct ServicesView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var rows: [Service]?
    /// Retry bumps it: a new load starts.
    @State private var retries = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle(title: "Services") { Text(subline) }
            if rows == nil, let running = model.running {
                // D5: nb's lock holds a read behind the app's own command; the list loads when it ends.
                Text("Waiting for \(running.title) to end").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(error).foregroundStyle(Theme.negative).textSelection(.enabled)
                    Button("Retry") { self.error = nil; retries += 1 }.buttonStyle(TextButtonStyle())
                }
                .padding(.top, 20)
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
                        LazyVStack(alignment: .leading, spacing: 0) {
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
        // D6(5): the loaded rows fade in instead of popping.
        .animation(Motion.fade, value: rows == nil)
        // No load while the app's own changing command runs (D5); its end changes `commandsEnded`.
        .task(id: model.running == nil ? [model.commandsEnded, retries] : []) {
            guard model.running == nil else { return }
            await load()
        }
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
        .frame(maxWidth: 760, alignment: .leading) // app-screens §4.2: a short table keeps its columns close
    }

    private func load() async {
        // A newer command end cancelled this load: keep what shows until the newer one ends.
        do {
            let fresh = try await model.services()
            guard !Task.isCancelled else { return }
            rows = fresh
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
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
