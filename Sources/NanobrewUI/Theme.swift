import AppKit
import NanobrewKit
import SwiftUI

/// The light and dark tokens of the framed-sheet style (DD10, DD11, DD17; mockups/*.dc.html). They follow the
/// Mac's appearance.
enum Theme {
    static let frame = pair(0xf9fbfc, 0x000000)
    static let sheet = pair(0xffffff, 0x111111)
    static let raised = pair(0xf4f6f8, 0x1a1a1a)
    static let active = pair(0xebedee, 0x262626)
    static let border = pair(0xe8eaec, 0x2e2e2e)
    static let rule = pair(0xf0f1f2, 0x1e1e1e)
    static let control = pair(0xcdced1, 0x444444)
    static let edge = pair(0xd5d8db, 0x3a3a3a)
    static let text = pair(0x131416, 0xffffff)
    static let muted = pair(0x5d5f60, 0xb4b4b4)
    static let amber = pair(0xba8122, 0xf8ac2d)
    static let amberText = pair(0x8b6019, 0xf8ac2d)
    static let amberBg = pair(0xfbf4e6, 0x2a2112)
    static let positive = pair(0x1e7b4f, 0x3fc07a)
    static let negative = pair(0xc4242a, 0xe5566f)
    static let primary = pair(0x131416, 0xffffff)
    static let onPrimary = pair(0xffffff, 0x000000)
    static let pillBg = pair(0xebedee, 0x262626)
    static let pillInk = pair(0x353736, 0xd4d4d4)

    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) {
            $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

/// A Lucide icon drawn as a template in the colour around it.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = icon.image { Image(nsImage: image).renderingMode(.template).resizable() } else { Color.clear }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Section {
    var icon: Icon {
        switch self {
        case .installed: .package
        case .updates: .circleArrowUp
        case .discover: .search
        case .services: .server
        case .maintenance: .wrench
        case .bundle: .archive
        case .settings: .settings
        }
    }
}

/// DD12: the mark, the name and the scope line; the groups Packages and System; Settings at the bottom.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: Section?
    @State private var nbVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Group {
                    if let logo = nanobrewLogo { Image(nsImage: logo).resizable() } else { Color.white }
                }
                .frame(width: 28, height: 28)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nanobrew UI").font(.system(size: 14, weight: .semibold))
                    Text(model.notInstalled ? "nb not found" : "nb \(nbVersion ?? "") · /opt/nanobrew")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 8, bottom: 14, trailing: 8))
            header("Packages", top: 6)
            row(.installed)
            row(.updates)
            row(.discover)
            header("System", top: 14)
            row(.services)
            row(.maintenance)
            row(.bundle)
            Spacer()
            row(.settings)
        }
        .padding(EdgeInsets(top: 34, leading: 10, bottom: 12, trailing: 10))
        .foregroundStyle(Theme.text)
        .task(id: model.nbPath) { nbVersion = await model.nbVersion() }
    }

    private func header(_ title: String, top: CGFloat) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(Theme.muted)
            .padding(EdgeInsets(top: top, leading: 8, bottom: 4, trailing: 8))
    }

    private func row(_ item: Section) -> some View {
        let selected = (section ?? .installed) == item
        return Button { section = item } label: {
            HStack(spacing: 10) {
                IconView(icon: item.icon).foregroundStyle(selected ? Theme.text : Theme.muted)
                Text(item.rawValue).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                if item == .updates, let count = model.updatesCount {
                    Text("\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
                        .background(Theme.amberBg, in: Capsule())
                        .accessibilityLabel("\(count) updates")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(selected ? Theme.active : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
