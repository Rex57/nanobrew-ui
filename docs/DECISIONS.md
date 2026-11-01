# Decisions

The main choices behind Nanobrew UI 1.0.0. The owner (Rex57) settled all of them on 2026-11-01. Each record has
the decision, the reason and the consequence.

## Build and code

### 1. A Swift package, no Xcode project

- **Date:** 2026-11-01
- **Decision:** One Swift package with a library (`NanobrewKit`), an executable SwiftUI target (`NanobrewUI`) and
  a test target. macOS 14 (Sonoma) or later, Swift 6 language mode. A script builds the `.app`.
- **Reason:** The whole build runs from the command line (`swift build`, `swift test`, `scripts/bundle.sh`), with
  no project file to keep in step with the sources.
- **Consequence:** `scripts/bundle.sh` makes the app bundle, the `Info.plist` and the icon. The icons and the logo
  reach the app through the package's resource bundle.

### 2. All logic in NanobrewKit

- **Date:** 2026-11-01
- **Decision:** `NanobrewKit` holds every rule: the state reader, the locator, the command catalogue, the runner,
  the parsers and the model. The app target holds only views.
- **Reason:** The tests link the library, not the app target.
- **Consequence:** The views only read `AppModel` and call it. A rule written in a view would have no test.

### 3. No third-party dependency

- **Date:** 2026-11-01
- **Decision:** No third-party Swift package.
- **Reason:** The app is a thin layer over nb, and the platform covers what it needs: `posix_spawn` for nb,
  SwiftUI for the views, `NSImage` for the SVG icons.
- **Consequence:** The icons are bundled SVG files. There is no update framework (see 16).

### 4. Every nb command, except `--deb` and `help`

- **Date:** 2026-11-01
- **Decision:** The app runs every nb command with its macOS flags. It leaves out `--deb` (Linux only) and `help`
  (the window replaces it). `version` shows in About. `completions` shows text with a Copy button.
- **Reason:** A person who prefers windows should not need Terminal for any nb task.
- **Consequence:** The command catalogue (`NBCommand`) has 40 entries, each with its exact argv.

## Data

### 5. Text parsing until nb has `--json`

- **Date:** 2026-11-01
- **Decision:** The app reads nb's text output, with the ANSI codes removed. It parses only what the UI needs as
  structure: search, outdated, services list, info, telemetry status, autoupdate status, the version and the
  upgrade skip line. All other output shows as plain text.
- **Reason:** nb 0.1.214 prints text for people and has no `--json` output.
- **Consequence:** The parsers follow nb's text, and a change in that text can break one. About shows "Tested with
  nb 0.1.214". The owner asks nanobrew for `--json` output, and the app will use it when it comes.

### 6. state.json is read only

- **Date:** 2026-11-01
- **Decision:** The app reads `/opt/nanobrew/db/state.json` and never writes it, or any file under
  `/opt/nanobrew`.
- **Reason:** nb owns its database. The app shows what nb has and runs nb; it is not a second package manager.
- **Consequence:** Every change goes through an nb command. A broken file shows an error and keeps the last good
  snapshot. The app writes only its own preferences, the Bundle export file and the clipboard.

### 7. Refresh at fixed moments, no file watcher

- **Date:** 2026-11-01
- **Decision:** The app reads `state.json` again after each command, when the app becomes active, and on ⌘R.
- **Reason:** These moments cover every change that the app makes. A change made in Terminal shows when the user
  comes back to the app.
- **Consequence:** A change made in Terminal while the app stays in front shows after ⌘R.

## Running nb

### 8. Argument lists, never a shell

- **Date:** 2026-11-01
- **Decision:** The app starts nb by its absolute path with an argv list.
- **Reason:** Without a shell, a package name or path with spaces, quotes or a semicolon stays one argument, and
  nothing in it can run as a command. A GUI app gets a short `PATH`, so the path must be absolute.
- **Consequence:** The one exception is `nb init`, which needs the macOS admin dialog. It runs through
  `osascript`, with the nb path passed as an argument and quoted with `quoted form of`.

### 9. One changing command at a time

- **Date:** 2026-11-01
- **Decision:** Changing commands wait in one serial queue. Read-only commands run at once, in parallel.
- **Reason:** nb locks its state while it works, so two nb operations must never clash.
- **Consequence:** The console shows "<n> waiting". Cancel stops what runs now, and the queued commands then run.

### 10. Ask before anything that removes or resets

