import NanobrewKit
import SwiftUI

@main
struct NanobrewUIApp: App {
    @State private var model = AppModel.fromLaunch()

    var body: some Scene {
        WindowGroup("Nanobrew UI") {
            ContentView()
                .environment(model)
                .onAppear { model.reload() }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case installed = "Installed"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section? = .installed

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { Text($0.rawValue).tag($0) }
        } detail: {
            VStack(spacing: 0) {
                if let error = model.stateError {
                    Text(error).foregroundStyle(.red).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                switch section {
                case .installed, nil: InstalledView()
                }
            }
        }
    }
}
