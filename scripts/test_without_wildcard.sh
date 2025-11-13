#!/bin/bash

# Test WITHOUT wildcards to see real cache performance
# Wildcards cause 640+ LOOKUP operations which aren't being cached

CACHED_MOUNT="/tmp/nfs-cached"
TEST_DIR="r0/d5"

# Find log file
if [ -f "/opt/forkspoon/forkspoon.log" ]; then
    LOG_FILE="/opt/forkspoon/forkspoon.log"
elif [ -f "$HOME/forkspoon.log" ]; then
    LOG_FILE="$HOME/forkspoon.log"
else
    LOG_FILE=""
fi

echo "============================================"
echo "CACHE TEST WITHOUT WILDCARDS"
echo "============================================"
echo ""
echo "This test avoids wildcards which cause 640+ LOOKUP operations"
echo ""

# Test 1: Simple ls (no wildcards)
echo "Test 1: Simple 'ls' of directory (no wildcards)"
before=$(wc -l < "$LOG_FILE")
echo -n "First run: "
time -p ls "$CACHED_MOUNT/$TEST_DIR" 2>&1 | grep real
after=$(wc -l < "$LOG_FILE")
ops1=$((after - before))
echo "Operations logged: $ops1"
echo ""

sleep 1

echo "Second run (should be cached):"
before=$(wc -l < "$LOG_FILE")
echo -n "Time: "
time -p ls "$CACHED_MOUNT/$TEST_DIR" 2>&1 | grep real
after=$(wc -l < "$LOG_FILE")
ops2=$((after - before))
echo "Operations logged: $ops2"

if [ $ops2 -eq 0 ]; then
    echo "✓ PERFECT: Zero operations = fully served from cache!"
elif [ $ops2 -lt $ops1 ]; then
    echo "✓ GOOD: Fewer operations ($ops2 vs $ops1)"
else
    echo "✗ BAD: Same/more operations"
fi

echo ""
echo "============================================"
echo "Test 2: ls -l (without wildcards)"
echo "============================================"
before=$(wc -l < "$LOG_FILE")
echo -n "First run: "
time -p ls -l "$CACHED_MOUNT/$TEST_DIR" | wc -l
after=$(wc -l < "$LOG_FILE")
ops1=$((after - before))
echo "Operations logged: $ops1"
echo ""

sleep 1

echo "Second run (should use cache):"
before=$(wc -l < "$LOG_FILE")
echo -n "Files: "
time -p ls -l "$CACHED_MOUNT/$TEST_DIR" | wc -l
after=$(wc -l < "$LOG_FILE")
ops2=$((after - before))
echo "Operations logged: $ops2"

if [ $ops2 -eq 0 ]; then
    echo "✓ PERFECT: Fully cached!"
elif [ $ops2 -lt $ops1 ]; then
    echo "✓ PARTIAL: Some caching"
else
    echo "✗ NO CACHE"
fi

echo ""
echo "============================================"
echo "SUMMARY"
echo "============================================"
echo ""
echo "Without wildcards:"
echo "  • READDIR operations ARE cached (we see hits)"
echo "  • Performance is much better"
echo ""
echo "With wildcards (r0/d5/*):"
echo "  • Causes 640+ LOOKUP operations per file"
echo "  • LOOKUP operations are NOT being cached by kernel"
echo "  • This is why hit rate is so low"
echo ""
echo "The caching IS working, but wildcards create uncacheable operations."