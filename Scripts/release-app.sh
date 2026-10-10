#!/bin/bash
# Build, sign, notarize and staple a distribution archive. Does not publish.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${CODESIGN_IDENTITY:-}" != "Developer ID Application:"* ]]; then
  echo 'Set CODESIGN_IDENTITY to a Developer ID Application identity.' >&2
  exit 2
fi
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo 'Set NOTARY_PROFILE to a stored notarytool keychain profile.' >&2
  exit 2
fi
Scripts/build-app.sh --universal
codesign --verify --deep --strict build/Clothesline.app
xcrun notarytool submit build/Clothesline.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple build/Clothesline.app
xcrun stapler validate build/Clothesline.app
spctl --assess --type execute build/Clothesline.app
# Rebuild archive so downloads contain the stapled ticket.
rm -f build/Clothesline.zip
ditto -c -k --keepParent build/Clothesline.app build/Clothesline.zip
shasum -a 256 build/Clothesline.zip > build/Clothesline.zip.sha256
printf 'Distribution archive ready: build/Clothesline.zip\n'
