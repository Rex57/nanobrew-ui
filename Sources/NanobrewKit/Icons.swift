import AppKit

/// The Lucide icons the app draws (lucide-static 1.66.0, ISC), bundled in Resources/Icons with stroke-width 1.5.
public enum Icon: String, CaseIterable, Sendable {
    case package, search, server, wrench, archive, settings, terminal, pin
    case circleArrowUp = "circle-arrow-up", rotateCW = "rotate-cw", externalLink = "external-link", triangleAlert = "triangle-alert", chevronDown = "chevron-down"

    /// A template image: it takes the colour of the text around it.
    public var image: NSImage? {
        guard let url = resources?.url(forResource: rawValue, withExtension: "svg", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// nanobrew's logo (Copyright 2026 Rach Pradhan, Apache-2.0).
public var nanobrewLogo: NSImage? {
    resources?.url(forResource: "nanobrew-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
}

/// The package resources: inside the app, bundle.sh puts them in Contents/Resources, where codesign accepts them;
/// SwiftPM's `Bundle.module` looks only next to the .app, so it is the fallback for `swift run` and the tests.
private let resources: Bundle? = Bundle.main.url(forResource: "NanobrewUI_NanobrewKit", withExtension: "bundle")
    .flatMap(Bundle.init(url:)) ?? Bundle.module
