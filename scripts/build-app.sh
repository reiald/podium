#!/bin/bash
# Builds build/Podium.app and signs it with a stable identity.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${PODIUM_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identities="$(security find-identity -p codesigning || true)"
    identity="$(echo "$identities" | grep -m1 "Apple Development" | sed -E 's/.*"(.*)".*/\1/' || true)"
    if [ -z "$identity" ]; then
        identity="$(echo "$identities" | grep -m1 "Podium Dev" | sed -E 's/.*"(.*)".*/\1/' || true)"
    fi
fi
if [ -z "$identity" ]; then
    echo "No signing identity found. Run scripts/make-dev-cert.sh first" >&2
    exit 1
fi

swift build -c release --product Podium
bin="$(swift build -c release --product Podium --show-bin-path)"

app="build/Podium.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Podium" "$app/Contents/MacOS/Podium"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp Resources/PodiumMenuTemplate*.png "$app/Contents/Resources/"

# Notarization needs the hardened runtime and a secure timestamp, which only Developer ID signing can use.
flags=()
case "$identity" in "Developer ID"*) flags=(--options runtime --timestamp) ;; esac
codesign --force ${flags[@]+"${flags[@]}"} --sign "$identity" "$app"
echo "Built $app (signed: $identity)"
