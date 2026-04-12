#!/bin/bash

# Test script for wal execution
echo "Testing wal execution..."

# Check if wal exists
WAL_PATH="/Volumes/NightSky/babaisalive/.local/bin/wal"
if [ ! -f "$WAL_PATH" ]; then
    echo "ERROR: Wal not found at $WAL_PATH"
    exit 1
fi

echo "Wal found at: $WAL_PATH"

# Create a test dummy file
DUMMY_FILE="$HOME/Pictures/dummy-file.jpg"
echo "Dummy file path: $DUMMY_FILE"

# Check if dummy file exists
if [ -f "$DUMMY_FILE" ]; then
    echo "Dummy file exists"
else
    echo "WARNING: Dummy file does not exist yet"
fi

# Test wal command
echo "Testing wal command..."
"$WAL_PATH" -i "$DUMMY_FILE" -n 2>&1

if [ $? -eq 0 ]; then
    echo "SUCCESS: Wal command executed successfully"
else
    echo "ERROR: Wal command failed"
fi

echo "Wal test completed."