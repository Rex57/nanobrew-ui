import AppKit
import NanobrewKit
import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // mockups/Discover.dc.html: a 40px header (dot, what runs, its time, Cancel, hide), the output in 12px SF Mono
        // on the sheet. The status line hides while the console shows. "Keep open" went with D1.
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
            ConsoleText(lines: model.console, dropped: model.consoleDropped)
        }
        .background(Theme.sheet)
    }
}

/// An NSTextView that only appends the new lines and removes the ones that dropped off the model's top: long output
/// stays fast and a drag selects across lines.
struct ConsoleText: NSViewRepresentable {
    let lines: [String]
    /// The lines that dropped off before `lines.first`: line numbers below count from the session's first line.
    let dropped: Int

    /// The text holds the session's lines `first..<shown`.
    final class Coordinator { var first = 0, shown = 0 }

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
        let c = context.coordinator
        guard dropped + lines.count > c.shown, let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage else { return }
        // Behind by more than the model keeps (or new): show the kept lines from the start.
        if c.shown <= dropped || c.shown == 0 {
            storage.setAttributedString(NSAttributedString())
            c.first = dropped
            c.shown = dropped
        }
        let text = (c.shown == c.first ? "" : "\n") + lines[(c.shown - dropped)...].joined(separator: "\n")
        storage.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]))
        // Remove the lines that dropped off the model's top since the last update, with their newlines.
        let string = storage.string as NSString
        var end = 0
        for _ in c.first..<dropped {
            end = string.range(of: "\n", range: NSRange(location: end, length: string.length - end)).upperBound
        }
        storage.deleteCharacters(in: NSRange(location: 0, length: end))
        c.first = dropped
        c.shown = dropped + lines.count
        textView.scrollToEndOfDocument(nil)
    }
}

/// DD4: the dot (green success, red failure, amber when a result needs attention), the last result, its time of day and
/// the console toggle. D2: while a command runs, a spinner, "Running: <titles>", the time, "<n> waiting", Cancel and
/// a thin amber bar on the top edge.
struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if !model.inProgress.isEmpty {
                ProgressView().controlSize(.mini).frame(width: 8, height: 8).accessibilityHidden(true)
                Text("Running: " + model.inProgress.map(\.title).joined(separator: ", "))
                    .foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                if let status = model.status, status.kind == .running {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        Text(formatDuration(.seconds(context.date.timeIntervalSince(status.time))))
                    }
                }
                if !model.waiting.isEmpty { Text("\(model.waiting.count) waiting") }
                Button("Cancel") { model.cancel() }
                    .buttonStyle(OutlinedButtonStyle(height: 24)).font(.system(size: 12, weight: .medium))
                    .disabled(!model.canCancel)
            } else if let status = model.status {
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
        .overlay(alignment: .top) {
            if model.inProgress.isEmpty { Theme.border.frame(height: 1) } else { RunningBar() }
        }
    }

    static func color(_ kind: CommandStatus.Kind) -> Color {
        switch kind {
        case .running, .attention: Theme.amber
        case .success: Theme.positive
        case .failure: Theme.negative
        case .cancelled, .skipped: Theme.muted
        }
    }
}

/// D2: a thin indeterminate amber bar: a segment that runs along the status line's top edge while a command runs.
struct RunningBar: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { bar in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                let width = bar.size.width * 0.3
                Theme.amber.frame(width: width, height: 2).offset(x: -width + (bar.size.width + width) * phase)
            }
        }
        .frame(height: 2).clipped().background(Theme.border.frame(height: 1), alignment: .top)
        .accessibilityHidden(true)
    }
}
