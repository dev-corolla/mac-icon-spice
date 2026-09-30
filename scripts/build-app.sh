#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION=release
UNIVERSAL=false
for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION=debug ;;
        --universal) UNIVERSAL=true ;;
        *) echo "Usage: $0 [--debug] [--universal]" >&2; exit 2 ;;
    esac
done
BUILD_FLAGS=(-c "$CONFIGURATION")
if [ "$UNIVERSAL" = true ]; then BUILD_FLAGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/app-stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_DIR="$STAGE_DIR/Icon Spice.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/ThirdParty"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/MacIconSpice" "$APP_DIR/Contents/MacOS/MacIconSpice"
cp "$BIN_DIR/iconspice" "$APP_DIR/Contents/Resources/iconspice"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE"
cp -R ThirdParty/macIconChanger "$APP_DIR/Contents/Resources/ThirdParty/"
swift scripts/create-app-icon.swift "$STAGE_DIR/AppIcon.iconset"
/usr/bin/iconutil -c icns "$STAGE_DIR/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
SIGN_IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$APP_DIR/Contents/Resources/iconspice"
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$APP_DIR"
/usr/bin/codesign --verify --strict "$APP_DIR"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist"
mkdir -p dist
if [ -e "dist/Icon Spice.app" ]; then rm -rf "dist/Icon Spice.app"; fi
mv "$APP_DIR" "dist/Icon Spice.app"
cp "$BIN_DIR/iconspice" dist/iconspice
echo "Built $PROJECT_DIR/dist/Icon Spice.app"
