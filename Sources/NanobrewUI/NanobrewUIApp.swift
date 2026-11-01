import AppKit
import NanobrewKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.fromLaunch()

    func applicationDidBecomeActive(_ notification: Notification) { model.reload() }

    private var quitConfirmed = false
    private var closeGuard: CloseGuard?

    /// Asks first while a changing command runs or waits; true when the app may quit.
    func mayQuit() -> Bool {
        guard model.askBeforeQuit, !quitConfirmed else { return true }
        let alert = NSAlert()
        alert.messageText = "A command is still running"
        alert.informativeText = "Quit now and nb may stop half done."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        quitConfirmed = alert.runModal() == .alertSecondButtonReturn
        return quitConfirmed
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mayQuit() ? .terminateNow : .terminateCancel
    }

    /// Closing the window quits the app (D29), so the close asks first too.
    func guardClose(of window: NSWindow) {
        guard closeGuard?.window !== window else { return }
        closeGuard = CloseGuard(window: window) { [unowned self] in mayQuit() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct NanobrewUIApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("Nanobrew UI") {
            ContentView().environment(delegate.model)
                .background(WindowReader { delegate.guardClose(of: $0) })
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Reload") { delegate.model.reload() }.keyboardShortcut("r")
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case updates = "Updates"
    case discover = "Discover"
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
                    if model.restartOffered {
                        HStack {
                            Text("Restart to use the new version")
                            Button("Restart", action: relaunch)
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2))
                    }
                    if let error = model.stateError {
                        Text(error).foregroundStyle(.red).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    switch section {
                    case .installed, nil: InstalledView()
                    case .updates: UpdatesView()
                    case .discover: DiscoverView()
                    case .maintenance: MaintenanceView()
                    }
                }
                .frame(minHeight: 200, maxHeight: .infinity)
                ConsoleView().frame(minHeight: 120, idealHeight: 180)
            }
        }
        .alert(model.pendingConfirmation.map { "Run \($0.title)?" } ?? "",
               isPresented: Binding(get: { model.pendingConfirmation != nil }, set: { if !$0 { model.decline() } })) {
            Button("Run", role: .destructive) { model.confirm() }
            Button("Cancel", role: .cancel) { model.decline() }
        } message: {
            Text("This changes your system.")
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

/// Opens the app bundle again as a new copy (the upgraded one nb put in place) and quits this one.
@MainActor func relaunch() {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-n", Bundle.main.bundlePath]
    try? open.run()
    open.waitUntilExit()
    NSApp.terminate(nil)
}
