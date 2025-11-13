#!/bin/bash

# Diagnostic script to understand FUSE cache behavior
# This script uses strace to see if the kernel is caching

CACHED_MOUNT="/tmp/nfs-cached"
TEST_DIR="r0/d5"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "============================================"
echo "FORKSPOON CACHE DIAGNOSTIC"
echo "============================================"
echo ""

echo -e "${BLUE}This script will use strace to see if FUSE operations are being called${NC}"
echo "If caching is working, subsequent calls should NOT trigger FUSE operations"
echo ""

# Function to count FUSE operations
count_fuse_ops() {
    local trace_file=$1
    local op_name=$2

    count=$(grep -c "FUSE_${op_name}" "$trace_file" 2>/dev/null || echo 0)
    echo "$count"
}

echo -e "${YELLOW}Test 1: Initial ls (should trigger FUSE operations)${NC}"
echo "Running: strace -e trace=read,write -o /tmp/trace1.txt ls -la $CACHED_MOUNT/$TEST_DIR 2>/dev/null | wc -l"

strace -e trace=read,write -o /tmp/trace1.txt ls -la "$CACHED_MOUNT/$TEST_DIR" 2>/dev/null | wc -l

lookup_count1=$(count_fuse_ops /tmp/trace1.txt "LOOKUP")
getattr_count1=$(count_fuse_ops /tmp/trace1.txt "GETATTR")

echo "  FUSE operations detected:"
echo "  - LOOKUP operations: $lookup_count1"
echo "  - GETATTR operations: $getattr_count1"
echo ""

echo -e "${YELLOW}Waiting 2 seconds...${NC}"
sleep 2

echo -e "${YELLOW}Test 2: Immediate repeat (should use cache)${NC}"
echo "Running: strace -e trace=read,write -o /tmp/trace2.txt ls -la $CACHED_MOUNT/$TEST_DIR 2>/dev/null | wc -l"

strace -e trace=read,write -o /tmp/trace2.txt ls -la "$CACHED_MOUNT/$TEST_DIR" 2>/dev/null | wc -l

lookup_count2=$(count_fuse_ops /tmp/trace2.txt "LOOKUP")
getattr_count2=$(count_fuse_ops /tmp/trace2.txt "GETATTR")

echo "  FUSE operations detected:"
echo "  - LOOKUP operations: $lookup_count2"
echo "  - GETATTR operations: $getattr_count2"
echo ""

# Analysis
echo "============================================"
echo "ANALYSIS"
echo "============================================"

if [ "$lookup_count2" -eq 0 ] && [ "$getattr_count2" -eq 0 ]; then
    echo -e "${GREEN}✓ CACHE IS WORKING!${NC}"
    echo "  Second ls did not trigger any FUSE operations"
    echo "  Data was served from kernel cache"
elif [ "$lookup_count2" -lt "$lookup_count1" ] || [ "$getattr_count2" -lt "$getattr_count1" ]; then
    echo -e "${YELLOW}⚠ PARTIAL CACHING${NC}"
    echo "  Some operations were cached, but not all"
    echo "  First run: LOOKUP=$lookup_count1, GETATTR=$getattr_count1"
    echo "  Second run: LOOKUP=$lookup_count2, GETATTR=$getattr_count2"
else
    echo -e "${RED}✗ CACHE NOT WORKING${NC}"
    echo "  Same number of FUSE operations in both runs"
    echo "  Every ls is going through FUSE to the backend"
fi

echo ""
echo "For more details, examine:"
echo "  /tmp/trace1.txt - First run strace output"
echo "  /tmp/trace2.txt - Second run strace output"
echo ""

# Additional mount info
echo "============================================"
echo "MOUNT INFORMATION"
echo "============================================"
mount | grep "$CACHED_MOUNT" || echo "Mount not found"

echo ""
echo "FUSE mount options:"
grep "$CACHED_MOUNT" /proc/mounts | awk '{print $4}' || echo "Unable to get mount options"