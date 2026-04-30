#!/usr/bin/env bash
# Builds a drag-to-Applications style .dmg from dist/recmeet.app.
# Run after build-app.sh has produced the app.
set -euo pipefail

cd "$(dirname "$0")"

APP="dist/recmeet.app"
DMG="dist/recmeet.dmg"

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found. Run ./build-app.sh first."
    exit 1
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

echo "→ Staging $APP + Applications symlink"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
echo "→ hdiutil create $DMG"
hdiutil create \
    -volname "recmeet" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

# Ad-hoc sign the DMG with the same identity used for the app, so
# Gatekeeper doesn't add an extra layer of warnings.
if security find-identity -p codesigning | grep -q "recmeet-dev"; then
    codesign --sign "recmeet-dev" --force "$DMG" >/dev/null
fi

echo "✓ Wrote $DMG ($(du -h "$DMG" | cut -f1))"
