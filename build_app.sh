#!/bin/bash

echo "Building Pywal Pick.app..."

# Clean previous build
rm -rf PywalPick.app

# Build in release mode
swift build --configuration release

# Create app bundle structure
mkdir -p PywalPick.app/Contents/MacOS
mkdir -p PywalPick.app/Contents/Resources

# Copy executable
cp .build/release/PywalPick PywalPick.app/Contents/MacOS/PywalPick

# Make executable
chmod +x PywalPick.app/Contents/MacOS/PywalPick

# Copy schemer2 binary into the app bundle
if [ -f "$HOME/.local/bin/schemer2" ]; then
    cp ~/.local/bin/schemer2 PywalPick.app/Contents/MacOS/schemer2
    chmod +x PywalPick.app/Contents/MacOS/schemer2
    echo "Bundled schemer2 binary"
else
    echo "Warning: schemer2 not found at ~/.local/bin/schemer2"
fi

# Copy Info.plist
cp Info.plist PywalPick.app/Contents/Info.plist

# Copy assets (including AppIcon from xcassets)
cp -r assets/Assets.xcassets PywalPick.app/Contents/Resources/Assets.xcassets

echo "Pywal Pick.app created successfully!"
echo "You can now double-click PywalPick.app to run it."