# Roadmap

> Status: current · Owner: Rex57 · Reviewed: 2026-11-05

What is done, what is open, and what comes next. Releases and their changes are in the [changelog](CHANGELOG.md).

## Now

Nanobrew UI 1.0.2 is released (2026-11-05): a quiet console with a result note, Maintenance results without
the console, the Services hang fix and the clean-up fixes (see the [changelog](CHANGELOG.md)). It installs and
upgrades with nanobrew through the tap: `nb install --cask Rex57/tap/nanobrew-ui` (see the
[README](README.md#install)).

## Open

- **nanobrew issue [#495](https://github.com/justrach/nanobrew/issues/495)**, waiting for the maintainer. It asks for
  `--json` output on eight commands, a machine-readable form of the "unsupported, skipping" upgrade line, the short
  name for tap casks, and a yes or no on the use of nanobrew's logo. If the answer on the logo is no, the next
  version gets another icon.
- **nanobrew issue [#503](https://github.com/justrach/nanobrew/issues/503)**, waiting for the maintainer. nb's own
  HTTP client has no connect time limit, so `nb outdated --cask` can hang on a network that drops IPv6 and hold
  nb's lock, which blocks every other nb command. 1.0.2 works around it in the app (background reads end after
  60 s); nb in Terminal can still hang.

## Next

- **nb's `--json` output.** nb prints text for people, and the app reads that text. When nanobrew adds `--json`
  output (for `list`, `outdated`, `info`, `search`, `leaves`, `deps`, `services list` and `where`), the app will
  use it instead of its text parsers and its reads of `state.json`.
- **"Recently upgraded" on Updates.** A list of the last upgrades (package, from, to, date), built from the
  history in nanobrew's `state.json`. It is drawn on the Updates screens of the
  [UI prototype](docs/UI/prototype_UI.html) and was left out of 1.0.0.
