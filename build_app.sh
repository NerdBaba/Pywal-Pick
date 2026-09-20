#!/bin/bash
set -euo pipefail

echo "Building Pywal Pick.app..."

APP_BUNDLE="PywalPick.app"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

# Clean previous build
rm -rf "$APP_BUNDLE"

# Build in release mode
swift build --configuration release

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp .build/release/PywalPick "$APP_BUNDLE/Contents/MacOS/PywalPick"

# Make executable
chmod +x "$APP_BUNDLE/Contents/MacOS/PywalPick"

# Copy schemer2 binary into the app bundle
if [ -f "$HOME/.local/bin/schemer2" ]; then
    cp ~/.local/bin/schemer2 "$APP_BUNDLE/Contents/MacOS/schemer2"
    chmod +x "$APP_BUNDLE/Contents/MacOS/schemer2"
    echo "Bundled schemer2 binary"
else
    echo "Warning: schemer2 not found at ~/.local/bin/schemer2"
fi

# Copy wallpick CLI binary into the app bundle
if [ -f ".build/release/wallpick" ]; then
    cp .build/release/wallpick "$APP_BUNDLE/Contents/MacOS/wallpick"
    chmod +x "$APP_BUNDLE/Contents/MacOS/wallpick"
    echo "Bundled wallpick CLI binary"
else
    echo "Warning: wallpick binary not found at .build/release/wallpick"
fi

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Compile the asset catalog so macOS receives Assets.car and AppIcon.icns.
# Copying the .xcassets directory directly does not make an icon available to
# Finder or the Dock because macOS only reads compiled asset catalogs.
if ! ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
    echo "Error: Xcode's actool is required to package the app icon." >&2
    exit 1
fi

ASSET_INFO_PLIST="$(mktemp -t pywalpick-assets)"
trap 'rm -f "$ASSET_INFO_PLIST"' EXIT

"$ACTOOL" assets/Assets.xcassets \
    --compile "$RESOURCES_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_INFO_PLIST"

if [ ! -f "$RESOURCES_DIR/Assets.car" ] || [ ! -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    echo "Error: actool did not produce the compiled app icon resources." >&2
    exit 1
fi

echo "Bundled compiled asset catalog and AppIcon.icns"

echo "Pywal Pick.app created successfully!"
echo "You can now double-click PywalPick.app to run it."
