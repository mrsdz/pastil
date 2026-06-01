#!/usr/bin/env bash
set -euo pipefail

# Renders the app icon and assembles Resources/AppIcon.icns.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Resources"
WORK="$(mktemp -d)"
SRC="$WORK/icon_1024.png"
ICONSET="$WORK/AppIcon.iconset"

trap 'rm -rf "$WORK"' EXIT

swift "$ROOT_DIR/script/make_icon.swift" "$SRC"

mkdir -p "$ICONSET" "$RES_DIR"
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
echo "Wrote $RES_DIR/AppIcon.icns"
