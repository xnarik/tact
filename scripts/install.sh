#!/bin/bash
# Builds Tact, signs it and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Tact.app
ICONSET=build/Tact.iconset

swift build -c release --product Tact
swift build -c release --product TactSnapshots

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tact "$APP/Contents/MacOS/Tact"
cp Resources/Info.plist "$APP/Contents/Info.plist"
.build/release/TactSnapshots icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Tact.icns"

# A real certificate keeps the same identity across rebuilds, so macOS remembers the
# Accessibility and Keychain permissions. Ad-hoc signing makes macOS forget them every time.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -1)
if [ -z "$IDENTITY" ]; then
    echo "No Apple Development certificate found, so signing ad-hoc."
    echo "macOS may ask for permissions again after each rebuild."
    IDENTITY="-"
fi
codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

pkill -x Tact 2>/dev/null || true
rm -rf /Applications/Tact.app
cp -R "$APP" /Applications/Tact.app
open /Applications/Tact.app
echo "Installed /Applications/Tact.app"
