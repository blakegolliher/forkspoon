#!/bin/bash

# Simple test to verify if caching is working at all
# Tests a single directory without wildcards

CACHED_MOUNT="/tmp/nfs-cached"
TEST_DIR="r0/d5"

# Find log file
if [ -f "/opt/forkspoon/forkspoon.log" ]; then
    LOG_FILE="/opt/forkspoon/forkspoon.log"
elif [ -f "$HOME/forkspoon.log" ]; then
    LOG_FILE="$HOME/forkspoon.log"
else
    echo "Log file not found!"
    exit 1
fi

echo "============================================"
echo "SIMPLE CACHE TEST - No Wildcards"
echo "============================================"
echo ""

# First, verify mount is active
if ! mountpoint -q "$CACHED_MOUNT"; then
    echo "ERROR: $CACHED_MOUNT is not mounted!"
    exit 1
fi

echo "Testing directory: $CACHED_MOUNT/$TEST_DIR"
echo "Log file: $LOG_FILE"
echo ""

# Mark log position
initial_lines=$(wc -l < "$LOG_FILE")

echo "Test 1: First 'ls' of directory (expect cache misses)"
echo "Running: ls $CACHED_MOUNT/$TEST_DIR | head -5"
time ls "$CACHED_MOUNT/$TEST_DIR" | head -5

# Count new log entries
new_entries1=$(($(wc -l < "$LOG_FILE") - initial_lines))
echo "New log entries: $new_entries1"
echo ""

sleep 2
before_second=$(wc -l < "$LOG_FILE")

echo "Test 2: Second 'ls' of same directory (expect NO new operations if cached)"
echo "Running: ls $CACHED_MOUNT/$TEST_DIR | head -5"
time ls "$CACHED_MOUNT/$TEST_DIR" | head -5

# Count new log entries
new_entries2=$(($(wc -l < "$LOG_FILE") - before_second))
echo "New log entries: $new_entries2"
echo ""

if [ $new_entries2 -eq 0 ]; then
    echo "✓ SUCCESS: Cache is working! No new operations on second ls"
elif [ $new_entries2 -lt $new_entries1 ]; then
    echo "⚠ PARTIAL: Some caching, but not complete ($new_entries2 vs $new_entries1)"
else
    echo "✗ FAILURE: Cache not working ($new_entries2 operations on second run)"
fi

echo ""
echo "============================================"
echo "Now testing with stat on a single file"
echo "============================================"
echo ""

# Pick a single file
TEST_FILE="$CACHED_MOUNT/$TEST_DIR/r0-f0"

before_stat1=$(wc -l < "$LOG_FILE")
echo "Test 3: First 'stat' of file"
stat "$TEST_FILE" > /dev/null 2>&1
stat1_ops=$(($(wc -l < "$LOG_FILE") - before_stat1))
echo "Operations: $stat1_ops"

sleep 1

before_stat2=$(wc -l < "$LOG_FILE")
echo "Test 4: Second 'stat' of same file (should be cached)"
stat "$TEST_FILE" > /dev/null 2>&1
stat2_ops=$(($(wc -l < "$LOG_FILE") - before_stat2))
echo "Operations: $stat2_ops"

if [ $stat2_ops -eq 0 ]; then
    echo "✓ File stat is cached!"
else
    echo "✗ File stat not cached"
fi

echo ""
echo "============================================"
echo "Mount information:"
mount | grep "$CACHED_MOUNT"
echo ""
echo "Process info:"
ps aux | grep forkspoon | grep -v grep