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

# Generate app icon from SF Symbol (sailboat)
# This creates a simple icon using sips and iconutil
ICONSET_DIR="$PROJECT_DIR/build/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Create a simple icon using Python and SF Symbols
# If you have a custom icon, replace this section
python3 << 'PYTHON_SCRIPT'
import subprocess
import os

iconset_dir = os.environ.get('ICONSET_DIR', 'build/AppIcon.iconset')
os.makedirs(iconset_dir, exist_ok=True)

# Icon sizes needed for macOS
sizes = [16, 32, 64, 128, 256, 512]

for size in sizes:
    # Create standard resolution
    subprocess.run([
        'sips', '-z', str(size), str(size),
        '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns',
        '--out', f'{iconset_dir}/icon_{size}x{size}.png'
    ], capture_output=True)

    # Create 2x resolution
    size2x = size * 2
    if size2x <= 1024:
        subprocess.run([
            'sips', '-z', str(size2x), str(size2x),
            '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns',
            '--out', f'{iconset_dir}/icon_{size}x{size}@2x.png'
        ], capture_output=True)
PYTHON_SCRIPT

# Convert iconset to icns
if [ -d "$ICONSET_DIR" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET_DIR"
fi

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
