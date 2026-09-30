#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a saved notarytool Keychain profile.}"
./scripts/build-app.sh --universal
ARCHIVE="dist/Icon-Spice-0.1.0-macOS.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/Icon Spice.app" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "dist/Icon Spice.app"
xcrun stapler validate "dist/Icon Spice.app"
/usr/sbin/spctl --assess --type execute "dist/Icon Spice.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/Icon Spice.app" "$ARCHIVE"
/usr/bin/shasum -a 256 "$ARCHIVE"
