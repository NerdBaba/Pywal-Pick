#!/bin/bash

echo "=== Manual Shell Command Test ==="
echo "Testing Process execution like the app does..."

# Test a simple command
echo "Testing: echo 'Hello from shell'"
/bin/bash -c "echo 'Hello from shell'"

echo ""
echo "Testing wal version check:"
/bin/bash -c "/Volumes/NightSky/babaisalive/.local/bin/wal --help 2>&1 | head -5"

echo ""
echo "Testing wal with dummy file:"
DUMMY_FILE="/Volumes/NightSky/babaisalive/Pictures/dummy-file.jpg"
if [ -f "$DUMMY_FILE" ]; then
    echo "Dummy file exists, testing wal command..."
    /bin/bash -c "/Volumes/NightSky/babaisalive/.local/bin/wal -i '$DUMMY_FILE' -n --version 2>&1 | head -3"
else
    echo "Dummy file not found: $DUMMY_FILE"
fi

echo ""
echo "=== Test Complete ==="