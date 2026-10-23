#!/bin/bash
# Runs the test suite. Each try uses a fresh scratch path: SwiftPM sometimes fails to load the
# TestingMacros plugin ("plugin for module 'TestingMacros' not found"); a retry passes.
set -uo pipefail
cd "$(dirname "$0")/.."

for try in 1 2 3 4 5 6 7 8; do
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/podium-test.XXXXXX")"
    out="$(swift test --scratch-path "$scratch" -j 1 "$@" 2>&1)"
    status=$?
    rm -rf "$scratch"
    if grep -q "plugin for module 'TestingMacros' not found" <<<"$out"; then
        echo "TestingMacros plugin not found (try $try); retrying" >&2
        continue
    fi
    echo "$out"
    exit $status
done
echo "TestingMacros plugin failed to load 8 times" >&2
exit 1
