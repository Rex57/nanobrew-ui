import AppKit
import NanobrewKit
import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.inProgress.isEmpty ? "Console" : "Running: " + model.inProgress.map(\.title).joined(separator: ", "))
                    .font(.headline)
                if !model.waiting.isEmpty { Text("\(model.waiting.count) waiting").foregroundStyle(.secondary) }
                Spacer()
                Button { model.consolePinned.toggle() } label: {
                    IconView(icon: .pin, size: 14)
                        .foregroundStyle(model.consolePinned ? Theme.text : Theme.muted)
                        .frame(width: 24, height: 24)
                        .background(model.consolePinned ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.consolePinned ? "Unpin: close the console after a command" : "Pin: keep the console open after a command")
                .accessibilityLabel("Pin console")
                .accessibilityAddTraits(model.consolePinned ? .isSelected : [])
                Button("Cancel") { model.cancel() }.disabled(!model.canCancel)
            }
            .padding(6)
            Divider()
            ConsoleText(lines: model.console)
        }
    }
}

/// An NSTextView that only appends the new lines: long output stays fast and a drag selects across lines.
struct ConsoleText: NSViewRepresentable {
    let lines: [String]

    final class Coordinator { var shown = 0 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let shown = context.coordinator.shown
        guard lines.count > shown, let textView = scrollView.documentView as? NSTextView else { return }
        let text = (shown == 0 ? "" : "\n") + lines[shown...].joined(separator: "\n")
        textView.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]))
        context.coordinator.shown = lines.count
        textView.scrollToEndOfDocument(nil)
    }
}

/// DD4: the dot (green success, red failure, amber while running), the last result, its time of day and the
/// console toggle.
struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if let status = model.status {
                Circle().fill(color(status.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(status.text).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Text("· " + status.time.formatted(date: .omitted, time: .shortened))
            }
            Spacer()
            Button { model.toggleConsole() } label: {
                HStack(spacing: 6) {
                    IconView(icon: .terminal, size: 14)
                    Text("Console")
                    Text("⌘J")
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(model.consoleShown ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.consoleShown ? "Hide console" : "Show console")
        }
        .font(.system(size: 12)).monospacedDigit()
        .foregroundStyle(Theme.muted)
        .padding(.leading, 24).padding(.trailing, 12)
        .frame(height: 36)
        .overlay(alignment: .top) { Theme.border.frame(height: 1) }
    }

    private func color(_ kind: CommandStatus.Kind) -> Color {
        switch kind {
        case .running: Theme.amber
        case .success: Theme.positive
        case .failure: Theme.negative
        case .cancelled, .skipped: Theme.muted
        }
    }
}
