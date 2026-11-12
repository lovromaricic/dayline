#!/bin/zsh
# Builds Dayline and installs it to /Applications, replacing a running copy.
# The Accessibility grant carries over: it is tied to the bundle id and the
# signing certificate, not to the location.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x Dayline 2>/dev/null && sleep 1 || true
rm -rf /Applications/Dayline.app
cp -R build/Dayline.app /Applications/Dayline.app
open /Applications/Dayline.app
echo "installed /Applications/Dayline.app"
