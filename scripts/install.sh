#!/bin/bash
# Harbr Installation Script
# Builds, signs, and installs Harbr.app to /Applications

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Harbr.app"
APP_PATH="/Applications/$APP_NAME"

echo "Building Harbr..."
cd "$PROJECT_DIR"
swift build -c release

# If a running Harbr is holding the binary open, replacing it can fail
# silently or leave a half-written file. Stop it before installing.
if pgrep -f "/Applications/Harbr.app/Contents/MacOS/Harbr" > /dev/null; then
    echo "Stopping running Harbr instance..."
    pkill -f "/Applications/Harbr.app/Contents/MacOS/Harbr" || true
    sleep 1
fi

# One-time cleanup for users upgrading from the old com.alexanderhayworth.harbr
# bundle ID: the LaunchAgent plist needs to be unloaded and removed so the
# new com.harbr.app one can take over without an orphaned auto-launch.
OLD_AGENT="$HOME/Library/LaunchAgents/com.alexanderhayworth.harbr.plist"
if [ -f "$OLD_AGENT" ]; then
    echo "Removing stale LaunchAgent from previous bundle ID..."
    launchctl unload "$OLD_AGENT" 2>/dev/null || true
    rm -f "$OLD_AGENT"
fi

echo "Creating app bundle..."
# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/Frameworks"

# Copy executable
cp "$BUILD_DIR/Harbr" "$APP_PATH/Contents/MacOS/"

# SwiftPM emits an rpath of just @executable_path, which doesn't point at
# the standard /Contents/Frameworks/ dir. Without this, dyld can't find
# the embedded Sparkle.framework at launch and the app dies before
# reaching applicationDidFinishLaunching. install_name_tool adds the
# bundle-relative rpath in place.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_PATH/Contents/MacOS/Harbr" 2>/dev/null || true

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

# Embed Sparkle.framework so dyld can resolve @rpath/Sparkle.framework at
# launch. SwiftPM extracts the xcframework under .build/artifacts/, and
# we copy the macOS slice into the bundle's Frameworks directory. The
# framework includes XPC services (Downloader.xpc, Installer.xpc) and an
# Updater.app helper — `cp -R` keeps the bundle intact. ditto preserves
# symlinks the framework relies on for its versioned layout.
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework"
    ditto "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
else
    echo "warning: Sparkle.framework not found at $SPARKLE_FRAMEWORK — the app will fail to launch." >&2
    echo "         Run 'swift package resolve' to fetch Sparkle, then retry." >&2
fi

# Copy icon — try project root first (where AppIcon.icns actually lives)
# then Resources/ as a fallback.
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/"
elif [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
fi

# Ad-hoc codesign the bundle. Without this, recent macOS releases refuse to
# grant the app TCC permissions (notably Automation, which Harbr needs to
# script Terminal). Users who want a Developer ID-signed build can set
# CODESIGN_IDENTITY to override "-" (ad-hoc) with their identity name.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Codesigning with identity: $CODESIGN_IDENTITY"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_PATH"

# Strip the quarantine attribute so Gatekeeper doesn't block the first launch
# when this script runs after a `git clone`. (No-op if already absent.)
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo ""
echo "Harbr has been installed to $APP_PATH"
echo ""
echo "To start Harbr, run:"
echo "  open /Applications/Harbr.app"
echo ""
echo "First launch will prompt for Automation permission to control Terminal —"
echo "approve it so Start/Stop/Restart can spawn dev-server windows."
echo ""
echo "To enable Launch at Login, open the menu and check:"
echo "  Preferences > Launch at Login"
