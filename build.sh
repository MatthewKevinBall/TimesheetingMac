#!/bin/bash
# Builds build/JobTimer.app. Run with "install" to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/JobTimer.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

if [ ! -f build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  mkdir -p build/AppIcon.iconset
  swift Scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JobTimer" "$APP/Contents/MacOS/JobTimer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x JobTimer && sleep 1 || true
  rm -rf /Applications/JobTimer.app
  cp -R "$APP" /Applications/
  open /Applications/JobTimer.app
  echo "Installed and launched /Applications/JobTimer.app"
fi
