#!/bin/bash
# Regenerates Support/AppIcon.icns from the goose sprite.
#
# The 1024x1024 master is rendered by `Preview --icon` (the goose magnified on a
# rounded sky tile), then sips scales it to every size iconutil expects. Re-run
# this after changing the goose's drawing so the app icon matches the sprite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT/build/AppIcon-1024.png"
ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/Support/AppIcon.icns"

echo "==> Rendering 1024 master"
swift run --package-path "$ROOT" Preview --icon >/dev/null

echo "==> Building iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# Apple wants each base size at 1x and 2x.
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Packing $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Done: $ICNS"
