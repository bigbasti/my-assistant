#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product MyAssistant
BIN="$(swift build -c release --show-bin-path)"
APP="build/My Assistant.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MyAssistant" "$APP/Contents/MacOS/MyAssistant"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for f in Resources/*; do
  [ "$(basename "$f")" = "Info.plist" ] || cp "$f" "$APP/Contents/Resources/"
done
codesign -s - --force "$APP"
echo "Built $APP"
