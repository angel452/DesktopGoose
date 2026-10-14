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

# The Windows build cannot be made on a Mac, so it comes from CI: the green CI run
# for exactly this commit carries it as an artifact.
WIN_ZIP="$ROOT/build/DesktopGoose-windows-${VERSION}.zip"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
echo "==> Fetching the Windows build from CI for ${COMMIT:0:7}"
RUN_ID="$(gh run list --workflow CI --commit "$COMMIT" --status success --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
if [[ -z "$RUN_ID" ]]; then
    echo "No successful CI run for ${COMMIT:0:7}. Push, wait for CI to go green, then retry." >&2
    exit 1
fi
rm -rf "$ROOT/build/windows" "$WIN_ZIP"
gh run download "$RUN_ID" --name DesktopGoose-windows --dir "$ROOT/build/windows"
ditto -c -k --keepParent "$ROOT/build/windows/DesktopGoose" "$WIN_ZIP"
echo "    $WIN_ZIP"

echo "==> Publishing GitHub Release $TAG"
gh release create "$TAG" "$ZIP" "$WIN_ZIP" \
    --title "Desktop Goose $TAG" \
    --notes "**Windows:** download **DesktopGoose-windows-${VERSION}.zip**, unzip it anywhere, and double-click **DesktopGoose.exe**. If SmartScreen says \"Windows protected your PC\", click **More info → Run anyway** (once — the app is free and unsigned). The goose lives in the system tray, next to the clock.

**macOS:** download **DesktopGoose-${VERSION}.zip**, unzip, and drag the app to /Applications.

**First launch:** double-click it, then approve it once in **System Settings → Privacy & Security → Open Anyway** (the app is ad-hoc signed, so Gatekeeper asks the first time — the old right-click → Open shortcut was removed in macOS 15). After that, double-click as usual. Prefer the Terminal? \`xattr -dr com.apple.quarantine /Applications/DesktopGoose.app\` does the same.

The goose lives in the menu bar as 🪿 — quit it from there. Universal build: runs on Apple Silicon and Intel."

echo "==> Published: $TAG"
