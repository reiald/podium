#!/bin/bash
# Crash test: parks TextEdit windows, kill -9s Podium at a random moment, relaunches it,
# and checks that every TextEdit window is fully back on screen. Needs Accessibility
# permission for build/Podium.app. Run scripts/build-app.sh first.
set -uo pipefail
cd "$(dirname "$0")/.."

app="build/Podium.app"
bundle="com.apple.TextEdit"
runs=10
[ -d "$app" ] || { echo "Missing $app; run scripts/build-app.sh first" >&2; exit 1; }

wait_until_gone() {
    for _ in $(seq 1 50); do pgrep -x Podium >/dev/null || return 0; sleep 0.1; done
    echo "Podium did not exit" >&2; return 1
}

pkill -x Podium; wait_until_gone || exit 1

passed=0
for i in $(seq 1 "$runs"); do
    osascript -e 'tell application "TextEdit"' -e 'activate' \
              -e 'repeat 3 times' -e 'make new document' -e 'end repeat' -e 'end tell' >/dev/null
    sleep 1

    open "$app" --args --debug-park-bundle "$bundle"
    delay="$(awk -v r="$RANDOM" 'BEGIN { printf "%.2f", 0.2 + (r / 32767) * 1.8 }')"
    sleep "$delay"
    pkill -9 -x Podium
    wait_until_gone || exit 1

    open "$app"
    sleep 3
    if swift scripts/check-onscreen.swift "$bundle" --min 3; then
        passed=$((passed + 1))
        echo "run $i (kill after ${delay}s): PASS"
    else
        echo "run $i (kill after ${delay}s): FAIL"
    fi

    pkill -x Podium; wait_until_gone || exit 1
    osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null
done

echo "$passed/$runs passed"
[ "$passed" -eq "$runs" ]
