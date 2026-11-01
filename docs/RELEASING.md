# Releasing

A release is one zip on a GitHub release, plus one cask file in the tap `Rex57/homebrew-tap`. Users install and
upgrade the app with nb. The steps below use version 1.0.0; put the new version in its place.

## 1. Build

1. Set `VERSION` at the top of `scripts/bundle.sh`. It is the only place that sets the version: the
   `Info.plist`, the zip name and the cask all take it from there.
2. Run the full check:

   ```sh
   swift build -c release && swift test && scripts/bundle.sh
   ```

3. `scripts/bundle.sh` makes these files in `dist/`: `Nanobrew UI.app`, `Nanobrew-UI-1.0.0.zip` and
   `nanobrew-ui.rb` (the cask text). It also prints the zip's sha256. `dist/` and `.build/` are git-ignored, and
   built output never goes into a commit.

[ARCHITECTURE.md](ARCHITECTURE.md#the-bundle-script-and-the-release-zip) describes each step of the script.

## 2. Check the zip

```sh
ZIP="dist/Nanobrew-UI-1.0.0.zip"
zipinfo -1 "$ZIP" | grep -E '(^|/)\._|__MACOSX' && echo "FAIL: AppleDouble entries" || echo "OK: no ._ or __MACOSX entries"
zipinfo -1 "$ZIP" | head -1        # the top entry must be "Nanobrew UI.app/"
CHECK="$(mktemp -d)" && ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict --verbose=2 "$CHECK/Nanobrew UI.app"
shasum -a 256 "$ZIP"               # must equal the sha256 that bundle.sh printed
grep sha256 dist/nanobrew-ui.rb    # and the sha256 in the cask text
```

- **No `._` or `__MACOSX` entries.** AppleDouble files in the zip break the signature (nanobrew #425).
- **The signature passes** on the unpacked app, with `--deep --strict`.
- **The sha256 matches** in all three places: `shasum`, the script's output and the cask text.

## 3. Publish the GitHub release

```sh
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 "dist/Nanobrew-UI-1.0.0.zip" --repo Rex57/nanobrew-ui --title "Nanobrew UI 1.0.0"
```

- Run `gh` as the repository owner, Rex57.
- Upload one asset: the zip that you checked in step 2. A new build can give a new sha256, so never rebuild
  between the check and the upload.
- The asset URL must be `https://github.com/Rex57/nanobrew-ui/releases/download/v1.0.0/Nanobrew-UI-1.0.0.zip`.
  The cask builds this URL from its `version`.
- Check the uploaded file:

  ```sh
  curl -fsSL -o /tmp/nanobrew-ui-check.zip "https://github.com/Rex57/nanobrew-ui/releases/download/v1.0.0/Nanobrew-UI-1.0.0.zip"
  shasum -a 256 /tmp/nanobrew-ui-check.zip
  ```

## 4. Update the cask

Copy `dist/nanobrew-ui.rb` to `Casks/nanobrew-ui.rb` in `Rex57/homebrew-tap`, and push it to the default branch.
nb reads the file from `https://raw.githubusercontent.com/Rex57/homebrew-tap/HEAD/Casks/nanobrew-ui.rb`.

```ruby
cask "nanobrew-ui" do
  version "1.0.0"
  sha256 "<sha256 of the zip>"

  url "https://github.com/Rex57/nanobrew-ui/releases/download/v#{version}/Nanobrew-UI-#{version}.zip"

  depends_on macos: ">= :sonoma"

  app "Nanobrew UI.app"
end
```

| Line | Why |
|---|---|
| `version` | The version nb installs. |
| `sha256` | nb checks the download against it. |
| `url` with `#{version}` | A new release changes only `version` and `sha256`. |
| `depends_on macos` | States macOS 14 (Sonoma) or later for Homebrew and for people who read the file. nb's tap parser does not read it. |
| `app "Nanobrew UI.app"` | The one artifact: the app that goes to `/Applications`. |

**Why there is no `name`, `desc` or `homepage`.** nb's tap parser (`extractQuotedAfter` in nanobrew's
`src/api/tap.zig`) looks for a keyword such as `app `, `name ` or `desc ` anywhere in a line, and takes the next
quoted text after it. The cask holds only the lines nb needs, so no free text can match a keyword by mistake.
Without a `name` line, nb shows the token, `nanobrew-ui`, as the name.

## 5. Check the install

```sh
nb install --cask Rex57/tap/nanobrew-ui
open "/Applications/Nanobrew UI.app"
codesign --verify --deep --strict "/Applications/Nanobrew UI.app"
```

- The app opens with no Gatekeeper prompt.
- About shows the new version, "Tested with nb 0.1.214" and "Unofficial. Not made by the nanobrew maintainer."
- `codesign --verify` passes.

This is the one real cask test on a real nanobrew.

## What an upgrade needs

nb can upgrade an installed copy in place only when both are true:

1. **A newer version.** The cask file has a newer `version` than the installed copy, with the sha256 of the new
   zip.
2. **A zip.** nb upgrades a cask in place only when its download is a zip, a tar.gz, a tar.xz or a bare binary,
   and its artifacts are apps or binaries (`unsupportedReason` in nanobrew's `src/cask/upgrade.zig`). nb skips a
   disk image (nanobrew #491). The release is a zip with one app, so nb can upgrade it.

The user then upgrades with `nb upgrade --cask nanobrew-ui`, or with Upgrade on the app's Updates screen. After nb
exits with success, the app shows "Restart to use the new version". A real upgrade through the tap is not tested
yet: it needs a second version.

## The Gatekeeper limit

- The app is signed ad hoc, not with an Apple Developer ID, and it is not notarized.
- nb downloads the zip itself and does not set the quarantine flag, so Gatekeeper does not check the app, and it
  opens.
- A copy from `brew install --cask` or from a browser download gets the quarantine flag, and Gatekeeper blocks it.
  The README says so.
- macOS can ask again for the App Management permission after an update.
