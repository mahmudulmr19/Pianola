#!/bin/bash
# Publishes a new version of Pianola that installed copies update to.
#
#   Scripts/release.sh 1.2 "Fixed the mini player. Faster loading."
#
# It sets VERSION, builds the universal app and DMG, signs the update with
# your key (Scripts/setup-update-key.sh), writes appcast.xml, and creates the
# GitHub release v1.2 with the DMG (for new installs), the zip (for updates)
# and appcast.xml (which every copy of Pianola checks daily).
#
# Publishing needs the GitHub CLI: brew install gh, then gh auth login.
# Without it, the script stops after building and says what to upload.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="mahmudulmr19/Pianola"
VERSION="${1:-}"
NOTES="${2:-}"
TOOLS=.build/artifacts/sparkle/Sparkle/bin

if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Usage: Scripts/release.sh <version> \"what's new\"   (for example 1.2)" >&2
  exit 1
fi
if [ ! -s Scripts/sparkle-public-key.txt ]; then
  echo "No update signing key yet. Run Scripts/setup-update-key.sh first." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "Version $VERSION was already released (tag v$VERSION exists)." >&2
  exit 1
fi

echo "$VERSION" > VERSION
Scripts/make-dmg.sh

APP=build/Pianola.app
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG="dist/Pianola-$VERSION.dmg"
ZIP="dist/Pianola-$VERSION.zip"
APPCAST="dist/appcast.xml"

echo "› Signing the update…"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SIGNATURE=$("$TOOLS/sign_update" --account pianola "$ZIP")

python3 - "$APPCAST" "$VERSION" "$BUILD_NUMBER" \
  "https://github.com/$REPO/releases/download/v$VERSION/Pianola-$VERSION.zip" "$SIGNATURE" "$NOTES" <<'PY'
import html, re, sys
from email.utils import formatdate
path, version, build, url, signature, notes = sys.argv[1:]
attrs = dict(re.findall(r'(sparkle:edSignature|length)="([^"]+)"', signature))
body = "".join(f"<p>{html.escape(line)}</p>" for line in notes.splitlines() if line.strip()) or "<p>Improvements and fixes.</p>"
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pianola</title>
    <item>
      <title>Pianola {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<h2>Pianola {html.escape(version)}</h2>{body}]]></description>
      <enclosure url="{html.escape(url)}" type="application/octet-stream"
                 sparkle:edSignature="{attrs['sparkle:edSignature']}" length="{attrs['length']}"/>
    </item>
  </channel>
</rss>
'''
open(path, "w").write(xml)
PY
echo "✓ $APPCAST"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "  Note: you have uncommitted changes (at least VERSION). Commit and push them so the release matches your code."
fi

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  echo "› Publishing v$VERSION on GitHub…"
  gh release create "v$VERSION" "$DMG" "$ZIP" "$APPCAST" --repo "$REPO" \
    --title "Pianola $VERSION" --notes "${NOTES:-Improvements and fixes.}"
  echo "✓ Released. Copies of Pianola will offer $VERSION within a day, or now from Check for Updates…"
else
  echo
  echo "GitHub CLI not set up, so nothing was published. To publish by hand:"
  echo "  1. Open https://github.com/$REPO/releases/new"
  echo "  2. Tag: v$VERSION   Title: Pianola $VERSION"
  echo "  3. Upload these three files from the dist folder:"
  echo "       $DMG  $ZIP  $APPCAST"
  echo "  4. Click Publish release."
fi
