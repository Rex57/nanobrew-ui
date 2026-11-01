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
