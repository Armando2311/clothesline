#!/bin/bash
# Builds Clothesline.app from the Swift package.
#
#   Scripts/build-app.sh               # release build for this Mac's architecture
#   Scripts/build-app.sh --universal   # Apple silicon + Intel
#
# Signs ad hoc by default. Set CODESIGN_IDENTITY="Developer ID Application: …"
# to sign for distribution (then notarize with notarytool).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

APP=build/Clothesline.app
rm -rf "$APP" build/AppIcon.iconset build/Clothesline.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clothesline" "$APP/Contents/MacOS/Clothesline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon, drawn programmatically (no third-party artwork).
swift Scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "${CODESIGN_IDENTITY:--}" --options runtime \
  --entitlements Resources/Clothesline.entitlements "$APP"

(cd build && ditto -c -k --keepParent Clothesline.app Clothesline.zip)
echo "Built $APP"
