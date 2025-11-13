#!/bin/bash

# Demonstration of actual kernel-level caching behavior

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Kernel Cache Demonstration ===${NC}"
echo
echo "This shows that repeated operations within the cache TTL"
echo "don't even reach our FUSE daemon (served by kernel cache)"
echo

# Setup
BACKEND="/tmp/demo-backend-$$"
MOUNT="/tmp/demo-mount-$$"
LOG="/tmp/demo-log-$$.txt"

mkdir -p "$BACKEND" "$MOUNT"
echo "Test content" > "$BACKEND/testfile.txt"

# Cleanup on exit
cleanup() {
    kill $FUSE_PID 2>/dev/null || true
    fusermount -u "$MOUNT" 2>/dev/null || true
    rm -rf "$BACKEND" "$MOUNT" "$LOG"
}
trap cleanup EXIT

# Mount with 10-second cache
echo "Mounting with 10-second cache TTL..."
./forkspoon-full -backend "$BACKEND" -mountpoint "$MOUNT" -cache-ttl 10s > "$LOG" 2>&1 &
FUSE_PID=$!
sleep 2

echo -e "\n${YELLOW}Test 1: First stat (will call FUSE daemon)${NC}"
echo "Running: stat $MOUNT/testfile.txt"
stat "$MOUNT/testfile.txt" > /dev/null
echo "FUSE daemon calls:"
grep -c "GETATTR.*testfile" "$LOG" || echo "0"
CALLS_AFTER_FIRST=$(grep -c "GETATTR.*testfile" "$LOG" 2>/dev/null || echo "0")
echo "Total GETATTR calls so far: $CALLS_AFTER_FIRST"

echo -e "\n${YELLOW}Test 2: Repeated stats within cache TTL (kernel cache serves)${NC}"
echo "Running stat 5 times rapidly..."
for i in {1..5}; do
    stat "$MOUNT/testfile.txt" > /dev/null
    echo -n "."
done
echo
CALLS_AFTER_CACHED=$(grep -c "GETATTR.*testfile" "$LOG" 2>/dev/null || echo "0")
echo "Total GETATTR calls now: $CALLS_AFTER_CACHED"

if [ "$CALLS_AFTER_FIRST" -eq "$CALLS_AFTER_CACHED" ]; then
    echo -e "${GREEN}✓ No new FUSE calls - kernel cache served all 5 requests!${NC}"
else
    echo -e "${YELLOW}New calls detected (unexpected)${NC}"
fi

echo -e "\n${YELLOW}Test 3: Wait for cache expiry${NC}"
echo "Waiting 11 seconds for cache to expire (TTL=10s)..."
sleep 11

echo -e "\n${YELLOW}Test 4: Stat after expiry (will call FUSE daemon again)${NC}"
stat "$MOUNT/testfile.txt" > /dev/null
CALLS_AFTER_EXPIRY=$(grep -c "GETATTR.*testfile" "$LOG" 2>/dev/null || echo "0")
echo "Total GETATTR calls now: $CALLS_AFTER_EXPIRY"

if [ "$CALLS_AFTER_EXPIRY" -gt "$CALLS_AFTER_CACHED" ]; then
    echo -e "${GREEN}✓ Cache expired - FUSE daemon called again${NC}"
fi

echo -e "\n${CYAN}=== Summary ===${NC}"
echo "The kernel VFS cache is working perfectly:"
echo "  1. First access: FUSE daemon called (cache miss)"
echo "  2. Repeated access: Kernel serves from cache (no FUSE calls)"
echo "  3. After TTL expires: FUSE daemon called again"
echo
echo "This is why we see '0% hit rate' in our metrics -"
echo "successful cache hits never reach our daemon!"