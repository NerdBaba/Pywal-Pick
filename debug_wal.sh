#!/bin/bash

echo "=== Wallpaper Switcher Wal Path Test ==="
echo "Current directory: $(pwd)"
echo "Home directory: $HOME"
echo "PATH: $PATH"
echo ""

# Test the wal path from app perspective
WAL_PATH="/Volumes/NightSky/babaisalive/.local/bin/wal"
echo "Testing wal path: $WAL_PATH"

if [ -f "$WAL_PATH" ]; then
    echo "✓ Wal file exists"
    if [ -x "$WAL_PATH" ]; then
        echo "✓ Wal is executable"
        ls -la "$WAL_PATH"
    else
        echo "✗ Wal is not executable"
        ls -la "$WAL_PATH"
    fi
else
    echo "✗ Wal file does not exist"
fi

echo ""
echo "Testing wal command directly:"
"$WAL_PATH" --version 2>&1 || echo "Wal command failed"

echo ""
echo "Dummy file location:"
DUMMY_FILE="$HOME/Pictures/dummy-file.jpg"
echo "Dummy file: $DUMMY_FILE"
if [ -f "$DUMMY_FILE" ]; then
    echo "✓ Dummy file exists"
    ls -la "$DUMMY_FILE"
else
    echo "✗ Dummy file does not exist"
fi

echo ""
echo "=== Test Complete ==="