#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source Scripts/toolchain-env.sh
source updates.env
NOTCHBROW_RELEASE_KEY=${NOTCHBROW_RELEASE_KEY:-"$HOME/Library/Application Support/NotchBrow/Release/update-key"}
if [[ ! -f "$NOTCHBROW_RELEASE_KEY" ]]; then
  echo "Missing release signing key: $NOTCHBROW_RELEASE_KEY" >&2
  exit 1
fi
Scripts/package_app.sh
"$SWIFT_EXEC" -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" Scripts/release_tool.swift -o .build/release-tool
mkdir -p build/release
ditto -c -k --keepParent --norsrc build/NotchBrow.app build/release/NotchBrow-universal.zip
.build/release-tool sign "$NOTCHBROW_RELEASE_KEY" build/NotchBrow.app build/release/NotchBrow-universal.zip build/release "$UPDATE_REPOSITORY" "$UPDATE_PUBLIC_KEY"
echo 'Upload all three files in build/release to the matching GitHub release.'
