#!/bin/zsh
# (Re)starts the app through LaunchServices so TCC sees it as its own app.
# Log: ~/Library/Logs/Dayline/dayline.log. Report: .build/release/dayline-report
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -x DaylineAgent 2>/dev/null || true
pkill -x Dayline 2>/dev/null && sleep 1 || true
open -n build/Dayline.app
echo "running; log at ~/Library/Logs/Dayline/dayline.log"
