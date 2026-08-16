#!/bin/bash
# Assembles DesktopGoose.app by hand — no Xcode required.
#
# Usage: ./Scripts/bundle.sh [release|debug] [native|universal]
#   ./Scripts/bundle.sh                     # release, this Mac's architecture
#   ./Scripts/bundle.sh debug               # debug build, native
#   ./Scripts/bundle.sh release universal   # both arches — what a Release ships
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
ARCH_MODE="${2:-native}"
APP="$ROOT/build/DesktopGoose.app"
mkdir -p "$ROOT/build"

case "$ARCH_MODE" in
universal)
    # Two single-arch passes merged with lipo. The combined `--arch a --arch b`
    # form routes through xcbuild (full Xcode); building each arch on its own and
    # merging by hand keeps the Command-Line-Tools-only promise.
    echo "==> Building universal ($CONFIGURATION): arm64 + x86_64"
    swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch arm64
    swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch x86_64
    ARM64="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch arm64 --show-bin-path)/DesktopGoose"
    X86_64="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --arch x86_64 --show-bin-path)/DesktopGoose"
    BINARY="$ROOT/build/DesktopGoose-universal"
    lipo -create "$ARM64" "$X86_64" -output "$BINARY"
    ;;
native)
    echo "==> Building native ($CONFIGURATION, $(uname -m))"
    swift build --package-path "$ROOT" -c "$CONFIGURATION"
    BINARY="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)/DesktopGoose"
    ;;
*)
    echo "Unknown arch mode: '$ARCH_MODE' (use 'native' or 'universal')" >&2
    exit 1
    ;;
esac

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/DesktopGoose"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Assets" "$APP/Contents/Resources/Assets"

# The app icon, if it has been generated (Scripts/make-icon.sh). Kept out of the
# Assets/ tree so it is not mistaken for runtime art.
if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
    cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature: enough to run locally. Distribution needs a Developer ID.
echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Done: $APP  [$(lipo -archs "$APP/Contents/MacOS/DesktopGoose")]"
echo "    Run it with: open \"$APP\""
