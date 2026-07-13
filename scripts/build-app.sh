#!/bin/bash

# Build script for creating Harbr.app bundle
# Usage: ./scripts/build-app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Harbr"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"

echo "Building $APP_NAME..."

# Build release binary
cd "$PROJECT_DIR"
swift build -c release

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy app icon
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found, app will use default icon"
fi

# Bundle Sparkle.framework and wire the rpath so the app can load it at
# runtime. Without both steps the app crashes on first frame with:
#   Library not loaded: @rpath/Sparkle.framework/…
# swift build's default rpaths only cover /usr/lib/swift and @loader_path
# (which is Contents/MacOS/, not Contents/Frameworks/) — neither contains
# Sparkle. -R preserves the framework's symlinks; --deep on the codesign
# step below re-signs the nested framework.
SPARKLE_SRC="$PROJECT_DIR/.build/release/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
    mkdir -p "$FRAMEWORKS_DIR"
    cp -R "$SPARKLE_SRC" "$FRAMEWORKS_DIR/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
    echo "Warning: Sparkle.framework not found at $SPARKLE_SRC — auto-updates will crash on launch"
fi

# Ad-hoc codesign so recent macOS will let the app request Automation /
# Notifications permissions. Set CODESIGN_IDENTITY to your Developer ID
# string if you have one (e.g. "Developer ID Application: Your Name (TEAMID)").
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Codesigning with identity: $CODESIGN_IDENTITY"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"

echo ""
echo "✅ Build complete!"
echo ""
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -r '$APP_BUNDLE' /Applications/"
echo ""
echo "To add to Login Items:"
echo "  1. Open System Settings → General → Login Items"
echo "  2. Click '+' and select Harbr from Applications"
