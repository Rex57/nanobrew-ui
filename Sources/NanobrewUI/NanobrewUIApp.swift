import AppKit
import NanobrewKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.fromLaunch()

    func applicationDidBecomeActive(_ notification: Notification) { model.reload() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.askBeforeQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A command is still running"
        alert.informativeText = "Quit now and nb may stop half done."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct NanobrewUIApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Nanobrew UI") {
            ContentView().environment(delegate.model)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") { delegate.model.reload() }.keyboardShortcut("r")
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case maintenance = "Maintenance"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section? = .installed

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { Text($0.rawValue).tag($0) }
        } detail: {
            VSplitView {
                VStack(spacing: 0) {
                    if let error = model.stateError {
                        Text(error).foregroundStyle(.red).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    switch section {
                    case .installed, nil: InstalledView()
                    case .maintenance: MaintenanceView()
                    }
                }
                .frame(minHeight: 200, maxHeight: .infinity)
                ConsoleView().frame(minHeight: 120, idealHeight: 180)
            }
        }
    }
}

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Button("Doctor") { model.run(.doctor) }.disabled(model.inProgress.contains(.doctor))
        }
        .formStyle(.grouped)
    }
}
