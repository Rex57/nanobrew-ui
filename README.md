# Nanobrew UI

A native macOS app for [nanobrew](https://github.com/justrach/nanobrew) (`nb`). It shows what nb has installed,
what is out of date and which services run, and it runs every nb command from a window, with the live output in a
console. nb does all the work; the app only shows what nb has and prints.

**Unofficial. Not made by the nanobrew maintainer.** Please report problems with the app here, not to nanobrew.

## Install

```sh
nb install --cask Rex57/tap/nanobrew-ui
```

Upgrade it like any other cask: `nb upgrade --cask nanobrew-ui` (or Updates > Upgrade in the app). After an
upgrade of itself, the app offers a restart.

The app is signed ad hoc, not with an Apple Developer ID, and it is not notarized. nb does not quarantine what it
installs, so the app opens when nb installs it. A copy from `brew install --cask` or from a browser download gets
the quarantine flag, and Gatekeeper blocks it. macOS can ask again for the App Management permission after an
update.

Requirements: macOS 14 (Sonoma) or later, and nanobrew. Tested with nb 0.1.214.

## Build

```sh
swift build                 # debug build
swift test                  # tests (NanobrewKit, with a fake nb and fixture state files)
scripts/bundle.sh           # dist/Nanobrew UI.app, dist/Nanobrew-UI-1.0.0.zip, its sha256, dist/nanobrew-ui.rb
```

A Swift package, no Xcode project and no third-party dependency: the library `NanobrewKit` holds all logic, and
the `NanobrewUI` target holds the SwiftUI views. `scripts/make-icon.swift` makes the icon from nanobrew's logo.

## Future ideas

- **nb's `--json` output.** nb prints text for people, and the app reads that text. When nanobrew adds `--json`
  output (for `list`, `outdated`, `info`, `search`, `leaves`, `deps`, `services list` and `where`), the app will
  use it.
- **"Recently upgraded" on Updates.** A list of the last upgrades (package, from, to, date), built from the
  history in nanobrew's state.json. It was drawn on the design canvas and left out of 1.0.0.

## License

Apache-2.0 (see LICENSE). No code is copied from Homebrew's BrewUI.

The nanobrew logo (`Sources/NanobrewKit/Resources/nanobrew-logo.png`, used in the app icon and the sidebar) is Copyright 2026 Rach Pradhan, licensed
under Apache-2.0, from the nanobrew repository.

The icons are from [Lucide](https://lucide.dev) (lucide-static 1.66.0, `Sources/NanobrewKit/Resources/Icons`, drawn
at stroke width 1.5), licensed under the ISC License, Copyright (c) Lucide Contributors.
