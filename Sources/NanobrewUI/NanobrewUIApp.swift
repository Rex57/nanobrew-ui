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
        alert.messageText = model.reinstalling.isEmpty ? "A command is still running" : "A reinstall is not finished"
        alert.informativeText = model.quitMessage
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
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutMenuItem() }
            CommandGroup(after: .toolbar) {
                Button("Reload") { Task { await delegate.model.refresh() } }
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
    /// The top-bar search field; each section that has one reads it, and a section change clears it.
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// The Updates row whose Reinstall dialog is open: it covers the whole window, as in Reinstall.dc.html.
    @State private var reinstalling: OutdatedPackage?

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
                .overlay { if let prompt = (section ?? .installed).searchPrompt { searchField(prompt) } }
                .background {
                    // Cmd-F focuses the top-bar search field.
                    Button("Find") { searchFocused = true }.keyboardShortcut("f").opacity(0).accessibilityHidden(true)
                }
                // The sheet (DD11): inset 8px from the right and bottom edges, 16px corners, a 1px edge, no shadow.
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if model.restartOffered {
                                HStack(spacing: 12) {
                                    Text("Restart to use the new version").foregroundStyle(Theme.amberText)
                                    Button("Restart", action: relaunch).buttonStyle(OutlinedButtonStyle())
                                }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 24).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading).background(Theme.amberBg)
                            }
                            if let error = model.stateError {
                                Text(error).font(.system(size: 13)).foregroundStyle(Theme.negative).textSelection(.enabled)
                                    .padding(.horizontal, 24).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
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
                        // The mockup's console: 212px under a 1px edge.
                        if model.consoleShown {
                            ConsoleView().frame(height: 212).overlay(alignment: .top) { Theme.border.frame(height: 1) }
                        }
                    }
                    if !model.consoleShown { StatusLine() }
                }
                .background(Theme.sheet)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
                .padding(.trailing, 8).padding(.bottom, 8)
            }
        }
        .background(Theme.frame)
        .overlay { if let reinstalling { ReinstallDialog(row: reinstalling) { self.reinstalling = nil } } }
        .ignoresSafeArea()
        .task { await model.checkOutdated(report: true) }
        .onChange(of: section) { query = "" }
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

    private func checkAgain() { Task { await model.refresh() } }

    private func searchField(_ prompt: String) -> some View {
        HStack(spacing: 8) {
            IconView(icon: .search, size: 14)
            TextField(prompt, text: $query).textFieldStyle(.plain).font(.system(size: 13))
                .foregroundStyle(Theme.text).focused($searchFocused)
            Text("⌘F").font(.system(size: 12))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 10)
        .frame(width: 400, height: 32)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.control))
    }

    @ViewBuilder private var sectionView: some View {
        switch section {
        case .installed, nil: InstalledView(filter: query, section: $section)
        case .updates: UpdatesView(filter: query, reinstalling: $reinstalling)
        case .discover: DiscoverView(query: query)
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
        VStack(alignment: .leading, spacing: 16) {
            ScreenTitle(title: "nanobrew is not installed") { Text("Install it in Terminal, then press ⌘R.") }
            Text(verbatim: "curl -fsSL https://nanobrew.trilok.ai/install | bash")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            Text("If nb is in another place, set its path in Settings.").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct NotSetUpView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenTitle(title: "nanobrew is not set up") {
                Text("Set-up runs nb init as administrator; macOS asks for your password.")
            }
            Button("Set up nanobrew") {
                if let nb = model.nbPath { model.request(.initNanobrew(nbPath: nb)) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.askBeforeQuit)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
