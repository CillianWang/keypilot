#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
python3 scripts/test-install-migration.py
swift test 2>&1 | tee artifacts/core-tests.txt
swift run Keylian --render-fixture "$PWD/artifacts/overlay.png" > artifacts/renderer.json
python3 scripts/verify-renderer.py
python3 scripts/verify-signing.py
