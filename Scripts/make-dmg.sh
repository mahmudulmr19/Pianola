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
WORK=build/Pianola-work.dmg
MOUNT=build/dmg-mount
rm -f "$DMG" "$WORK"
echo "› Creating ${DMG}…"
# Runs a command silently, but shows its output if it fails.
quiet() { local out; if ! out=$("$@" 2>&1); then echo "$out" >&2; return 1; fi; }
# Make a writable (raw) image first so the disk can be given the app's icon,
# then compress it. diskutil makes the volume APFS, which macOS 26 reads.
quiet diskutil image create from "$STAGE" "$WORK" --format RAW --volumeName "Pianola"
quiet diskutil image attach "$WORK" --nobrowse --mountPoint "$MOUNT"
SetFile -a C "$MOUNT"
quiet diskutil eject "$MOUNT"
quiet diskutil image create from "$WORK" "$DMG" --format UDZO
rm -f "$WORK"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
