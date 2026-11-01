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
    /// The positive pale pair of a running service's pill (app-screens.md §7.6).
    static let positiveBg = pair(0xe6f4ec, 0x12261b)
    /// Behind a dialog: #131416 at 28% on light, black at 50% on dark.
    static let scrim = pair(0x131416, 0x000000, alpha: (0.28, 0.5))

    private static func pair(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
        func color(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        }
        return Color(nsColor: NSColor(name: nil) {
            $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark, alpha.1) : color(light, alpha.0)
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
    /// The placeholder of the top-bar search field; nil: the section has none.
    var searchPrompt: String? {
        switch self {
        case .installed: "Search installed packages"
        case .updates: "Search updates"
        case .discover: "Search formulae and casks"
        default: nil
        }
    }

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

/// The near-black primary button (white on dark), 32px high.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(enabled ? Theme.onPrimary : Theme.muted)
            .padding(.horizontal, 14).frame(height: 32)
            // Disabled: the mockup's grey (Discover's "Installing jq…").
            .background(enabled ? Theme.primary.opacity(configuration.isPressed ? 0.8 : 1) : Theme.active,
                        in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A text action ("Pin", "Switch", "Remove…" in the negative colour).
struct TextButtonStyle: ButtonStyle {
    var color = Theme.text
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(color.opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4))
            .contentShape(Rectangle())
    }
}

/// The neutral grey pill ("Pinned", "Installed").
struct Pill: View {
    let text: String
    var height: CGFloat = 20

    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.pillInk)
            .padding(.horizontal, 8).frame(height: height)
            .background(Theme.pillBg, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// One h1 per screen (22px) and its grey subline.
struct ScreenTitle<Subline: View>: View {
    let title: String
    @ViewBuilder let subline: Subline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            subline.font(.system(size: 14)).foregroundStyle(Theme.muted).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An ISO date (2026-06-30) from a state.json time stamp.
func isoDate(_ seconds: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(.iso8601.year().month().day())
}

/// The outlined secondary button (28px), or the outlined negative one of a destructive choice.
struct OutlinedButtonStyle: ButtonStyle {
    var color = Theme.text
    var border = Theme.control
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12).frame(height: height)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// app-screens.md §8.2: a title and a grey description on the left, the controls on the right, a rule under it.
struct SettingsRow<Controls: View>: View {
    let title: String
    let description: String
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                Text(description).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { controls }
                .fixedSize()
                .buttonStyle(OutlinedButtonStyle())
                .toggleStyle(.switch).controlSize(.small).tint(Theme.primary)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

/// Plain words first, the flag after them in grey (DD6).
func flagLabel(_ words: String, _ flag: String) -> some View {
    HStack(spacing: 6) {
        Text(words).font(.system(size: 13)).foregroundStyle(Theme.text)
        Text(flag).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
    }
}

extension View {
    /// A text field in the theme: 28px, 1px control edge, 6px corners.
    func themedField(width: CGFloat? = nil) -> some View {
        textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.text)
            .padding(.horizontal, 10).frame(width: width, height: 28)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.control))
    }
}

/// The up and down arrow keys move `selection` through `items` and scroll to it, as the parent run's
/// List(selection:) did; a click on a row gives the list the keyboard focus. Rows carry `.id(item)`.
struct ArrowSelection<Item: Hashable>: ViewModifier {
    @Binding var selection: Item?
    let items: [Item]
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.downArrow) { move(1, proxy) }
                .onKeyPress(.upArrow) { move(-1, proxy) }
                .onChange(of: selection) { _, new in if new != nil { focused = true } }
        }
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let index = selection.flatMap { items.firstIndex(of: $0) }.map { $0 + step } ?? (step > 0 ? 0 : items.count - 1)
        let next = items[min(max(index, 0), items.count - 1)]
        selection = next
        proxy.scrollTo(next)
        return .handled
    }
}