- **Date:** 2026-11-01
- **Decision:** remove, rollback, cleanup, bundle install, migrate and nuke ask first. Nuke runs only after the user
  types "yes", and then runs as `nb nuke --yes`.
- **Reason:** Each of these removes or replaces packages or files, or changes what nanobrew manages, in one step.
- **Consequence:** Without `--yes`, nb nuke waits for "yes" on stdin, so the app always passes it after its own
  check. Clean Up needs a successful dry run with the same `--prune-kegs` setting first.

### 11. A given `-NBPath` is the only place the app looks

- **Date:** 2026-11-01
- **Decision:** Without `-NBPath`, the app looks for nb at the Settings path, then `/opt/nanobrew/prefix/bin/nb`,
  then `~/.local/bin/nb`. With `-NBPath`, it looks only there.
- **Reason:** The user's own choice wins over the default places. A test path must never fall back to the real
  nb: a typo in a test would otherwise run commands on a real nanobrew.
- **Consequence:** A wrong test path shows "nanobrew is not installed".

### 12. Closing the window quits the app

- **Date:** 2026-11-01
- **Decision:** The app has one main window. Closing it quits the app.
- **Reason:** The app is a single-window utility, like System Settings.
- **Consequence:** A close while a changing command runs or waits asks first, like a quit. There is no File > New
  Window.

### 13. A quit lets nb finish

- **Date:** 2026-11-01
- **Decision:** When the user quits while a changing command runs, the app does not stop nb. nb runs in its own
  process group and ends its operation in the background.
- **Reason:** A finished nb operation, or one that nb rolled back itself, is safer than one cut off halfway.
- **Consequence:** The quit question says so: "nb keeps running in the background until it ends. You will not see
  its output." The next launch reads the result.

### 14. Reinstall only from nb's own verdict, keyed on the installed version

- **Date:** 2026-11-01
- **Decision:** A cask gets the "Can't upgrade in place" badge and a "Reinstall…" button only after nb itself
  printed `[unsupported, skipping: <reason>]` for it. The app remembers that verdict per cask token and installed
  version, in its own preferences. Reinstall runs only by hand, never inside "Upgrade All Casks". It removes the
  cask and installs it again only when the remove succeeded. A failed install says so plainly.
