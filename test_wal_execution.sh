#!/bin/bash

echo "=== Testing Wal Execution from App Context ==="
echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"
echo "Shell: $SHELL"
echo "PATH: $PATH"
echo ""

# Test the exact command the app would run
WAL_CMD="/Volumes/NightSky/babaisalive/.local/bin/wal -i /Volumes/NightSky/babaisalive/Pictures/dummy-file.jpg -n"

echo "Testing wal command: $WAL_CMD"
echo "Wal binary exists: $([ -f '/Volumes/NightSky/babaisalive/.local/bin/wal' ] && echo 'YES' || echo 'NO')"
echo "Wal binary executable: $([ -x '/Volumes/NightSky/babaisalive/.local/bin/wal' ] && echo 'YES' || echo 'NO')"
echo "Dummy file exists: $([ -f '/Volumes/NightSky/babaisalive/Pictures/dummy-file.jpg' ] && echo 'YES' || echo 'NO')"
echo ""

echo "Running wal command..."
eval "$WAL_CMD"
EXIT_CODE=$?

echo ""
echo "Exit code: $EXIT_CODE"
echo "Wal cache exists: $([ -d '~/.cache/wal' ] && echo 'YES' || echo 'NO')"
echo "Colors file exists: $([ -f '~/.cache/wal/colors' ] && echo 'YES' || echo 'NO')"

if [ -f ~/.cache/wal/colors ]; then
    echo "Colors file contents:"
    head -5 ~/.cache/wal/colors
fi

echo ""
echo "=== Test Complete ==="