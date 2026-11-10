#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/signing.py check
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
APP="$PWD/dist/KeyPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/KeyPilot" "$APP/Contents/MacOS/KeyPilot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LocalBuild.txt "$APP/Contents/Resources/LocalBuild.txt"
"$BIN_DIR/KeyPilot" --export-brand "$PWD/artifacts/brand"
iconutil -c icns "$PWD/artifacts/brand/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Brand/KeyPilot.svg "$APP/Contents/Resources/KeyPilot.svg"
python3 scripts/signing.py sign "$APP"
"$APP/Contents/MacOS/KeyPilot" --self-check
