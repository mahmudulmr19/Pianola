#!/bin/bash
# One-time setup for updates.
#
# Creates the key that signs Pianola updates (if you don't have one yet). The
# private half stays in your login Keychain; the public half is saved to
# Scripts/sparkle-public-key.txt and built into the app, so copies of Pianola
# only accept updates you signed.
#
# Back up the private key somewhere safe (a password manager, not this repo):
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys --account pianola -x pianola-update-key.txt
# If it is lost, existing copies of Pianola can't accept new updates.
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS=.build/artifacts/sparkle/Sparkle/bin
[ -x "$TOOLS/generate_keys" ] || swift package resolve >/dev/null

"$TOOLS/generate_keys" --account pianola >/dev/null
KEY="$("$TOOLS/generate_keys" --account pianola -p | tr -d '[:space:]')"
echo "$KEY" > Scripts/sparkle-public-key.txt
echo "✓ Update signing key ready. Public key saved to Scripts/sparkle-public-key.txt"
echo "  Back up the private key (see the top of this script)."
