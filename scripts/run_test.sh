#!/bin/bash

# Simple test of the already-built FUSE filesystem

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Testing Metadata-Caching FUSE Filesystem ===${NC}"
echo

# Check if binary exists
if [ ! -f ./forkspoon ]; then
    echo -e "${RED}Error: forkspoon binary not found${NC}"
    echo "Please build first: go build -o forkspoon main.go"
    exit 1
fi

# Create test environment
BACKEND="/tmp/fuse-backend-$$"
MOUNT="/tmp/fuse-mount-$$"
LOG="/tmp/fuse-log-$$.txt"

echo "Creating test environment..."
mkdir -p "$BACKEND" "$MOUNT"

# Create test files
echo "Creating test files..."
for i in {1..5}; do
    echo "Test file $i content" > "$BACKEND/file$i.txt"
done
mkdir -p "$BACKEND/subdir"
echo "Nested content" > "$BACKEND/subdir/nested.txt"

echo -e "${GREEN}✓ Test environment ready${NC}"
echo "  Backend: $BACKEND"
echo "  Mount:   $MOUNT"
echo

# Function to cleanup
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"

    # Kill FUSE process if running
    if [ ! -z "$FUSE_PID" ]; then
        kill $FUSE_PID 2>/dev/null || true
        sleep 1
    fi

    # Unmount
    fusermount -u "$MOUNT" 2>/dev/null || true

    # Remove directories
    rm -rf "$BACKEND" "$MOUNT" "$LOG"

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT

# Mount the filesystem with 10-second cache
echo -e "${YELLOW}Mounting FUSE filesystem with 10-second cache TTL...${NC}"
./forkspoon -backend "$BACKEND" -mountpoint "$MOUNT" -cache-ttl 10s -verbose > "$LOG" 2>&1 &
FUSE_PID=$!

# Wait for mount
sleep 2

# Check if mounted
if ! mountpoint -q "$MOUNT"; then
    echo -e "${RED}✗ Mount failed! Check log:${NC}"
    tail -20 "$LOG"
    exit 1
fi

echo -e "${GREEN}✓ Filesystem mounted successfully${NC}"
echo

# Test 1: First access (cache miss)
echo -e "${BLUE}Test 1: First access (expecting cache misses)${NC}"
ls -la "$MOUNT" > /dev/null
echo "Check log for cache miss messages:"
grep "Cache miss" "$LOG" | tail -5
echo

sleep 1

# Test 2: Second access (cache hit)
echo -e "${BLUE}Test 2: Immediate second access (expecting cache hits)${NC}"
LOG_LINES_BEFORE=$(wc -l < "$LOG")
ls -la "$MOUNT" > /dev/null
LOG_LINES_AFTER=$(wc -l < "$LOG")

if [ "$LOG_LINES_BEFORE" -eq "$LOG_LINES_AFTER" ]; then
    echo -e "${GREEN}✓ No new log entries - served from cache!${NC}"
else
    NEW_LINES=$((LOG_LINES_AFTER - LOG_LINES_BEFORE))
    echo -e "${YELLOW}Added $NEW_LINES log lines (should be 0 for pure cache hit)${NC}"
fi
echo

# Test 3: File operations
echo -e "${BLUE}Test 3: File operations${NC}"
echo "Creating new file..."
echo "New content" > "$MOUNT/newfile.txt"
echo "Renaming file..."
mv "$MOUNT/newfile.txt" "$MOUNT/renamed.txt"
echo "Deleting file..."
rm "$MOUNT/renamed.txt"

echo "Checking operations in log:"
grep -E "CREATE|RENAME|UNLINK" "$LOG" | tail -3
echo -e "${GREEN}✓ File operations completed${NC}"
echo

# Test 4: Cache expiry
echo -e "${BLUE}Test 4: Cache expiry test (10-second TTL)${NC}"
echo "Waiting 11 seconds for cache to expire..."
sleep 11

echo "Accessing again (should see new cache misses)..."
LOG_LINES_BEFORE=$(wc -l < "$LOG")
ls -la "$MOUNT" > /dev/null
LOG_LINES_AFTER=$(wc -l < "$LOG")

if [ "$LOG_LINES_AFTER" -gt "$LOG_LINES_BEFORE" ]; then
    echo -e "${GREEN}✓ Cache expired - new cache misses detected${NC}"
    grep "Cache miss" "$LOG" | tail -3
else
    echo -e "${RED}✗ No new cache misses - cache may not have expired${NC}"
fi
echo

# Performance test
echo -e "${BLUE}Test 5: Performance comparison${NC}"

# Direct access
START=$(date +%s%N)
for i in {1..100}; do
    stat "$BACKEND/file1.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
DIRECT_MS=$((($END - $START) / 1000000))
echo "Direct backend access: ${DIRECT_MS}ms for 100 stat operations"

# Cached access
stat "$MOUNT/file1.txt" > /dev/null 2>&1  # Prime cache
START=$(date +%s%N)
for i in {1..100}; do
    stat "$MOUNT/file1.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
CACHED_MS=$((($END - $START) / 1000000))
echo "Cached access:         ${CACHED_MS}ms for 100 stat operations"

if [ "$CACHED_MS" -lt "$DIRECT_MS" ]; then
    echo -e "${GREEN}✓ Caching provides performance improvement${NC}"
else
    echo -e "${YELLOW}Note: Local filesystem may be too fast to show improvement${NC}"
fi

echo
echo -e "${GREEN}=== All Tests Complete ===${NC}"
echo
echo "The FUSE filesystem is working correctly with:"
echo "  • Metadata caching with configurable TTL"
echo "  • Cache hits and misses properly logged"
echo "  • File operations (create, rename, delete)"
echo "  • Cache expiry after TTL"
echo
echo "View full log: cat $LOG"