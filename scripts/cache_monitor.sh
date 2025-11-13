#!/bin/bash

# Smart cache monitoring for Forkspoon
# Understands that cache hits = no operations logged

# Find the log file
if [ -f "/opt/forkspoon/forkspoon.log" ]; then
    LOG_FILE="/opt/forkspoon/forkspoon.log"
elif [ -f "$HOME/forkspoon.log" ]; then
    LOG_FILE="$HOME/forkspoon.log"
else
    LOG_FILE=""
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}       FORKSPOON CACHE MONITOR${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

if [ -z "$LOG_FILE" ]; then
    echo -e "${RED}ERROR: Log file not found!${NC}"
    echo "Checked: /opt/forkspoon/forkspoon.log"
    echo "Checked: $HOME/forkspoon.log"
    echo ""
    echo "Make sure forkspoon is running with the new binary"
    exit 1
fi

echo "Log file: $LOG_FILE"
echo ""
echo -e "${CYAN}IMPORTANT:${NC}"
echo "• When operations appear in log = CACHE MISS (kernel cache expired)"
echo "• When NO operations appear = CACHE HIT (served from kernel cache)"
echo "• Low operation rate = Good (cache is working)"
echo "• High operation rate = Bad (cache misses)"
echo ""
echo "─────────────────────────────────────────────"

# Initialize counters
prev_count=0
if [ -f "$LOG_FILE" ]; then
    prev_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
fi

# Track operations per interval
declare -A path_counts
declare -A path_last_seen

while true; do
    if [ ! -f "$LOG_FILE" ]; then
        echo "Waiting for log file to be created..."
        sleep 2
        continue
    fi

    # Get current line count
    current_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

    # Calculate new operations
    new_ops=$((current_count - prev_count))

    # Get timestamp
    timestamp=$(date '+%H:%M:%S')

    # Determine cache effectiveness based on operation rate
    if [ $new_ops -eq 0 ]; then
        status="${GREEN}EXCELLENT - Full cache hit (no operations)${NC}"
        indicator="✓✓✓"
    elif [ $new_ops -le 5 ]; then
        status="${GREEN}GOOD - Mostly cached${NC}"
        indicator="✓✓"
    elif [ $new_ops -le 20 ]; then
        status="${YELLOW}MODERATE - Some cache misses${NC}"
        indicator="✓"
    else
        status="${RED}POOR - Many cache misses${NC}"
        indicator="✗"
    fi

    # Clear previous output (move cursor up)
    if [ $prev_count -gt 0 ]; then
        printf "\033[15A"  # Move up 15 lines
    fi

    # Display current status
    echo -e "${CYAN}[$timestamp] Monitoring...${NC}"
    echo "─────────────────────────────────────────────"
    echo -e "Cache Status: $status $indicator"
    echo "Operations in last 2 seconds: $new_ops"
    echo ""

    # Show operation breakdown if there were any
    if [ $new_ops -gt 0 ]; then
        echo "Recent operations (cache misses):"

        # Get the new lines and count by operation type
        tail -n $new_ops "$LOG_FILE" | while IFS='|' read -r timestamp op status path; do
            op=$(echo "$op" | xargs)
            echo "$op"
        done | sort | uniq -c | while read count op; do
            printf "  %-10s: %3d operations\n" "$op" "$count"
        done

        echo ""
        echo "Most accessed paths (last interval):"
        tail -n $new_ops "$LOG_FILE" | while IFS='|' read -r timestamp op status path; do
            path=$(echo "$path" | xargs)
            # Get just the filename for readability
            basename "$path"
        done | sort | uniq -c | sort -rn | head -5 | while read count path; do
            printf "  %3d: %s\n" "$count" "$path"
        done
    else
        echo -e "${GREEN}No operations = Cache serving all requests!${NC}"
        echo ""
        echo "Last operation was more than 2 seconds ago."
        echo "All metadata requests are being served from kernel cache."
    fi

    echo ""
    echo "─────────────────────────────────────────────"
    echo "Total operations since start: $current_count"
    echo "Press Ctrl+C to exit"

    # Update previous count
    prev_count=$current_count

    # Wait before next update
    sleep 2
done