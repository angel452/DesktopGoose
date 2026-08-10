#!/bin/bash
# Assembles DesktopGoose.app by hand — no Xcode required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/DesktopGoose.app"

echo "==> Building ($CONFIGURATION)"
swift build --package-path "$ROOT" -c "$CONFIGURATION"

BINARY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)/DesktopGoose"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/DesktopGoose"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Assets" "$APP/Contents/Resources/Assets"

# Ad-hoc signature: enough to run locally. Distribution needs a Developer ID.
echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Done: $APP"
echo "    Run it with: open \"$APP\""
