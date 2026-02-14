#!/bin/bash
# Harbr Installation Script
# Builds and installs Harbr.app to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Harbr.app"
APP_PATH="/Applications/$APP_NAME"

echo "Building Harbr..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/Harbr" "$APP_PATH/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

# Copy icon if exists
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

echo "Harbr has been installed to $APP_PATH"
echo ""
echo "To start Harbr, run:"
echo "  open /Applications/Harbr.app"
echo ""
echo "To enable Launch at Login, open Harbr and check:"
echo "  Preferences > Launch at Login"
