#!/bin/bash
# Builds dist/Pianola-<version>.dmg to share: a universal app (Apple Silicon
# and Intel), a shortcut to Applications, and install steps.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=1 Scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Pianola.app/Contents/Info.plist)

STAGE=build/dmg
rm -rf "$STAGE"
mkdir -p "$STAGE" dist
ditto build/Pianola.app "$STAGE/Pianola.app"
ln -s /Applications "$STAGE/Applications"
cp Scripts/dmg-readme.txt "$STAGE/Read Me First.txt"

cp build/AppIcon.icns "$STAGE/.VolumeIcon.icns"

DMG="dist/Pianola-$VERSION.dmg"
WORK=build/Pianola-rw.dmg
MOUNT="$(mktemp -d)"
rm -f "$DMG" "$WORK"
echo "› Creating $DMG…"
# Make a writable image first so the disk can be given the app's icon.
hdiutil create -volname "Pianola" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK" >/dev/null
hdiutil attach "$WORK" -nobrowse -noautoopen -mountpoint "$MOUNT" >/dev/null
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$WORK" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$WORK"
rmdir "$MOUNT" 2>/dev/null || true
echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
