#!/bin/bash
# Builds build/NanoClip.app from the SwiftPM executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="NanoClip"
APP="$ROOT/build/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [ ! -x "$BIN" ]; then
  echo "error: binary not found at $BIN"
  exit 1
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICON="$ROOT/Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
  echo "==> generating icon"
  mkdir -p "$ROOT/Resources"
  swift "$ROOT/Scripts/GenerateAppIcon.swift" "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Local symbols are not needed at runtime and only grow the binary.
strip -x "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "==> codesign ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "ok: $APP ($(du -sh "$APP" | cut -f1))"