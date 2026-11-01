import AppKit
import NanobrewKit
import SwiftUI

struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Nanobrew UI") { openWindow(id: "about") }
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var model
    @State private var nbVersion: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Nanobrew UI").font(.title2)
            Text("Version \(model.appVersion ?? "unknown")")
            Text("nb version: \(nbVersion ?? "not found")")
            Text("Tested with nb \(testedNBVersion)")
            Text("Unofficial. Not made by the nanobrew maintainer.").bold()
            Text("License: Apache-2.0")
            Text("nanobrew logo: Copyright 2026 Rach Pradhan, Apache-2.0").foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
        .padding(24)
        .frame(width: 380)
        .task { nbVersion = await model.nbVersion() }
    }
}
