#!/bin/zsh
# Builds build/Dayline.app (the menu bar app) and signs it with a stable
# identity so the Accessibility grant survives rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Dayline
swift build -c release --product dayline-report
APP=build/Dayline.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Dayline "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign "${SIGN_IDENTITY:-Apple Development}" "$APP"
echo "built $APP"
