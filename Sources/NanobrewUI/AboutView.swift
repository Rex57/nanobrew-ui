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
        VStack(spacing: 6) {
            Group {
                if let logo = nanobrewLogo { Image(nsImage: logo).resizable() } else { Color.white }
            }
            .frame(width: 72, height: 72)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
            .padding(.bottom, 6)
            Text("Nanobrew UI").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Version \(model.appVersion ?? "unknown")").foregroundStyle(Theme.text)
            Group {
                Text("nb version: \(nbVersion ?? "not found")")
                Text("Tested with nb \(testedNBVersion)")
            }
            .foregroundStyle(Theme.muted).monospacedDigit()
            Text("Unofficial. Not made by the nanobrew maintainer.").fontWeight(.semibold).foregroundStyle(Theme.text)
                .padding(.top, 8)
            Group {
                Text("License: Apache-2.0")
                Text("nanobrew logo: Copyright 2026 Rach Pradhan, Apache-2.0")
                Text("Icons: Lucide, ISC License")
            }
            .foregroundStyle(Theme.muted)
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
        .padding(28)
        .frame(width: 380)
        .background(Theme.sheet)
        .task { nbVersion = await model.nbVersion() }
    }
}
