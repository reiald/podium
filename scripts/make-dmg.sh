#!/bin/bash
# Builds build/Podium-<version>.dmg: the signed app, an Applications shortcut and the installer background.
# The layout step drives Finder, so macOS asks once whether your terminal may control Finder.
# For a release others can open without a warning, sign with a Developer ID and notarize the result:
#   PODIUM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
volume="Podium"
rw="build/Podium-rw.dmg"
dmg="build/Podium-$version.dmg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

scripts/build-app.sh

mkdir -p "$stage/.background"
cp -R build/Podium.app "$stage/Podium.app"
ln -s /Applications "$stage/Applications"
cp design/kit/installer/background.tiff "$stage/.background/background.tiff"

# A disk image still mounted under the same name would take the layout commands instead.
if [ -d "/Volumes/$volume" ]; then hdiutil detach "/Volumes/$volume" -quiet || true; fi
rm -f "$rw" "$dmg"
hdiutil create -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw" >/dev/null
hdiutil attach "$rw" -readwrite -noverify -noautoopen >/dev/null

# Window content is 660 x 400 points; the extra 28 is the title bar. Icons are placed by their centers.
osascript <<EOF
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 860, 548}
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "Podium.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
hdiutil detach "/Volumes/$volume" -quiet
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"
echo "Built $dmg"
