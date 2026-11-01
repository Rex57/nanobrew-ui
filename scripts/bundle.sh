#!/bin/bash
# Builds the release binary into "dist/Nanobrew UI.app" with its icon, signs it ad hoc, zips it as
# dist/Nanobrew-UI-<version>.zip (no AppleDouble entries), prints the zip's sha256 and writes
# dist/nanobrew-ui.rb, the cask text for the Rex57/homebrew-tap repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.1"
DIST="$ROOT/dist"
APP="$DIST/Nanobrew UI.app"
ZIP="$DIST/Nanobrew-UI-$VERSION.zip"

swift build -c release --package-path "$ROOT"
BINDIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"
BIN="$BINDIR/NanobrewUI"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NanobrewUI"
# NanobrewKit's resources (the Lucide icons and the logo) go in Contents/Resources, where codesign seals them.
cp -R "$BINDIR/NanobrewUI_NanobrewKit.bundle" "$APP/Contents/Resources/"

# The icon at every size, from nanobrew's logo (scripts/make-icon.swift).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift "$ROOT/scripts/make-icon.swift" "$ROOT/Sources/NanobrewKit/Resources/nanobrew-logo.png" "$WORK/icon_1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Nanobrew UI</string>
    <key>CFBundleDisplayName</key><string>Nanobrew UI</string>
    <key>CFBundleIdentifier</key><string>io.github.rex57.nanobrew-ui</string>
    <key>CFBundleExecutable</key><string>NanobrewUI</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Extended attributes become ._ files in a zip and break the signature (nanobrew #425).
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# --norsrc: no AppleDouble (._) entries; --keepParent: the zip holds "Nanobrew UI.app/".
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"

cat > "$DIST/nanobrew-ui.rb" <<CASK
cask "nanobrew-ui" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/Rex57/nanobrew-ui/releases/download/v#{version}/Nanobrew-UI-#{version}.zip"

  depends_on macos: ">= :sonoma"

  app "Nanobrew UI.app"
end
CASK

echo "$APP"
echo "$ZIP"
echo "sha256: $SHA"
echo "cask: $DIST/nanobrew-ui.rb"
