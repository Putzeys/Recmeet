#!/usr/bin/env bash
# Builds RecmeetApp and packages it as recmeet.app.
# Usage:
#   ./build-app.sh                  # builds to ./dist
#   ./build-app.sh --install        # builds and installs to /Applications
#   ./build-app.sh <destination>    # builds to <destination>
set -euo pipefail

INSTALL=0
if [[ "${1:-}" == "--install" ]]; then
    INSTALL=1
    DEST="./dist"
else
    DEST="${1:-./dist}"
fi
APP="$DEST/recmeet.app"

# Stable signing identity. Required for TCC permissions to persist across rebuilds.
# Run ./setup-codesign-identity.sh once on this Mac if missing.
SIGN_IDENTITY="recmeet-dev"
if ! security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "✗ Signing identity \"$SIGN_IDENTITY\" not found."
    echo "  Run: ./setup-codesign-identity.sh"
    exit 1
fi

echo "→ swift build -c release --product RecmeetApp"
swift build -c release --product RecmeetApp

mkdir -p "$DEST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/RecmeetApp "$APP/Contents/MacOS/recmeet"
cp Sources/RecmeetApp/Info.plist "$APP/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "⚠  AppIcon.icns missing — run ./make-icon.sh to generate it."
fi

# Ad-hoc sign with entitlements so Hardened Runtime allows mic/audio APIs.
# Without the entitlement, requestAccess() silently fails and the app
# never appears in System Settings → Microphone.
echo "→ codesign --sign \"$SIGN_IDENTITY\" (with entitlements)"
codesign --sign "$SIGN_IDENTITY" --force --options runtime --timestamp=none \
    --entitlements "Sources/RecmeetApp/recmeet.entitlements" \
    "$APP" >/dev/null

echo "✓ Built $APP"

if [[ "$INSTALL" == "1" ]]; then
    echo "→ Installing to /Applications/recmeet.app"
    osascript -e 'tell application "recmeet" to quit' 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/recmeet.app"
    cp -R "$APP" "/Applications/"
    codesign --sign "$SIGN_IDENTITY" --force --options runtime --timestamp=none \
        --entitlements "Sources/RecmeetApp/recmeet.entitlements" \
        "/Applications/recmeet.app" >/dev/null
    echo "✓ Installed at /Applications/recmeet.app"
    echo "Run with:  open /Applications/recmeet.app"
else
    echo "Run with:  open \"$APP\""
fi