#!/bin/bash
# Builds build/Pianola.app.
#   Scripts/build-app.sh                   release build for this Mac
#   Scripts/build-app.sh debug             debug build
#   UNIVERSAL=1 Scripts/build-app.sh       runs on Apple Silicon and Intel
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh

CONFIG="${1:-release}"
APP="build/Pianola.app"
VERSION="1.0"
ARCHS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi

echo "› Building ($CONFIG${UNIVERSAL:+, universal})…"
swift build -c "$CONFIG" --product Pianola ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Pianola"

mkdir -p build
if [ ! -f build/AppIcon.icns ] || [ Scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "› Drawing the icon…"
  swiftc -O Scripts/make-icon.swift -o build/make-icon
  build/make-icon build/icon-1024.png >/dev/null
  rm -rf build/AppIcon.iconset
  mkdir build/AppIcon.iconset
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

echo "› Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pianola"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pianola</string>
  <key>CFBundleDisplayName</key><string>Pianola</string>
  <key>CFBundleIdentifier</key><string>com.mahmudul.pianola</string>
  <key>CFBundleExecutable</key><string>Pianola</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Plays Roblox piano sheets with PianoBlox timing.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. By default macOS ties the Accessibility permission to a
# fingerprint of this exact build, so every rebuild would lose it. Naming the
# bundle identifier as the app's identity keeps the permission across rebuilds.
codesign --force --sign - --identifier com.mahmudul.pianola \
  --requirements '=designated => identifier "com.mahmudul.pianola"' "$APP"
echo "✓ $APP"
