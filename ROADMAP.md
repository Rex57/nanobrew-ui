# Roadmap

> Status: current · Owner: Rex57 · Reviewed: 2026-11-05

What is done, what is open, and what comes next. Releases and their changes are in the [changelog](CHANGELOG.md).

## Now

Nanobrew UI 1.0.1 is released. It installs and upgrades with nanobrew through the tap:
`nb install --cask Rex57/tap/nanobrew-ui` (see the [README](README.md#install)).

## Open

- **nanobrew issue [#495](https://github.com/justrach/nanobrew/issues/495)**, waiting for the maintainer. It asks for
  `--json` output on eight commands, a machine-readable form of the "unsupported, skipping" upgrade line, the short
  name for tap casks, and a yes or no on the use of nanobrew's logo. If the answer on the logo is no, the next
  version gets another icon.

## Next

- **nb's `--json` output.** nb prints text for people, and the app reads that text. When nanobrew adds `--json`
  output (for `list`, `outdated`, `info`, `search`, `leaves`, `deps`, `services list` and `where`), the app will
  use it instead of its text parsers and its reads of `state.json`.
- **"Recently upgraded" on Updates.** A list of the last upgrades (package, from, to, date), built from the
  history in nanobrew's `state.json`. It is drawn on the Updates screens of the
  [UI prototype](docs/UI/prototype_UI.html) and was left out of 1.0.0.
