#!/bin/bash
# Build, sign with Developer ID, notarize, and staple Harbr.app — producing
# a distributable Harbr.app.zip in dist/.
#
# Required environment variables (none of which can live in the repo):
#
#   CODESIGN_IDENTITY      e.g. "Developer ID Application: Jane Doe (ABCD1234EF)"
#                          Find with: security find-identity -v -p codesigning
#
#   APPLE_ID               Apple ID email enrolled in the Apple Developer
#                          Program.
#
#   APP_SPECIFIC_PASSWORD  Generated at https://appleid.apple.com → Security
#                          → App-Specific Passwords. NOT your Apple ID
#                          password. Treat as a secret.
#
#   TEAM_ID                10-character Team ID from
#                          https://developer.apple.com/account → Membership.
#
# Optional:
#
#   KEEP_UNNOTARIZED_ZIP   If set, the pre-notarization zip submitted to
#                          notarytool is preserved in dist/ for debugging
#                          a rejection. Default: removed once the staple
#                          finishes.
#
# This script does NOT depend on scripts/install.sh — it builds its own
# bundle under dist/ so the local /Applications copy stays as-is during
# the notarization round-trip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Harbr.app"
APP_PATH="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/Harbr.app.zip"

require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "error: $name is not set. See header of $(basename "$0") for required env vars." >&2
        exit 1
    fi
}

require_env CODESIGN_IDENTITY
require_env APPLE_ID
require_env APP_SPECIFIC_PASSWORD
require_env TEAM_ID

# Refuse the ad-hoc identity for notarization. Apple's notary service
# requires a Developer ID Application certificate; "-" (ad-hoc) is what
# install.sh uses for local builds and will be silently accepted by
# codesign but rejected at notarytool submission with an opaque error.
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "error: CODESIGN_IDENTITY=- (ad-hoc) cannot be notarized." >&2
    echo "       Set it to a 'Developer ID Application: …' identity." >&2
    exit 1
fi

echo "→ Building release binary…"
cd "$PROJECT_DIR"
swift build -c release

echo "→ Creating dist bundle at $APP_PATH"
rm -rf "$DIST_DIR"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILD_DIR/Harbr" "$APP_PATH/Contents/MacOS/"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/"
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/"
elif [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

echo "→ Signing with $CODESIGN_IDENTITY (hardened runtime + timestamp)…"
# --options runtime is required for notarization.
# --timestamp embeds an Apple timestamp so the signature stays valid after
# the cert expires.
# --deep handles the executable + any embedded frameworks (Sparkle's XPC
# services in particular).
codesign --force --deep --options runtime --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_PATH"

# Verify the signature before paying the round-trip cost of submitting.
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "→ Zipping for notarytool submission…"
# ditto preserves resource forks / extended attributes — plain `zip` will
# strip the codesign signature on macOS in some configurations.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "→ Submitting to Apple notary service (this may take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

echo "→ Stapling the notarization ticket to the app bundle…"
xcrun stapler staple "$APP_PATH"
# Validation is offline once stapled; do it to fail loud if Apple's ticket
# didn't actually attach.
xcrun stapler validate "$APP_PATH"

echo "→ Re-zipping the stapled bundle for distribution…"
# The submission zip was pre-staple, so it's not the artifact users should
# download. Replace it with the stapled version unless explicitly kept.
if [ -z "${KEEP_UNNOTARIZED_ZIP:-}" ]; then
    rm -f "$ZIP_PATH"
fi
FINAL_ZIP="$DIST_DIR/Harbr.app.zip"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

echo ""
echo "✓ Notarized + stapled bundle at: $APP_PATH"
echo "✓ Distributable archive at:      $FINAL_ZIP"
echo ""
echo "Next: upload $FINAL_ZIP to the GitHub release for this version, then"
echo "      bump appcast.xml with the new <enclosure> URL + EdDSA signature"
echo "      (see docs/appcast.xml for the template)."
