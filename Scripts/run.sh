#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ ! -d "$ROOT/build/NotchBrow.app" ]]; then "$ROOT/Scripts/package_app.sh"; fi
open "$ROOT/build/NotchBrow.app"
