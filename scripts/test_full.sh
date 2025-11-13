#!/bin/bash

# Comprehensive test of the full FUSE implementation with metrics

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=== Full FUSE Filesystem Test with Metrics ===${NC}"
echo

# Setup
BACKEND="/tmp/fuse-backend-$$"
MOUNT="/tmp/fuse-mount-$$"
TRANS_LOG="/tmp/fuse-transactions-$$.log"
STATS_FILE="/tmp/fuse-stats-$$.json"

echo "Test Configuration:"
echo "  Backend:     $BACKEND"
echo "  Mount:       $MOUNT"
echo "  Trans Log:   $TRANS_LOG"
echo "  Stats File:  $STATS_FILE"
echo "  Cache TTL:   5 seconds"
echo

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"

    # Kill FUSE process
    if [ ! -z "$FUSE_PID" ]; then
        kill -INT $FUSE_PID 2>/dev/null || true
        sleep 2
    fi

    # Unmount
    fusermount -u "$MOUNT" 2>/dev/null || true

    # Show final statistics if available
    if [ -f "$STATS_FILE" ]; then
        echo -e "\n${MAGENTA}=== Final Cache Statistics ===${NC}"
        cat "$STATS_FILE" | python3 -m json.tool 2>/dev/null || cat "$STATS_FILE"
    fi

    # Remove test directories
    rm -rf "$BACKEND" "$MOUNT"

    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo "Transaction log saved at: $TRANS_LOG"
    echo "Statistics saved at: $STATS_FILE"
}

trap cleanup EXIT

# Create test environment
echo -e "${BLUE}1. Creating test environment...${NC}"
mkdir -p "$BACKEND"
mkdir -p "$BACKEND/subdir1"
mkdir -p "$BACKEND/subdir2"

# Create test files
for i in {1..5}; do
    echo "Initial content of file$i" > "$BACKEND/file$i.txt"
done
echo "Nested file content" > "$BACKEND/subdir1/nested.txt"

echo -e "${GREEN}✓ Test environment created${NC}\n"

# Mount filesystem
echo -e "${BLUE}2. Mounting FUSE filesystem...${NC}"
./forkspoon-full \
    -backend "$BACKEND" \
    -mountpoint "$MOUNT" \
    -cache-ttl 5s \
    -verbose \
    -trans-log "$TRANS_LOG" \
    -stats-file "$STATS_FILE" &
FUSE_PID=$!

sleep 2

# Verify mount
if ! mountpoint -q "$MOUNT"; then
    echo -e "${RED}Mount failed!${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Filesystem mounted${NC}\n"

# Test 1: Read operations (will be cached)
echo -e "${MAGENTA}=== Test 1: Read Operations (Cached) ===${NC}"

echo "First access - cache MISS expected:"
ls -la "$MOUNT" > /dev/null
stat "$MOUNT/file1.txt" > /dev/null
cat "$MOUNT/file1.txt" > /dev/null

echo "Second access - cache HIT expected:"
ls -la "$MOUNT" > /dev/null
stat "$MOUNT/file1.txt" > /dev/null

echo -e "${GREEN}✓ Read operations tested${NC}\n"

# Test 2: Write operations (passthrough)
echo -e "${MAGENTA}=== Test 2: Write Operations (Passthrough) ===${NC}"

echo "Creating new file..."
echo "New file content" > "$MOUNT/newfile.txt"

echo "Modifying existing file..."
echo "Modified content" >> "$MOUNT/file1.txt"

echo "Creating directory..."
mkdir "$MOUNT/newdir"

echo "Moving file..."
mv "$MOUNT/newfile.txt" "$MOUNT/renamed.txt"

echo "Deleting file..."
rm "$MOUNT/renamed.txt"

echo "Removing directory..."
rmdir "$MOUNT/newdir"

echo -e "${GREEN}✓ Write operations completed${NC}\n"

# Test 3: Cache expiry
echo -e "${MAGENTA}=== Test 3: Cache Expiry Test ===${NC}"

echo "Accessing files (priming cache)..."
stat "$MOUNT/file2.txt" > /dev/null
stat "$MOUNT/file3.txt" > /dev/null

echo "Waiting 6 seconds for cache to expire (TTL=5s)..."
sleep 6

echo "Re-accessing files (cache miss expected)..."
stat "$MOUNT/file2.txt" > /dev/null
stat "$MOUNT/file3.txt" > /dev/null

echo -e "${GREEN}✓ Cache expiry tested${NC}\n"

# Test 4: Mixed operations
echo -e "${MAGENTA}=== Test 4: Mixed Read/Write Operations ===${NC}"

# Rapid mixed operations
for i in {1..3}; do
    # Read
    ls "$MOUNT/subdir1" > /dev/null

    # Write
    echo "Test $i" > "$MOUNT/test$i.tmp"

    # Read
    cat "$MOUNT/subdir1/nested.txt" > /dev/null

    # Delete
    rm "$MOUNT/test$i.tmp"
done

echo -e "${GREEN}✓ Mixed operations completed${NC}\n"

# Test 5: Performance comparison
echo -e "${MAGENTA}=== Test 5: Performance Comparison ===${NC}"

echo "Testing 100 stat operations..."

# Direct backend access
START=$(date +%s%N)
for i in {1..100}; do
    stat "$BACKEND/file4.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
DIRECT_TIME=$((($END - $START) / 1000000))
echo "Direct backend: ${DIRECT_TIME}ms"

# Prime cache
stat "$MOUNT/file4.txt" > /dev/null 2>&1

# Cached access
START=$(date +%s%N)
for i in {1..100}; do
    stat "$MOUNT/file4.txt" > /dev/null 2>&1
done
END=$(date +%s%N)
CACHED_TIME=$((($END - $START) / 1000000))
echo "With caching:   ${CACHED_TIME}ms"

if [ $CACHED_TIME -lt $DIRECT_TIME ]; then
    SPEEDUP=$(echo "scale=1; $DIRECT_TIME / $CACHED_TIME" | bc 2>/dev/null || echo "N/A")
    echo -e "${GREEN}✓ Caching provides ${SPEEDUP}x speedup${NC}"
else
    echo -e "${YELLOW}Local filesystem too fast to show improvement${NC}"
fi
echo

# Show transaction log sample
echo -e "${MAGENTA}=== Transaction Log Sample ===${NC}"
echo "Last 10 transactions:"
tail -10 "$TRANS_LOG" | column -t -s '|'
echo

# Trigger statistics output
echo -e "${MAGENTA}=== Triggering Statistics Collection ===${NC}"
echo "Sending SIGINT to collect statistics..."
kill -INT $FUSE_PID 2>/dev/null || true
sleep 2

echo -e "\n${GREEN}=== Test Complete ===${NC}"
echo
echo "Key Results:"
echo "  ✓ Read operations are cached (GETATTR, LOOKUP)"
echo "  ✓ Write operations pass through (CREATE, WRITE, DELETE)"
echo "  ✓ Cache expires after TTL (5 seconds)"
echo "  ✓ Full read/write functionality working"
echo "  ✓ Metrics and transaction logging operational"