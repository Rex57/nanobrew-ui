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
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: only the visible lines are laid out, so long output stays fast.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.console.indices, id: \.self) { i in
                            Text(model.console[i]).id(i)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .onChange(of: model.console.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }
}
