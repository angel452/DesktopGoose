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

# The Windows build cannot be made on a Mac, so it comes from CI: the green push run
# for exactly this commit carries it as an artifact. Not a pull_request run, which
# builds the PR merged into main rather than this commit.
WIN_ZIP="$ROOT/build/DesktopGoose-windows-${VERSION}.zip"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
echo "==> Fetching the Windows build from CI for ${COMMIT:0:7}"
RUN_ID="$(gh run list --workflow CI --commit "$COMMIT" --event push --status success --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
if [[ -z "$RUN_ID" ]]; then
    echo "No successful CI run for ${COMMIT:0:7}. Push, wait for CI to go green, then retry." >&2
    exit 1
fi
rm -rf "$ROOT/build/windows" "$WIN_ZIP"
gh run download "$RUN_ID" --name DesktopGoose-windows --dir "$ROOT/build/windows"
# Without --norsrc --noextattr, ditto adds an AppleDouble `._*` twin for every file
# carrying an extended attribute, and the downloaded files all do. Windows shows
# those as stray files, among them a fake `._DesktopGoose.exe`.
ditto -c -k --norsrc --noextattr --keepParent "$ROOT/build/windows/DesktopGoose" "$WIN_ZIP"
echo "    $WIN_ZIP"

echo "==> Publishing GitHub Release $TAG"
# Written for people who have never used GitHub: exact file and button names, one
# recipe per system, and nothing technical above the fold.
NOTES="$(cat <<EOF
## Which file do I download?

Scroll down to **Assets** and click the file for your computer. **Do not** download "Source code" — that is for programmers.

| Your computer | Download this file |
|---|---|
| 🪟 Windows | **DesktopGoose-windows-${VERSION}.zip** |
| 🍎 Mac | **DesktopGoose-${VERSION}.zip** |

## 🪟 Windows

1. Download **DesktopGoose-windows-${VERSION}.zip**. If your browser warns that the file is not commonly downloaded, choose **Keep**.
2. Open your **Downloads** folder, **right-click** the zip and choose **Extract All…**, then click **Extract**. (Do not just double-click the zip — the goose cannot start from inside it.)
3. In the folder that opens, double-click **DesktopGoose**.
4. A blue window may say **"Windows protected your PC"**. Click **More info**, then **Run anyway**. It only asks the first time. The app is free and safe; it just is not signed with a paid certificate.
5. Done! The goose is on your screen. To quit, find the goose icon next to the clock (click the **^** arrow if you cannot see it), click it, and choose **Quit Desktop Goose**.

## 🍎 Mac

1. Download **DesktopGoose-${VERSION}.zip**.
2. Open your **Downloads** folder and double-click the zip. A **DesktopGoose** app appears (Safari may already have done this for you).
3. Drag **DesktopGoose** into your **Applications** folder.
4. Open **Applications** and double-click **DesktopGoose**. The first time, macOS says it could not verify the app. Click **Done** — **not** "Move to Trash".
5. Open the  menu → **System Settings** → **Privacy & Security**. Scroll to the bottom and click **Open Anyway** next to the Desktop Goose message. Enter your password (or use Touch ID) and click **Open Anyway** once more. You only do this once.
6. Done! The goose is on your screen. To quit, click 🪿 at the top right of the screen and choose **Quit Desktop Goose**.

Works on every Mac with macOS 14 or newer, and on Windows 10 and 11.
EOF
)"

# --target pins the tag to the commit the Windows exe was built from; without it a
# new tag lands on the default branch tip.
gh release create "$TAG" "$ZIP" "$WIN_ZIP" \
    --target "$COMMIT" \
    --title "Desktop Goose $TAG" \
    --notes "$NOTES"

echo "==> Published: $TAG"
