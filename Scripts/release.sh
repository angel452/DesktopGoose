#!/bin/bash
# Packages a universal DesktopGoose.app as a zip for a GitHub Release, so non-dev
# users can download and run it without a Swift toolchain.
#
# Usage:
#   ./Scripts/release.sh            # build + zip into build/, then print next steps
#   ./Scripts/release.sh v0.2.0     # also publish a GitHub Release under that tag
#
# The zip is ad-hoc signed (no Developer ID), so first launch needs a one-time
# approval in System Settings > Privacy & Security > Open Anyway. See
# docs/RELEASING.md for the full flow and when to cut a release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-}"
APP="$ROOT/build/DesktopGoose.app"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Support/Info.plist")"
ZIP="$ROOT/build/DesktopGoose-${VERSION}.zip"

echo "==> Refreshing the app icon"
"$ROOT/Scripts/make-icon.sh"

echo "==> Building the universal .app (v$VERSION)"
"$ROOT/Scripts/bundle.sh" release universal

echo "==> Zipping"
rm -f "$ZIP"
# ditto keeps the bundle structure, symlinks and the code signature intact — a
# plain `zip` would corrupt the app.
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP  [$(lipo -archs "$APP/Contents/MacOS/DesktopGoose")]"

if [[ -z "$TAG" ]]; then
    cat <<EOF

Zip is ready but NOT published. To publish a GitHub Release for non-dev users:

    ./Scripts/release.sh v$VERSION

(bump CFBundleShortVersionString in Support/Info.plist first if this is a new version)
EOF
    exit 0
fi

echo "==> Publishing GitHub Release $TAG"
gh release create "$TAG" "$ZIP" \
    --title "Desktop Goose $TAG" \
    --notes "Download **DesktopGoose-${VERSION}.zip**, unzip, and drag the app to /Applications.

**First launch:** double-click it, then approve it once in **System Settings → Privacy & Security → Open Anyway** (the app is ad-hoc signed, so Gatekeeper asks the first time — the old right-click → Open shortcut was removed in macOS 15). After that, double-click as usual. Prefer the Terminal? \`xattr -dr com.apple.quarantine /Applications/DesktopGoose.app\` does the same.

The goose lives in the menu bar as 🪿 — quit it from there. Universal build: runs on Apple Silicon and Intel."

echo "==> Published: $TAG"
