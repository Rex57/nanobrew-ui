import NanobrewKit
import SwiftUI

/// D3: the result of a command that ended while the console was closed, bottom-right above the status line: the
/// dot, the result, one detail line, View and "Dismiss (n)". n counts down from 10 once a second and pauses while the
/// pointer is over the toast; at 0 the toast goes. It floats, so it has a shadow (taste: only what floats).
struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.reduceMotion) private var reduceMotion
    let toast: AppModel.Toast
    @State private var left = 10
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(StatusLine.color(toast.kind)).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // F5: a long result (a failure) wraps to two lines; the detail stays one.
                Text(toast.text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(toast.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).monospacedDigit()
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("View") { model.viewToast() }
                .buttonStyle(OutlinedButtonStyle(height: 26)).font(.system(size: 12, weight: .medium))
                .accessibilityLabel("View in the console")
            Button { model.dismissToast() } label: {
                // D6(2): the countdown number rolls.
                // F7: as wide as "Dismiss (10)" at every n, so View never moves (D6: nothing pops).
                Text("Dismiss (10)").hidden().overlay(alignment: .leading) {
                    Text("Dismiss (\(left))").contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                }
            }
                .buttonStyle(TextButtonStyle(color: Theme.muted)).font(.system(size: 12)).monospacedDigit()
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 380)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .onHover { hovering = $0 }
        .task(id: toast.id) {
            left = 10
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if !hovering { withAnimation(Motion.fade) { left -= 1 } }
            }
            model.dismissToast()
        }
    }
}
