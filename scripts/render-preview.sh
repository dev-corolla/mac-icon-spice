#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
swiftc -swift-version 6 -parse-as-library -I "$BIN_DIR/Modules" \
    Sources/IconSpice/AppModel.swift Sources/IconSpice/LibraryView.swift Sources/IconSpice/PepperArtwork.swift \
    Sources/IconSpice/IconCard.swift Sources/IconSpice/SettingsView.swift \
    scripts/render-preview.swift "$BIN_DIR"/IconSpiceCore.build/*.o \
    -o "$BIN_DIR/render-preview"
"$BIN_DIR/render-preview" "${1:-$PROJECT_DIR/docs/images/library.png}"
