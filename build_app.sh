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

# Generate icon from polaroid-camera.png if ImageMagick is available
if command -v magick &> /dev/null || command -v convert &> /dev/null; then
    CONVERT_CMD="magick"
    command -v convert &> /dev/null && CONVERT_CMD="convert"
    
    mkdir -p PywalPick.app/Contents/Resources/AppIcon.appiconset
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 16x16 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_16x16.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 32x32 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_16x16@2x.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 32x32 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_32x32.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 128x128 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_128x128.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 256x256 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_128x128@2x.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 256x256 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_256x256.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 512x512 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_256x256@2x.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 512x512 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_512x512.png
    $CONVERT_CMD -background none assets/polaroid-camera.png -resize 1024x1024 PywalPick.app/Contents/Resources/AppIcon.appiconset/icon_512x512@2x.png
    
    cat > PywalPick.app/Contents/Resources/AppIcon.appiconset/Contents.json << 'EOF'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
    echo "Icon generated from polaroid-camera.png"
fi

echo "Pywal Pick.app created successfully!"
echo "You can now double-click PywalPick.app to run it."