# Sourced by the other scripts.
#
# With only the Command Line Tools installed (no Xcode), the macOS 27 SDK needs
# SwiftUI's macro plugin, which ships with Xcode. Fall back to the newest
# macOS 26 SDK in that case; it has everything Pianola uses.
DEV_DIR="$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)"
if [ -z "${SDKROOT:-}" ] && [ ! -e "$DEV_DIR/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ] \
   && [ ! -e "$DEV_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
  for sdk in "$DEV_DIR"/SDKs/MacOSX26.*.sdk "$DEV_DIR"/SDKs/MacOSX26.sdk; do
    if [ -d "$sdk" ]; then export SDKROOT="$sdk"; fi
  done
fi

# Swift Testing's macro plugin sits in a sub-folder the build does not search.
TEST_FLAGS=()
if [ -d "$DEV_DIR/usr/lib/swift/host/plugins/testing" ]; then
  TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing")
fi
