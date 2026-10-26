#!/bin/bash
# Builds build/Pianola.app.
#   Scripts/build-app.sh                   release build for this Mac
#   Scripts/build-app.sh debug             debug build
#   UNIVERSAL=1 Scripts/build-app.sh       runs on Apple Silicon and Intel
#
# The version number comes from the VERSION file. Updates are checked against
# the appcast attached to the latest GitHub release, signed with the key in
# Scripts/sparkle-public-key.txt (see Scripts/setup-update-key.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh

CONFIG="${1:-release}"
APP="build/Pianola.app"
VERSION="${APP_VERSION:-$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 1.0)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
# These can be overridden to test updates without touching the real app
# (see Scripts/test-update.sh).
BUNDLE_ID="${BUNDLE_ID:-com.mahmudul.pianola}"
FEED_URL="${FEED_URL:-https://github.com/mahmudulmr19/Pianola/releases/latest/download/appcast.xml}"
EXTRA_PLIST="${EXTRA_PLIST:-}"
PUBLIC_KEY="$(tr -d '[:space:]' < Scripts/sparkle-public-key.txt 2>/dev/null || true)"
ARCHS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi

echo "› Building ${VERSION} ($CONFIG${UNIVERSAL:+, universal})…"
swift build -c "$CONFIG" --product Pianola ${ARCHS[@]+"${ARCHS[@]}"}
PRODUCTS="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

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

# Update settings go in Info.plist only when there is a signing key.
UPDATE_KEYS=""
if [ -n "$PUBLIC_KEY" ]; then
  UPDATE_KEYS="  <key>SUFeedURL</key><string>${FEED_URL}</string>
  <key>SUPublicEDKey</key><string>${PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>"
else
  echo "  (no update signing key yet: this build won't check for updates)"
fi

echo "› Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/Pianola" "$APP/Contents/MacOS/Pianola"
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Pianola</string>
  <key>CFBundleDisplayName</key><string>Pianola</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>Pianola</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Plays Roblox piano sheets with PianoBlox timing.</string>
${UPDATE_KEYS}
${EXTRA_PLIST}
</dict>
</plist>
PLIST

# Ad-hoc signature. By default macOS ties the Accessibility permission to a
# fingerprint of this exact build, so every rebuild (and every update) would
# lose it. Naming the bundle identifier as the app's identity keeps it.
# Sparkle.framework keeps the Sparkle project's own signature.
codesign --force --sign - --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"${BUNDLE_ID}\"" "$APP"
echo "✓ $APP"
