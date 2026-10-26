#!/bin/bash
# Runs the engine tests.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain.sh
swift test "${TEST_FLAGS[@]}" "$@"
