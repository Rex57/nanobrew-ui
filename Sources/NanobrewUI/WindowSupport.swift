import AppKit
import SwiftUI

/// Hands the hosting NSWindow to a closure once the view is in it.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found?(window) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.found = found
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// Sits in front of SwiftUI's window delegate to ask before a close; forwards everything else.
@MainActor
final class CloseGuard: NSObject, NSWindowDelegate {
    weak var window: NSWindow?
    // Set once in init; read by the Objective-C runtime on the main thread.
    nonisolated(unsafe) private weak var original: NSWindowDelegate?
    private let shouldClose: () -> Bool

    init(window: NSWindow, shouldClose: @escaping () -> Bool) {
        self.window = window
        original = window.delegate
        self.shouldClose = shouldClose
        super.init()
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        shouldClose() && (original?.windowShouldClose?(sender) ?? true)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? { original }
}
