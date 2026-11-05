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
  case "$(basename "$f")" in Info.plist|AppIcon.png) ;; *) cp "$f" "$APP/Contents/Resources/" ;; esac
done
# Version: VERSION holds major.minor; BUILD_NUMBER (set by CI) makes the patch/build number.
BUILD_NUMBER="${BUILD_NUMBER:-0}"
APP_VERSION="${APP_VERSION:-$(cat VERSION).${BUILD_NUMBER}}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
echo "Version $APP_VERSION (build $BUILD_NUMBER)"
# A stable identity keeps macOS privacy grants (Accessibility, Full Disk Access, Calendar,
# Automation) across rebuilds; ad-hoc signatures change with every build and reset them.
# Override with SIGN_IDENTITY="-" for ad-hoc, or another identity name/hash.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')}"
codesign -s "${IDENTITY:--}" --force --timestamp=none "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
