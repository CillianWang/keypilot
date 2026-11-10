#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/signing.py check
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    echo "Usage: bash scripts/build.sh [--universal]" >&2
    exit 2
fi
BUILD_OPTIONS=(-c release --product KeyPilot)
if [[ -n "${KEYPILOT_SDK:-}" ]]; then
    BUILD_OPTIONS+=(--sdk "$KEYPILOT_SDK")
fi
if [[ -n "${KEYPILOT_BUILD_SYSTEM:-}" ]]; then
    BUILD_OPTIONS+=(--build-system "$KEYPILOT_BUILD_SYSTEM")
fi
APP="$PWD/dist/KeyPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    BINARIES=()
    for ARCH in arm64 x86_64; do
        OPTIONS=("${BUILD_OPTIONS[@]}" --scratch-path "$PWD/.build/distribution-compatible" --triple "$ARCH-apple-macosx13.0")
        swift build "${OPTIONS[@]}"
        BIN_DIR=$(swift build "${OPTIONS[@]}" --show-bin-path)
        BINARIES+=("$BIN_DIR/KeyPilot")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/KeyPilot"
else
    swift build "${BUILD_OPTIONS[@]}"
    BIN_DIR=$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)
    cp "$BIN_DIR/KeyPilot" "$APP/Contents/MacOS/KeyPilot"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LocalBuild.txt "$APP/Contents/Resources/LocalBuild.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
"$APP/Contents/MacOS/KeyPilot" --export-brand "$PWD/artifacts/brand"
iconutil -c icns "$PWD/artifacts/brand/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Brand/KeyPilot.svg "$APP/Contents/Resources/KeyPilot.svg"
python3 scripts/signing.py sign "$APP"
"$APP/Contents/MacOS/KeyPilot" --self-check
