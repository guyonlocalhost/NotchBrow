#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NOTCHBROW_COMPILER=$(cat "$ROOT/.build/toolchain/compiler-path")
exec "$NOTCHBROW_COMPILER" -vfsoverlay "$ROOT/.build/toolchain/overlay.json" "$@"
