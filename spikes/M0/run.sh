#!/bin/zsh
# Launches the app through LaunchServices so TCC treats it as its own
# responsible process (running the binary from a terminal would check the
# terminal's Accessibility permission instead). Output goes to build/spike.log.
set -euo pipefail
cd "$(dirname "$0")"
LOG=build/spike.log
: > "$LOG"
pkill -x DaylineSpike 2>/dev/null || true
open -n build/DaylineSpike.app --args "$@"
echo "logging to $PWD/$LOG"
