import AppKit
import NanobrewKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.fromLaunch()

    func applicationDidBecomeActive(_ notification: Notification) { model.checkAgain() }

    /// Test-only `-NBAppearance light|dark`: macOS ignores `-AppleInterfaceStyle Light` on a Mac set to dark.
    func applicationWillFinishLaunching(_ notification: Notification) {
        switch launchArgument("NBAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private var closeGuard: CloseGuard?

    /// Asks first while a changing command runs or waits; true when the app may quit.
    func mayQuit() -> Bool {
        guard model.askBeforeQuit else { return true }
        let alert = NSAlert()
        alert.messageText = "A command is still running"
        alert.informativeText = "nb keeps running in the background until it ends. You will not see its output."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mayQuit() ? .terminateNow : .terminateCancel
    }

    /// Closing the one main window quits the app (D29): the close becomes a quit, which asks first while a
    /// changing command runs or waits. The window itself never closes alone, so no "confirmed" state is kept.
    func guardClose(of window: NSWindow) {
        guard closeGuard?.window !== window else { return }
        closeGuard = CloseGuard(window: window) {
            NSApp.terminate(nil)
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct NanobrewUIApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // One main window (D29): a Window scene has no File > New Window.
        Window("Nanobrew UI", id: "main") {
            ContentView().environment(delegate.model)
                .background(WindowReader { delegate.guardClose(of: $0) })
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    delegate.model.checkAgain()
                    Task { await delegate.model.checkOutdated(report: true) }
                }
                .keyboardShortcut("r")
                Button("Console") { delegate.model.toggleConsole() }.keyboardShortcut("j")
            }
        }
        Window("About Nanobrew UI", id: "about") {
            AboutView().environment(delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

enum Section: String, CaseIterable, Identifiable {
    case installed = "Installed"
    case updates = "Updates"
    case discover = "Discover"
    case services = "Services"
    case maintenance = "Maintenance"
    case bundle = "Bundle"
    case settings = "Settings"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section? = .installed
    @State private var typed = ""

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section).frame(width: 228)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: checkAgain) {
                        IconView(icon: .rotateCW).foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 32)
                            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.control))
                    }
                    .buttonStyle(.plain)
                    .help("Check again (⌘R)")
                    .accessibilityLabel("Check again")
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                // The sheet (DD11): inset 8px from the right and bottom edges, 16px corners, a 1px edge, no shadow.
                VStack(spacing: 0) {
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
                            if model.notInstalled && section != .settings {
                                NotInstalledView()
                            } else if model.notSetUp && section != .settings {
                                NotSetUpView()
                            } else {
                                sectionView
                            }
                        }
                        .frame(minHeight: 200, maxHeight: .infinity)
                        if model.consoleShown { ConsoleView().frame(minHeight: 120, idealHeight: 180) }
                    }
                    StatusLine()
                }
                .background(Theme.sheet)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
                .padding(.trailing, 8).padding(.bottom, 8)
            }
        }
        .background(Theme.frame)
        .ignoresSafeArea()
        .task { await model.checkOutdated(report: true) }
        // After each command: the count on Updates may have changed.
        .onChange(of: model.inProgress) { old, new in
            if new.count < old.count { Task { await model.checkOutdated() } }
        }
        // After a command (nuke, init) left nb or the state folder gone, show the screen that says so.
        // Not on a Settings path change: the user stays there to fix a typo.
        .onChange(of: model.running) { old, new in
            if old != nil, new == nil, model.notInstalled || model.notSetUp { section = .installed }
        }
        .alert(model.pendingConfirmation.map { "Run \($0.title)?" } ?? "",
               isPresented: Binding(get: { model.pendingConfirmation != nil }, set: { if !$0 { model.decline() } })) {
            if model.pendingConfirmation?.confirmation == .typeYes {
                TextField("Type yes", text: $typed)
            }
            Button("Run", role: .destructive) {
                model.confirm(typed: typed)
                typed = ""
            }
            .disabled(model.pendingConfirmation?.confirmation == .typeYes && typed != "yes")
            Button("Cancel", role: .cancel) {
                model.decline()
                typed = ""
            }
        } message: {
            Text(model.pendingConfirmation?.confirmation == .typeYes
                 ? "This removes nanobrew and everything it installed. Type yes to go on."
                 : "This changes your system.")
        }
    }

    private func checkAgain() {
        model.checkAgain()
        Task { await model.checkOutdated(report: true) }
    }

    @ViewBuilder private var sectionView: some View {
        switch section {
        case .installed, nil: InstalledView()
        case .updates: UpdatesView()
        case .discover: DiscoverView()
        case .services: ServicesView()
        case .maintenance: MaintenanceView()
        case .bundle: BundleView()
        case .settings: SettingsView()
        }
    }
}

/// D25: the install command as selectable text; Cmd-R checks again.
struct NotInstalledView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("nanobrew is not installed").font(.title2)
            Text("Install it in Terminal:")
            Text(verbatim: "curl -fsSL https://nanobrew.trilok.ai/install | bash")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text("Then press ⌘R. If nb is in another place, set its path in Settings.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotSetUpView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Text("nanobrew is not set up").font(.title2)
            Text("Set-up runs nb init as administrator; macOS asks for your password.")
            Button("Set up nanobrew") {
                if let nb = model.nbPath { model.request(.initNanobrew(nbPath: nb)) }
            }
            .disabled(model.askBeforeQuit)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
