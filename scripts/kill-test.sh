#!/bin/bash
# Crash test: parks TextEdit windows, kill -9s Podium at a random moment, relaunches it,
# and checks that every TextEdit window is fully back on screen. Needs Accessibility
# permission for build/Podium.app. Run scripts/build-app.sh first.
#
# Only touches TextEdit documents this script creates; refuses to start if any other
# TextEdit document is open.
set -uo pipefail
cd "$(dirname "$0")/.."

app="build/Podium.app"
bundle="com.apple.TextEdit"
runs=10
marker="$HOME/Library/Application Support/Podium/debug-parked"  # written by Podium after a debug park
docs=()        # names of the TextEdit documents this script created
started=0
cleaned=0

die() { echo "kill-test: $*" >&2; exit 1; }

wait_until_gone() {
    for _ in $(seq 1 50); do pgrep -x Podium >/dev/null || return 0; sleep 0.1; done
    echo "kill-test: Podium did not exit" >&2; return 1
}

# SIGTERM: Podium restores every parked window before exiting.
quit_podium() { pkill -x Podium; wait_until_gone; }

# AppleScript that creates 3 TextEdit documents and prints their names, one per line.
# (Kept out of $(...): bash 3.2 misparses quotes in a heredoc inside command substitution.)
read -r -d '' MAKE_DOCS <<'EOF'
tell application "TextEdit"
    activate
    set made to {}
    repeat 3 times
        set d to make new document
        set end of made to name of d
    end repeat
    set AppleScript's text item delimiters to linefeed
    return made as text
end tell
EOF

# Creates 3 TextEdit documents and remembers their names.
open_docs() {
    local out name
    out="$(osascript -e "$MAKE_DOCS")" || return 1
    while IFS= read -r name; do [ -n "$name" ] && docs+=("$name"); done <<< "$out"
}

# Closes, without saving, only the documents this script created.
close_docs() {
    [ "${#docs[@]}" -eq 0 ] && return 0
    osascript - "${docs[@]}" >/dev/null <<'EOF'
on run argv
    tell application "TextEdit"
        repeat with n in argv
            close (every document whose name is (n as text)) saving no
        end repeat
    end tell
end run
EOF
    docs=()
}

cleanup() {
    [ "$cleaned" -eq 1 ] && return
    cleaned=1
    [ "$started" -eq 1 ] || return
    pgrep -x Podium >/dev/null && quit_podium
    # Relaunch so launch-time recovery restores anything a kill -9 left parked.
    open "$app"
    sleep 3
    quit_podium
    close_docs
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ -d "$app" ] || die "missing $app; run scripts/build-app.sh first"

existing="$(osascript -e 'tell application "TextEdit" to count documents')" || die "cannot talk to TextEdit"
[ "$existing" -eq 0 ] || die "TextEdit has $existing document(s) open; close them first so none can be lost"

started=1
pgrep -x Podium >/dev/null && { quit_podium || exit 1; }

# Preflight (no kill): prove that parking really happens and that quitting restores.
echo "preflight: parking without a kill"
rm -f "$marker"
open_docs || die "could not create TextEdit documents"
sleep 1
since="$(date '+%Y-%m-%d %H:%M:%S')"
open "$app" --args --debug-park-bundle "$bundle"
sleep 3
log show --start "$since" --style compact --predicate 'process == "Podium"' 2>/dev/null \
    | grep -q 'AXIsProcessTrusted=1' \
    || die "preflight: no 'AXIsProcessTrusted=1' in Podium's log; grant Accessibility to $app"
[ -f "$marker" ] || die "preflight: Podium did not report parking any window"
swift scripts/check-onscreen.swift "$bundle"
rc=$?
[ "$rc" -eq 1 ] || die "preflight: expected parked windows off screen (exit 1), got exit $rc"
quit_podium || exit 1
sleep 1
swift scripts/check-onscreen.swift "$bundle" --min 3 || die "preflight: quitting Podium did not restore the windows"
close_docs
echo "preflight: OK"

passed=0
after_park=0
for i in $(seq 1 "$runs"); do
    rm -f "$marker"
    open_docs || die "could not create TextEdit documents"
    sleep 1

    open "$app" --args --debug-park-bundle "$bundle"
    delay="$(awk -v r="$RANDOM" 'BEGIN { printf "%.2f", 0.2 + (r / 32767) * 1.8 }')"
    sleep "$delay"
    pkill -9 -x Podium
    wait_until_gone || exit 1
    when="before park"
    if [ -f "$marker" ]; then after_park=$((after_park + 1)); when="after park"; fi

    open "$app"
    sleep 3
    if swift scripts/check-onscreen.swift "$bundle" --min 3; then
        passed=$((passed + 1))
        echo "run $i (kill after ${delay}s, $when): PASS"
    else
        echo "run $i (kill after ${delay}s, $when): FAIL"
    fi

    quit_podium || exit 1
    close_docs
done

echo "$passed/$runs passed"
echo "$after_park/$runs kills happened after parking"
[ "$after_park" -gt 0 ] || { echo "kill-test: no kill happened after parking; the test proved nothing" >&2; exit 1; }
[ "$passed" -eq "$runs" ]
