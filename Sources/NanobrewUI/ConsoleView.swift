import AppKit
import NanobrewKit
import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // mockups/Discover.dc.html: a 40px header (dot, what runs, its time, Cancel, Keep open, hide), the output in
        // 12px SF Mono on the sheet. The status line hides while the console shows.
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let status = model.status {
                    Circle().fill(StatusLine.color(status.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
                }
                Text(model.inProgress.isEmpty ? model.status?.text ?? "Console"
                     : "Running: " + model.inProgress.map(\.title).joined(separator: ", "))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    .truncationMode(.middle)
                if let status = model.status, status.kind == .running {
                    // The time since the command started, as the status line would show it at the end.
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(formatDuration(.seconds(context.date.timeIntervalSince(status.time))))
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                } else if let status = model.status {
                    Text(status.time.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                if !model.waiting.isEmpty {
                    Text("\(model.waiting.count) waiting").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Cancel") { model.cancel() }
                    .buttonStyle(OutlinedButtonStyle(height: 26)).font(.system(size: 12, weight: .medium))
                    .disabled(!model.canCancel)
                Button("Keep open") { model.consolePinned.toggle() }
                    .buttonStyle(TextButtonStyle(color: model.consolePinned ? Theme.text : Theme.muted))
                    .font(.system(size: 12, weight: model.consolePinned ? .semibold : .regular))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(model.consolePinned ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .help("Keep the console open after a command")
                    .accessibilityAddTraits(model.consolePinned ? .isSelected : [])
                Button { model.toggleConsole() } label: {
                    IconView(icon: .chevronDown).foregroundStyle(Theme.muted).frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide console (⌘J)")
                .accessibilityLabel("Hide console")
            }
            .padding(.leading, 24).padding(.trailing, 12)
            .frame(height: 40)
            ConsoleText(lines: model.console)
        }
        .background(Theme.sheet)
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
        // On the sheet's colour, 24px from the edge, as in the mockup.
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 19, height: 0)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let shown = context.coordinator.shown
        guard lines.count > shown, let textView = scrollView.documentView as? NSTextView else { return }
        let text = (shown == 0 ? "" : "\n") + lines[shown...].joined(separator: "\n")
        textView.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
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
                Circle().fill(Self.color(status.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
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

    static func color(_ kind: CommandStatus.Kind) -> Color {
        switch kind {
        case .running: Theme.amber
        case .success: Theme.positive
        case .failure: Theme.negative
        case .cancelled, .skipped: Theme.muted
        }
    }
}
