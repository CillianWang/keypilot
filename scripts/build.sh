#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/signing.py check
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    echo "Usage: bash scripts/build.sh [--universal]" >&2
    exit 2
fi
BUILD_OPTIONS=(-c release --product Keylian)
KEYLIAN_SDK="${KEYLIAN_SDK:-${KEYPILOT_SDK:-}}"
KEYLIAN_BUILD_SYSTEM="${KEYLIAN_BUILD_SYSTEM:-${KEYPILOT_BUILD_SYSTEM:-}}"
if [[ -n "$KEYLIAN_SDK" ]]; then
    BUILD_OPTIONS+=(--sdk "$KEYLIAN_SDK")
fi
if [[ -n "$KEYLIAN_BUILD_SYSTEM" ]]; then
    BUILD_OPTIONS+=(--build-system "$KEYLIAN_BUILD_SYSTEM")
fi
APP="$PWD/dist/Keylian.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    BINARIES=()
    for ARCH in arm64 x86_64; do
        OPTIONS=("${BUILD_OPTIONS[@]}" --scratch-path "$PWD/.build/distribution-compatible" --triple "$ARCH-apple-macosx13.0")
        swift build "${OPTIONS[@]}"
        BIN_DIR=$(swift build "${OPTIONS[@]}" --show-bin-path)
        BINARIES+=("$BIN_DIR/Keylian")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Keylian"
else
    swift build "${BUILD_OPTIONS[@]}"
    BIN_DIR=$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)
    cp "$BIN_DIR/Keylian" "$APP/Contents/MacOS/Keylian"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/LocalBuild.txt "$APP/Contents/Resources/LocalBuild.txt"
cp LICENSE "$APP/Contents/Resources/LICENSE"
"$APP/Contents/MacOS/Keylian" --export-brand "$PWD/artifacts/brand"
iconutil -c icns "$PWD/artifacts/brand/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Brand/Keylian.svg "$APP/Contents/Resources/Keylian.svg"
python3 scripts/signing.py sign "$APP"
"$APP/Contents/MacOS/Keylian" --self-check
