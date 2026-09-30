#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build --product iconspice
BIN_DIR="$(swift build --show-bin-path)"
swiftc -swift-version 6 -parse-as-library -I "$BIN_DIR/Modules" \
    scripts/export-promo-assets.swift "$BIN_DIR"/IconSpiceCore.build/*.o \
    -o "$BIN_DIR/export-promo-assets"
"$BIN_DIR/export-promo-assets" "${1:-$PROJECT_DIR/promo/public/icons}"
