#!/bin/bash
# Source this file; exports only project-local build configuration.
NOTCHBROW_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NOTCHBROW_NEEDS_OVERLAY=$(python3 "$NOTCHBROW_ROOT/Scripts/prepare-toolchain.py")
if [[ "$NOTCHBROW_NEEDS_OVERLAY" == "1" ]]; then
  export SWIFT_EXEC="$NOTCHBROW_ROOT/Scripts/swiftc-local.sh"
  export SWIFTPM_MODULECACHE_OVERRIDE="$NOTCHBROW_ROOT/.build/toolchain/clean-cache"
  if [[ -d "$NOTCHBROW_ROOT/.build/toolchain/pm/ManifestAPI" ]]; then
    export SWIFTPM_CUSTOM_LIBS_DIR="$NOTCHBROW_ROOT/.build/toolchain/pm"
  fi
fi
