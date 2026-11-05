# Testing

> Status: current · Owner: Rex57 · Reviewed: 2026-11-05

## The tests

- They are in `Tests/NanobrewKitTests`, one file per area (the table below); `swift test` prints the count.
- They use Swift Testing: `import Testing`, `@Test`, `#expect` and `#require`. Suites that use `AppModel` run on
  the main actor (`@MainActor @Suite`).
- They link `NanobrewKit` only (`@testable import NanobrewKit`), never the app target. This is why all logic lives
  in `NanobrewKit` ([ARCHITECTURE.md](ARCHITECTURE.md#the-two-targets)).
- A good test checks behaviour through a public interface. It gives an input and checks what a caller or a person
  sees, not private state.

## Run them

```sh
swift test                                                       # all tests
swift test --filter RunnerTests                                  # one suite
swift test --filter RunnerTests/cancelStopsTheProcessGroupAndTheNextQueuedCommandRuns   # one test
python3 -I tools/check_docs.py .                                 # the docs gate alone (also part of swift test)
swift build -c release && swift test && scripts/bundle.sh        # the full check before a release
```

## What each file covers

| File | Covers |
|---|---|
| `StateTests.swift` | `StateReader` (full, empty, missing and broken files, missing folder) and `NBLocator` (order, non-executables, the exclusive `-NBPath`, nothing found). Also holds the helpers `fixture(_:)` and `scratchDir()`. |
| `RunnerTests.swift` | argv kept whole, the serial queue, read-only commands in parallel, Cancel of the process group, the `SIGKILL` 5 s after a `SIGTERM` that nb ignored (and none for a run that ended), ANSI removal, stderr in the console, the last 20,000 console lines, a non-zero exit, `askBeforeQuit`, the reload after a command, no exit code before the reap |
| `StatusTests.swift` | The status texts and durations, the launch check, the console's open and closed states (a command leaves them as they were), read-only results that must not replace a running change, `refresh()` |
| `ReadLimitTests.swift` | The one read path: a cancelled read (services, info, search) ends its nb run, the read limit (the timeout text, on time, a run that ignores `SIGTERM`, bundle dump writes nothing), no limit while the app's own changing command runs, the quit call ends reads and leaves console commands alone, console commands have no limit |
| `SummaryTests.swift` | nb's summary lines of cleanup, dry run and Doctor (recorded, each form, with ANSI codes, refused lines), and the status texts they give (the amber `attention` kind for problems) |
| `ToastTests.swift` | The toast: made only when the console is closed, never by a background read, replaced by a newer end, cleared by Dismiss, View and opening the console, made for a failure, a cancel and a command that cannot start |
| `ReinstallTests.swift` | The skip-line parse, the plain words, the verdict per installed version, the status after skips, the upgrade outcome (`UpgradeOutcome`: the skipped casks, and the restart offer for the short name and the tap name), the ready rows, the Reinstall sequence (good, failed remove, failed install, quit during it), runs that cannot start |
| `UpdateTests.swift` | The outdated parse, formulae and casks from their two commands, the restart offer after a self-upgrade (and when there must be none), a cancelled check that keeps the list, Restart's order (ask, open, quit) and a failed open, the check after a changing command only, the `commandsEnded` signal, the checks at launch and when the app becomes active (one check for both), ⌘R and activation sharing one running check |
| `ActionTests.swift` | The Installed actions, confirmation and decline |
| `InfoTests.swift` | `PackageInfo` for formulae and casks, the detail pane with and without a tree, nb's error text (also when nb exits 0), a cancelled fetch |
| `SearchTests.swift` | Search rows, the installed tag, no results, every install form |
| `ServicesTests.swift` | Service rows, the service commands, nb's error text for a failed list or search |
| `MaintenanceTests.swift` | The maintenance commands, the autoupdate parse, `lastRunSucceeded`, the cleanup rule (`canCleanUp`), the dry-run answer (kept until forgotten, none after a failure or a late end), the Doctor answer for the session, the row text when nb prints no known answer |
| `SettingsTests.swift` | Bundle and Settings commands, telemetry, the saved nb path, bundle dump to a file (stdout only, nothing written on failure), completions |
| `SetupTests.swift` | Nuke's typed "yes", migrate, the `nb init` admin script, locating nb again after nuke |
| `TrustTests.swift` | The trust line in plain words |
| `ThemeTests.swift` | Every icon loads as a template image, the logo loads, icons and the logo load once, the Updates count, the error text of a failed outdated check |
| `VersionTests.swift` | Earlier versions from the history, rollback and switch |
| `AboutTests.swift` | The nb version and the tested version |
| `DocsGateTests.swift` | The docs gate: `tools/check_docs.py` passes on the repo, and its selftest passes |

## The fake nb

`Tests/Fixtures/fake-nb` is a bash script that stands in for nb. Tests and manual checks never run a real nb
that could change anything. Link it as `nb` in a scratch folder (call it D); the `FakeNB` helper in
`FakeNB.swift` does this for each test.

**Control files.** The fake reads files in D, keyed on its first argument:

| File | Effect |
|---|---|
| `D/wait-<arg1>` | Sleep that many seconds before printing. The sleep runs as a child process, so a Cancel test can prove that the whole process group stops. |
| `D/exit-<arg1>` | Exit with that code. |
| `D/stderr-<arg1>` | Print that file to stderr. |
| `D/ignore-term-<arg1>` | Ignore `SIGTERM`, the sleep child too; only the `SIGKILL` that follows a Cancel 5 s later stops the run. |
| `D/out-<arg1>` | Print that file as the output instead of the recorded one (for example `doctor-issues.txt`, a Doctor that finds 2 problems). |

**Log.** Each run appends to `D/fake-nb.log`, with tabs between the fields:

- `START <arg> <arg> …` when it starts;
- `CHILD <pid>` when it sleeps (the pid of the sleep child);
- `END <arg> <arg> …` when it ends. A cancelled run has no `END` line.

**Output.** The fake prints `nb-output/<all args joined by _>.txt` next to the real script, else
`nb-output/<arg1>.txt`, else nothing. For example, `nb info --cask iterm2` prints `info_--cask_iterm2.txt`.

**The helper.** `FakeNB` gives `wait(_:seconds:)`, `ignoreTerm(_:)`, `output(_:recorded:)`, `exit(_:code:)` and `stderr(_:text:)` to write the control
files, `log`, `argvs` (without the outdated checks) and `allArgvs` to read the log, `killChildren()` to end
leftover sleeps, and `model(statePath:)` to make an `AppModel` that uses the fake.
`eventually(_:)` waits up to 10 seconds for a condition.

**Other seams in the model.** `AppModel` takes a clock (`now:`), a `UserDefaults` (`defaults:`) and a locator
(`locate:`), so tests can control durations, the Reinstall verdicts and where nb is.

**The admin script.** Two tests run the real `/usr/bin/osascript` with the app's `nb init` argv. Each test first
removes the admin clause, or replaces the whole command with error -128, so no password dialog can open. A
`#require` stops the test if that edit did not apply.

## Fixtures

- **State files** in `Tests/Fixtures`: `state.json` (a trimmed real file), `state-empty.json`, `state-broken.json`,
  and `state-self-current.json`, `state-self-upgraded.json`, `state-self-tap-current.json` and `state-self-tap-upgraded.json` (for the restart offer after a self-upgrade, with the short name and with the tap name).
- **nb output** in `Tests/Fixtures/nb-output`: recorded text of real nb 0.1.214. It comes from read-only commands on
  a real install. It was checked unchanged against nb 0.1.215 (2026-11-05: the parsed commands' output did not
  change). Outputs that a real install could not show (for example `nb outdated` with outdated packages, or
  an upgrade skip line) follow the text in nanobrew's source.

## The three test seams

| Seam | How | Catches | Misses |
|---|---|---|---|
| NanobrewKit | `swift test` with the fake nb and the fixtures | Wrong argv, wrong parsing, queue order, Cancel, the confirmation rules, the refresh after a command, durations, verdicts, the Reinstall sequence | The real screen and the real nb |
| The running app | The built app with `-NBPath` and `-NBStatePath`, in light and dark, driven by AppleScript, checked with screenshots against the [mockups](UI/prototype_UI.html) and with the fake nb's log | Wiring, screens, dialogs, the console, the look | Changes in real nb output (checked with read-only commands on a real install) |
| The release zip | The zip that `scripts/bundle.sh` makes | A broken signature, a wrong checksum, `._` entries, a wrong cask | The real install through the tap (checked at release) |

[RELEASING.md](RELEASING.md) lists the zip checks.

## Manual checks with launch arguments

Point a built copy (`scripts/bundle.sh`, see the [README](../README.md#build)) at the fake nb and a fixture:

```sh
mkdir -p /tmp/nbfake && ln -sf "$PWD/Tests/Fixtures/fake-nb" /tmp/nbfake/nb && cp Tests/Fixtures/state.json /tmp/nbfake/
open -n "dist/Nanobrew UI.app" --args -NBPath /tmp/nbfake/nb -NBStatePath /tmp/nbfake/state.json -NBAppearance dark
```

| Argument | Effect |
|---|---|
| `-NBPath <file>` | The only place the app looks for nb. A wrong path shows "nanobrew is not installed" and never reaches a real nb. |
| `-NBStatePath <file>` | The `state.json` to read. A path in a missing folder shows "nanobrew is not set up". `Tests/Fixtures/state-broken.json` shows the red "Cannot read …" line. |
| `-NBAppearance light\|dark` | For tests only: forces light or dark for this launch. macOS ignores `-AppleInterfaceStyle` for this app. It never changes the Mac's own setting. |
| `-NBReduceMotion YES` | For tests only: the app moves as with Reduce Motion on (fades only, nothing travels). It never changes the Mac's own accessibility setting. |

These are user-defaults launch arguments: they last for that launch only.

The control files give the other states:

```sh
echo 30 > /tmp/nbfake/wait-upgrade                    # upgrades take 30 s: the console, the queue and Cancel
echo 1 > /tmp/nbfake/exit-install                     # installs fail with exit code 1
echo "nb: test error" > /tmp/nbfake/stderr-doctor     # doctor prints an error line
tail -f /tmp/nbfake/fake-nb.log                       # watch which commands ran
rm -f /tmp/nbfake/wait-* /tmp/nbfake/exit-* /tmp/nbfake/stderr-* /tmp/nbfake/ignore-term-*   # back to normal
```

Do not press "Set up nanobrew" in a test copy. It runs `osascript` with administrator privileges, and macOS opens
its real password dialog.

## Driving the app by AppleScript safely

The running-app seam drives the app with AppleScript (`osascript` and System Events) and checks it with
screenshots. The terminal app needs the Accessibility and Screen Recording permissions once. Keep these rules:

1. **Use your own copy.** Start it with `open -n` and note its pid. One tester uses the app at a time.
2. **Act only when that copy is in front.** Before every keystroke or click, check that your copy is alive and
   frontmost. Send a click only to a point inside its window. Never type while another app is in front: a stray
   Return once went into a terminal after the app copy had quit.
3. **Click at points.** On macOS 27, SwiftUI buttons have no accessibility titles, so scripts click at points.
   System Events `click at` does not fire SwiftUI tap gestures; use a real mouse event (a CGEvent click) instead.
4. **Capture only that window.** Move the window to a known place, then capture its area.
5. **Quit by pid.** Quit only your own copy, by its pid. Quitting by app name hits every copy, the owner's real
   app too.
6. **Never change the Mac's appearance.** Use `-NBAppearance` instead.
7. **Clean up.** Delete the preferences keys you made, and restore the clipboard after a Copy check. A test copy
   shares the domain `io.github.rex57.nanobrew-ui` with a real installed copy, so delete single keys, not the
   domain:

   ```sh
   defaults delete io.github.rex57.nanobrew-ui SavedNBPath
   defaults read io.github.rex57.nanobrew-ui | grep ReinstallVerdict   # then delete each key you made:
   defaults delete io.github.rex57.nanobrew-ui ReinstallVerdict.<token>
   ```

## Checks on a real nanobrew

On a real nanobrew (`/opt/nanobrew`), run only read-only nb commands, plus installing and removing one small test
formula (`sl`). Never run these on a real install: nuke, migrate, cleanup without `--dry-run`, update, upgrade,
bundle install, init. Test them with the fake nb only. The one real cask test is at release: installing the app's
own cask ([RELEASING.md](RELEASING.md#5-check-the-install)).
