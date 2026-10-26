#!/bin/bash
# End-to-end check of automatic updates, entirely on this Mac. It never touches
# the real app: it builds an "old" (1.0) and a "new" (9.9) test copy with their
# own app ID, serves the new one from a local web server, starts the old one and
# waits for Sparkle to download it, check its signature and install it.
# Rebuilds the normal app at the end.
#
#   Scripts/test-update.sh              the update should install
#   Scripts/test-update.sh --forged     the update carries a wrong signature and must be refused
set -euo pipefail
FORGED=0
[ "${1:-}" = "--forged" ] && FORGED=1
cd "$(dirname "$0")/.."

TEST_ID=com.mahmudul.pianola.updatetest
PORT=8765
WORK="$(mktemp -d)"
SERVER="$WORK/server"
OLD="$WORK/Pianola.app"
LOG="$HOME/Library/Logs/Pianola/pianola.log"
TOOLS=.build/artifacts/sparkle/Sparkle/bin
FEED="http://127.0.0.1:$PORT/appcast.xml"
ATS='  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>'
mkdir -p "$SERVER"
touch "$LOG"

cleanup() {
  { kill "${SERVER_PID:-}" && wait "${SERVER_PID:-}"; } 2>/dev/null || true
  pkill -f "$OLD/Contents/MacOS/Pianola" 2>/dev/null || true
  defaults delete "$TEST_ID" >/dev/null 2>&1 || true
  rm -rf "$WORK" "$HOME/Library/Caches/$TEST_ID" "$HOME/Library/HTTPStorages/$TEST_ID" \
    "$HOME/Library/Application Support/$TEST_ID"
}
trap cleanup EXIT
pause() { perl -e "select(undef, undef, undef, $1)"; }

build() {
  BUNDLE_ID=$TEST_ID FEED_URL=$FEED EXTRA_PLIST="$ATS" APP_VERSION=$1 BUILD_NUMBER=$2 \
    Scripts/build-app.sh >/dev/null 2>&1
}

echo "› Building the old test copy (1.0)…"
build 1.0 100
ditto build/Pianola.app "$OLD"

echo "› Building the new test copy (9.9) and signing it…"
build 9.9 200
ditto -c -k --sequesterRsrc --keepParent build/Pianola.app "$SERVER/Pianola-9.9.zip"
SIGNATURE=$("$TOOLS/sign_update" --account pianola "$SERVER/Pianola-9.9.zip")
if [ "$FORGED" = 1 ]; then
  # A real signature, but of a different file: Pianola must refuse the download.
  echo "something else" > "$WORK/other"
  OTHER=$("$TOOLS/sign_update" --account pianola -p "$WORK/other")
  SIGNATURE=$(echo "$SIGNATURE" | sed -E "s|sparkle:edSignature=\"[^\"]+\"|sparkle:edSignature=\"$OTHER\"|")
fi
cat > "$SERVER/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Pianola test</title>
    <item>
      <title>Pianola 9.9</title>
      <sparkle:version>200</sparkle:version>
      <sparkle:shortVersionString>9.9</sparkle:shortVersionString>
      <enclosure url="http://127.0.0.1:$PORT/Pianola-9.9.zip" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVER" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
pause 1

echo "› Starting the old copy; it should update itself…"
MARK=$(wc -l < "$LOG")
open -n --env PIANOLA_UPDATE_TEST=1 --env PIANOLA_LIBRARY="$WORK/library.json" "$OLD"
NOW=""
for _ in $(seq 1 $([ "$FORGED" = 1 ] && echo 15 || echo 90)); do
  pause 1
  NOW=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OLD/Contents/Info.plist" 2>/dev/null || true)
  [ "$NOW" = "9.9" ] && break
done
pause 3
tail -n +"$((MARK + 1))" "$LOG" | sed 's/^/  log: /'
grep -o '"GET [^"]*" [0-9]*' "$WORK/server.log" | sed 's/^/  served: /' || true

STATUS=0
if [ "$FORGED" = 1 ]; then
  if [ "$NOW" = "1.0" ]; then
    echo "✓ The wrongly signed update was refused; the copy stayed at 1.0."
  else
    echo "✗ A wrongly signed update was installed!" >&2
    STATUS=1
  fi
elif [ "$NOW" = "9.9" ] && codesign --verify --strict "$OLD" 2>/dev/null; then
  echo "✓ The old copy updated itself from 1.0 to 9.9, and its signature is intact."
  pgrep -f "$OLD/Contents/MacOS/Pianola" >/dev/null && echo "✓ It relaunched as the new version."
else
  echo "✗ The update did not install (copy is at version ${NOW:-unknown})." >&2
  STATUS=1
fi

echo "› Rebuilding the normal app…"
Scripts/build-app.sh >/dev/null 2>&1
exit $STATUS
