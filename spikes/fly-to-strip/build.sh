#!/bin/bash
# Builds the throwaway spike into build/PodiumSpike.app
set -euo pipefail
cd "$(dirname "$0")"
APP=build/PodiumSpike.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/PodiumSpike" main.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.podium.spike</string>
  <key>CFBundleName</key><string>PodiumSpike</string>
  <key>CFBundleExecutable</key><string>PodiumSpike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
