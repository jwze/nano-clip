#!/bin/bash
# nano-clip — 轻量 macOS 剪贴板历史
# Copyright © 2026 jvz <them@live.cn>. All rights reserved.
# Watermark: jvz·NanoClip — 电子水印，请勿移除本署名头。

# Installs build/NanoClip.app into /Applications, replacing the previous copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/build/NanoClip.app"
DESTINATION="/Applications/NanoClip.app"

if [ ! -d "$SOURCE" ]; then
  echo "error: $SOURCE not found — run Scripts/build-app.sh first"
  exit 1
fi

if pgrep -x NanoClip >/dev/null 2>&1; then
  echo "==> quitting running NanoClip"
  osascript -e 'quit app "NanoClip"' >/dev/null 2>&1 || pkill -x NanoClip || true
  sleep 1
fi

echo "==> installing to $DESTINATION"
rm -rf "$DESTINATION"
cp -R "$SOURCE" "$DESTINATION"

# Ad-hoc signatures change per build, so the Accessibility grant must be refreshed by the user.
echo "==> launching"
open "$DESTINATION"
echo "installed: $DESTINATION"