- **Reason:** A guess from download links would copy nb's rules, and would go wrong when nb learns to upgrade disk
  images (nanobrew #491). The key is the installed version because nb's trust check can fall back to an older
  verified build: the new version in the skip line can then differ from the one in `nb outdated --cask`, and a
  key on the new version would never match. A key on the installed version can at worst show a badge that still
  leads to a working Reinstall.
- **Consequence:** A cask shows the badge only after one upgrade attempt. The dialog warns that the app is removed
  first and stays removed if the install fails, for example with no network.

## Release

### 15. Ad hoc signing, not a Developer ID

- **Date:** 2026-11-01
- **Decision:** The app is signed ad hoc and not notarized.
- **Reason:** It is free, needs no Apple account and puts no personal name in the app. nb does not set the
  quarantine flag on what it downloads, so Gatekeeper does not check an app that nb installs.
- **Consequence:** A copy from `brew install --cask` or a browser download gets the quarantine flag, and
  Gatekeeper blocks it. The README says so. macOS can ask again for the App Management permission after an update.
  A later move to a Developer ID needs no code change.

### 16. A zip, not a DMG

- **Date:** 2026-11-01
- **Decision:** The release asset is one zip, `Nanobrew-UI-<version>.zip`, with no AppleDouble `._` entries.
- **Reason:** nb upgrades zip casks in place but skips disk images (nanobrew #491). `._` files in a zip break the
  signature (nanobrew #425).
- **Consequence:** The bundle script clears extended attributes and zips with `ditto --norsrc`. A real upgrade can
  be tested only when a second version exists.

### 17. No Sparkle: the app upgrades through nb

- **Date:** 2026-11-01
- **Decision:** The app has no update framework. It upgrades with `nb upgrade --cask nanobrew-ui`, from Terminal or
  from its own Updates screen.
- **Reason:** nb keeps managing the app like any other cask: in `state.json`, in `nb outdated` and in `nb remove`.
- **Consequence:** After nb upgraded the app with success, a Restart button appears. There is no separate upgrade
  helper.

## Design

### 18. The framed-sheet style, in light and dark

- **Date:** 2026-11-01
- **Decision:** An opaque tinted frame for the sidebar and the top bar, and the content on an inset sheet. The app
  follows the Mac's light or dark setting. Dark mode uses true neutral darks, not navy or slate.
- **Reason:** A developer tool with short visits and list-plus-detail screens. The frame and the sheet map onto
  the Mac window's sidebar, toolbar and content.
- **Consequence:** One token table in `Theme.swift`, with a light and a dark value for each colour
  ([DESIGN.md](DESIGN.md)).

### 19. Amber means "needs your attention"

- **Date:** 2026-11-01
- **Decision:** The one hue is nanobrew's amber, and it marks only what needs the user. Red marks only failure and
  loss, green only success. Buttons are near-black, never amber. Colour stays under 3 % of the screen.
- **Reason:** A colour that always means the same thing lets the user see at a glance what needs them.
- **Consequence:** Light mode has two ambers: `#ba8122` for marks and `#8b6019` for text, because text needs 4.5:1
  on the selected-row grey.

### 20. The system font

- **Date:** 2026-11-01
- **Decision:** SF Pro with tabular figures for numbers; SF Mono only for nb's own text and for flags.
- **Reason:** A native Mac app uses the system font. This replaces the style sheet's IBM Plex Sans on purpose.
- **Consequence:** Versions, counts and durations line up in tables and in the status line.

### 21. Speed is the signature

- **Date:** 2026-11-01
- **Decision:** Every command shows its duration ("Installed sl in 0.84 s"), and the last result stays in a status
  line. The console is closed by default, opens while a command runs, can be kept open, and ⌘J toggles it.
- **Reason:** nanobrew is fast, and the app should show it without a console that takes half the window.
- **Consequence:** `NanobrewKit` times each command with a monotonic clock and writes the status text.

### 22. Lucide icons

- **Date:** 2026-11-01
- **Decision:** Icons from Lucide (lucide-static 1.66.0, ISC), bundled as SVG files and drawn as template images,
  16 px and grey in the sidebar.
- **Reason:** The owner chose Lucide for the design pass. Its ISC licence allows bundling, and `NSImage` reads its
  SVG files with no extra code.
- **Consequence:** No new dependency. README and About credit Lucide.

### 23. "Recently upgraded" waits for a later version

- **Date:** 2026-11-01
- **Decision:** A list of recent upgrades on Updates, built from the history in `state.json`, was drawn and left
  out of 1.0.0.
- **Reason:** The owner kept 1.0.0 to its agreed scope.
- **Consequence:** It is listed under "Future ideas" in the README.

## Identity and licences

### 24. Unofficial, and labelled so

- **Date:** 2026-11-01
- **Decision:** The name is "Nanobrew UI", the bundle id `io.github.rex57.nanobrew-ui`, the cask token
  `nanobrew-ui`. README and About say "Unofficial. Not made by the nanobrew maintainer."
- **Reason:** Users must not ask the nanobrew maintainer for help with this app.
- **Consequence:** Problems with the app are reported in this repository.

### 25. No BrewUI code

- **Date:** 2026-11-01
- **Decision:** The app is licensed Apache-2.0. No code is copied from Homebrew's BrewUI; only its layout ideas
  are used.
- **Reason:** BrewUI is licensed AGPL-3.0, which does not fit an Apache-2.0 app.
- **Consequence:** The README states that no BrewUI code is copied.

### 26. The nanobrew logo, with credit, and the maintainer asked

- **Date:** 2026-11-01
- **Decision:** The app icon and the sidebar mark use nanobrew's logo (`assets/logo.png` in the nanobrew
  repository) on a white rounded square, next to the "Unofficial" label. The owner asks the nanobrew maintainer
  for a yes in an issue on `justrach/nanobrew` after the release.
- **Reason:** The app is for nanobrew, and the logo's Apache-2.0 licence asks for credit. A logo is also the mark
  of its project, so the owner asks the maintainer as well.
- **Consequence:** README and About credit the logo: Copyright 2026 Rach Pradhan, Apache-2.0. On a no from the
  maintainer, the icon changes in 1.0.1.

### 27. A test-only appearance argument

- **Date:** 2026-11-01
- **Decision:** `-NBAppearance light|dark` forces the app's appearance for one launch.
- **Reason:** macOS ignores `-AppleInterfaceStyle` for this app, and a check must never change the Mac's own
  appearance setting.
- **Consequence:** Both themes can be checked on any Mac. Normal use never passes it.
