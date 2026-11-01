import NanobrewKit
import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.running.map { "Running: \($0.title)" } ?? "Console").font(.headline)
                if !model.waiting.isEmpty { Text("\(model.waiting.count) waiting").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { model.cancel() }.disabled(!model.canCancel)
            }
            .padding(6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.console.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    Color.clear.frame(height: 1).id("end")
                }
                .onChange(of: model.console.count) { proxy.scrollTo("end") }
            }
        }
    }
}
