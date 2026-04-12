#!/bin/bash

echo "Building Wallpaper Switcher.app..."

# Clean previous build
rm -rf WallpaperSwitcher.app

# Build in release mode
swift build --configuration release

# Create app bundle structure
mkdir -p WallpaperSwitcher.app/Contents/MacOS
mkdir -p WallpaperSwitcher.app/Contents/Resources

# Copy executable
cp .build/release/ImagePicker WallpaperSwitcher.app/Contents/MacOS/WallpaperSwitcher

# Make executable
chmod +x WallpaperSwitcher.app/Contents/MacOS/WallpaperSwitcher

# Copy schemer2 binary into the app bundle
if [ -f "$HOME/.local/bin/schemer2" ]; then
    cp ~/.local/bin/schemer2 WallpaperSwitcher.app/Contents/MacOS/schemer2
    chmod +x WallpaperSwitcher.app/Contents/MacOS/schemer2
    echo "Bundled schemer2 binary"
else
    echo "Warning: schemer2 not found at ~/.local/bin/schemer2"
fi

# Copy Info.plist
cp Info.plist WallpaperSwitcher.app/Contents/Info.plist

# Generate icon if ImageMagick is available
if command -v convert &> /dev/null; then
    mkdir -p WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset
    convert -background none AppIcon.svg -resize 16x16 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_16x16.png
    convert -background none AppIcon.svg -resize 32x32 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_16x16@2x.png
    convert -background none AppIcon.svg -resize 32x32 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_32x32.png
    convert -background none AppIcon.svg -resize 128x128 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_128x128.png
    convert -background none AppIcon.svg -resize 256x256 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_128x128@2x.png
    convert -background none AppIcon.svg -resize 256x256 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_256x256.png
    convert -background none AppIcon.svg -resize 512x512 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_256x256@2x.png
    convert -background none AppIcon.svg -resize 512x512 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_512x512.png
    convert -background none AppIcon.svg -resize 1024x1024 WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/icon_512x512@2x.png
    
    cat > WallpaperSwitcher.app/Contents/Resources/AppIcon.appiconset/Contents.json << 'EOF'
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
    echo "Icon generated from AppIcon.svg"
fi

echo "Wallpaper Switcher.app created successfully!"
echo "You can now double-click WallpaperSwitcher.app to run it."