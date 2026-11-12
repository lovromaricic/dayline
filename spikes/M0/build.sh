#!/bin/zsh
# Builds DaylineSpike.app and signs it with a stable identity so the
# Accessibility grant survives rebuilds (ad-hoc signatures change every build).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/DaylineSpike.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DaylineSpike "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign "${SIGN_IDENTITY:-Apple Development}" "$APP"
echo "built $APP"
