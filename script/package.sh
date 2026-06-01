#!/usr/bin/env bash
set -euo pipefail

# Builds release .app bundles for sharing (AirDrop / GitHub Releases):
#   • Pastil-universal.app  — arm64 + x86_64, runs on any Mac
#   • Pastil-arm64.app      — Apple Silicon only (smaller)
# plus a zip of each (ditto, so the .app survives the round-trip).
#
# Universal builds need both slices. Full Xcode's `swift build --arch a --arch b` would do
# it in one shot, but with only Command Line Tools we build each slice separately (x86_64
# under Rosetta) and lipo them together.
#
# Usage: bash script/package.sh [version]

APP_NAME="Pastil"
BUNDLE_ID="com.mohammadreza.Pastil"
VERSION="${1:-1.0.0}"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/release"
ICON_SRC="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$OUT_DIR"
cd "$ROOT_DIR"

echo "==> Building arm64 (native)"
swift build -c release
ARM_BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Building x86_64 (Rosetta)"
arch -x86_64 swift build -c release
X86_BIN="$(arch -x86_64 swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Creating universal binary"
UNIVERSAL_BIN="$OUT_DIR/.Pastil-universal-bin"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"

assemble() {
  local label="$1" srcbin="$2"
  # The bundle is always "Pastil.app" (no arch in the name); the arch lives in the zip
  # name and a per-variant staging dir keeps the two from colliding.
  local stage="$OUT_DIR/$label"
  local app="$stage/$APP_NAME.app"

  rm -rf "$stage"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$srcbin" "$app/Contents/MacOS/$APP_NAME"
  chmod +x "$app/Contents/MacOS/$APP_NAME"
  [ -f "$ICON_SRC" ] && cp "$ICON_SRC" "$app/Contents/Resources/AppIcon.icns"

  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Mohammadreza</string>
</dict>
</plist>
PLIST

  codesign --force --sign - "$app" >/dev/null 2>&1 || true
  ( cd "$stage" && rm -f "$OUT_DIR/$APP_NAME-$label.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$OUT_DIR/$APP_NAME-$label.zip" )

  printf '    %s  (%s)\n' "$app" "$(lipo -archs "$app/Contents/MacOS/$APP_NAME")"
  printf '    %s\n' "$OUT_DIR/$APP_NAME-$label.zip"
}

assemble "arm64" "$ARM_BIN"
assemble "universal" "$UNIVERSAL_BIN"
rm -f "$UNIVERSAL_BIN"

echo
echo "Done — artifacts in $OUT_DIR"