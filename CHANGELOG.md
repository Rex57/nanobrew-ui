# Changelog

> Status: current · Owner: Rex57 · Reviewed: 2026-11-05

Each release of Nanobrew UI, newest first. Old entries keep their words. The release zips are on the
[releases page](https://github.com/Rex57/nanobrew-ui/releases); how a release is made is in
[Releasing](docs/RELEASING.md).

## 1.0.1, 2026-11-01

- **Fixed:** after the app upgrades itself, it offers "Restart to use the new version" also when it was installed
  from the tap. nb records a tap cask under its full name, `Rex57/tap/nanobrew-ui`, and 1.0.0 looked only for
  `nanobrew-ui`.
- **Docs:** the upgrade command uses the full tap name, `nb upgrade --cask Rex57/tap/nanobrew-ui`; nb answers
  "not installed" for the short name.

## 1.0.0, 2026-11-01

The first release. A native macOS app for nanobrew (`nb`), unofficial.

- Every nb command for macOS, on seven screens: Installed, Updates, Discover, Services, Maintenance, Bundle and
  Settings.
- A status line with each command's result and duration, and a console that opens while a command runs.
- One changing command at a time; a confirmation before anything that removes or resets, and a typed "yes"
  before `nb nuke`.
- "Reinstall…" for a cask that nb cannot upgrade in place: the app removes it, then installs the new version only
  after the remove succeeded.
- Light and dark, following the Mac's setting.
- Signed ad hoc, not notarized; installed with `nb install --cask Rex57/tap/nanobrew-ui`. Tested with nb 0.1.214.
