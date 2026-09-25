#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/Scripts/toolchain-env.sh"
swift run NotchBrowChecks
if [[ "${1:-}" == "--release" ]]; then
  NOTCHBROW_TEST_APP="$ROOT/build/NotchBrow.app/Contents/MacOS/NotchBrow"
else
  swift build --product NotchBrow
  NOTCHBROW_TEST_APP="$ROOT/.build/debug/NotchBrow"
fi
mkdir -p build/smoke
rm -f build/smoke/failure.txt
export NOTCHBROW_OVERLAY_FIXTURE="$ROOT/.build/overlay-fixture"
if [[ ! -x "$NOTCHBROW_OVERLAY_FIXTURE" || Scripts/overlay_fixture.swift -nt "$NOTCHBROW_OVERLAY_FIXTURE" ]]; then
  "${SWIFT_EXEC:-$(xcrun --find swiftc)}" -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" Scripts/overlay_fixture.swift -o "$NOTCHBROW_OVERLAY_FIXTURE"
fi
NOTCHBROW_PORT_FILE=$(mktemp)
python3 Scripts/test_server.py "$NOTCHBROW_PORT_FILE" &
NOTCHBROW_SERVER_PID=$!
trap 'kill "$NOTCHBROW_SERVER_PID" 2>/dev/null || true; rm -f "$NOTCHBROW_PORT_FILE"' EXIT
for attempt in {1..50}; do
  [[ -s "$NOTCHBROW_PORT_FILE" ]] && break
  sleep 0.1
done
export NOTCHBROW_TEST_BASE_URL="http://127.0.0.1:$(cat "$NOTCHBROW_PORT_FILE")"
"$NOTCHBROW_TEST_APP" --smoke-test "$ROOT/build/smoke"
