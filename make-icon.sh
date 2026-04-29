#!/usr/bin/env bash
# Renders the recmeet app icon at every required size and assembles AppIcon.icns.
# Run this whenever Scripts/make-icon.swift changes.
set -euo pipefail

cd "$(dirname "$0")"

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

BASE="$ICONSET/icon_512x512@2x.png"

echo "→ Rendering 1024x1024 base PNG"
swift Scripts/make-icon.swift "$BASE"

# All sizes required by iconutil for a complete .icns.
SPECS=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
)

echo "→ Resampling to all required sizes"
for spec in "${SPECS[@]}"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    sips -Z "$size" "$BASE" --out "$ICONSET/$name" >/dev/null
done

echo "→ Assembling AppIcon.icns"
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "✓ AppIcon.icns generated ($(du -h AppIcon.icns | cut -f1))"
