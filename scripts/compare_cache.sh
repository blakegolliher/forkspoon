#!/bin/bash

# Test script to compare cached vs uncached NFS performance
# and check for cache hits/misses

CACHED_MOUNT="/tmp/nfs-cached"
UNCACHED_MOUNT="/mnt/nfs-dest"
TEST_DIR="r0/d5"

# Find the log file
if [ -f "/opt/forkspoon/forkspoon.log" ]; then
    LOG_FILE="/opt/forkspoon/forkspoon.log"
elif [ -f "$HOME/forkspoon.log" ]; then
    LOG_FILE="$HOME/forkspoon.log"
else
    LOG_FILE=""
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "FORKSPOON CACHE PERFORMANCE TEST"
echo "============================================"
echo "Test started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Function to run test and capture timing
run_test() {
    local mount_point=$1
    local test_name=$2
    local iteration=$3

    echo -e "${YELLOW}[$test_name - Run $iteration]${NC}"

    # Mark the log position before the test
    if [ -f "$LOG_FILE" ]; then
        log_position=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    else
        log_position=0
    fi

    # Run the ls command and time it
    start_time=$(date '+%Y-%m-%d %H:%M:%S.%N')
    result=$(time -p bash -c "ls -la $mount_point/$TEST_DIR/* | wc -l" 2>&1)

    # Extract timing
    real_time=$(echo "$result" | grep "^real" | awk '{print $2}')
    file_count=$(echo "$result" | grep -v "^real\|^user\|^sys" | tail -1)

    echo "  Files counted: $file_count"
    echo "  Time taken: ${real_time}s"

    # Check for cache hits/misses in log (only for cached mount)
    if [[ "$mount_point" == "$CACHED_MOUNT" ]] && [ -f "$LOG_FILE" ]; then
        sleep 0.1  # Give logs time to flush

        # Get new log entries since test started
        new_entries=$(($(wc -l < "$LOG_FILE" 2>/dev/null || echo 0) - log_position))

        if [ $new_entries -gt 0 ]; then
            cache_misses=$(tail -n $new_entries "$LOG_FILE" | grep -c "CACHE_MISS" || true)
            cache_hits=$(tail -n $new_entries "$LOG_FILE" | grep -c "CACHE_HIT" || true)

            if [ $cache_misses -gt 0 ] || [ $cache_hits -gt 0 ]; then
                echo -e "  Cache Stats: ${RED}Misses: $cache_misses${NC} / ${GREEN}Hits: $cache_hits${NC}"

                # Calculate hit rate for this run
                total_ops=$((cache_hits + cache_misses))
                if [ $total_ops -gt 0 ]; then
                    hit_rate=$((cache_hits * 100 / total_ops))
                    echo -e "  Hit Rate: ${GREEN}${hit_rate}%${NC}"
                fi

                # If iteration > 1 and we have hits, cache is working!
                if [ $iteration -gt 1 ] && [ $cache_hits -gt 0 ]; then
                    echo -e "  ${GREEN}✓ Cache is working! Directory reads are being cached${NC}"
                elif [ $iteration -gt 1 ] && [ $cache_misses -gt 0 ] && [ $cache_hits -eq 0 ]; then
                    echo -e "  ${RED}⚠ Warning: Expected cache hits but got only misses${NC}"
                fi
            else
                # No new log entries might mean kernel cache served the request
                echo -e "  ${GREEN}✓ No new operations logged (likely served from kernel cache)${NC}"
            fi
        else
            echo -e "  ${GREEN}✓ No new operations logged (likely served from kernel cache)${NC}"
        fi
    fi

    echo ""
}

# Test 1: Uncached NFS mount baseline
echo -e "${GREEN}=== UNCACHED NFS PERFORMANCE (Baseline) ===${NC}"
echo "Mount: $UNCACHED_MOUNT"
echo ""
for i in 1 2 3; do
    run_test "$UNCACHED_MOUNT" "UNCACHED" $i
done

# Test 2: Cached mount - should see improvement after first run
echo -e "${GREEN}=== CACHED FUSE MOUNT PERFORMANCE ===${NC}"
echo "Mount: $CACHED_MOUNT"
echo ""

# First run - expect cache misses
echo -e "${YELLOW}First run - expecting cache misses:${NC}"
run_test "$CACHED_MOUNT" "CACHED" 1

# Wait a moment for cache to settle
sleep 1

# Second run - should be from cache
echo -e "${YELLOW}Second run - expecting cache hits (no new operations):${NC}"
run_test "$CACHED_MOUNT" "CACHED" 2

# Third run - should also be from cache
echo -e "${YELLOW}Third run - expecting cache hits (no new operations):${NC}"
run_test "$CACHED_MOUNT" "CACHED" 3

# Summary
echo "============================================"
echo "TEST SUMMARY"
echo "============================================"

# Check if we have the log file to analyze
if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    total_misses=$(grep -c "CACHE_MISS" "$LOG_FILE" 2>/dev/null || echo 0)
    total_hits=$(grep -c "CACHE_HIT" "$LOG_FILE" 2>/dev/null || echo 0)

    echo "Overall Cache Analysis:"
    echo "  Total cache hits logged: $total_hits"
    echo "  Total cache misses logged: $total_misses"

    if [ $((total_hits + total_misses)) -gt 0 ]; then
        overall_hit_rate=$((total_hits * 100 / (total_hits + total_misses)))
        echo -e "  Overall hit rate: ${GREEN}${overall_hit_rate}%${NC}"
    fi

    echo ""
    echo -e "${CYAN}How caching works:${NC}"
    echo "  • READDIR operations are cached in memory (we can log hits!)"
    echo "  • GETATTR/LOOKUP cached by kernel (no logs = cache hit)"
    echo ""

    if [ $total_hits -gt 0 ]; then
        echo -e "${GREEN}✓ SUCCESS: Cache is working! We logged $total_hits cache hits${NC}"
    else
        echo -e "${YELLOW}Check if you're using the latest binary with READDIR caching${NC}"
    fi
else
    echo -e "${YELLOW}Warning: Log file not found${NC}"
    echo "Checked: /opt/forkspoon/forkspoon.log"
    echo "Checked: $HOME/forkspoon.log"
    echo ""
    echo "Make sure forkspoon is running with logging enabled"
fi

echo ""
echo "Test completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"