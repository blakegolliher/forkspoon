#!/bin/bash

# Real-time cache monitoring script for Forkspoon
# Shows cache hit/miss percentages and operation rates

# Find the log file
if [ -f "/opt/forkspoon/forkspoon.log" ]; then
    LOG_FILE="/opt/forkspoon/forkspoon.log"
elif [ -f "$HOME/forkspoon.log" ]; then
    LOG_FILE="$HOME/forkspoon.log"
else
    echo "Error: Log file not found in /opt/forkspoon/ or $HOME/"
    echo "Make sure forkspoon is running with logging enabled"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  FORKSPOON CACHE MONITOR${NC}"
echo -e "${BLUE}================================${NC}"
echo "Log file: $LOG_FILE"
echo ""

# Function to calculate percentages
calc_percentage() {
    local hits=$1
    local total=$2
    if [ $total -eq 0 ]; then
        echo "0.0"
    else
        echo "scale=1; $hits * 100 / $total" | bc -l
    fi
}

# Main monitoring loop
while true; do
    if [ ! -f "$LOG_FILE" ]; then
        echo "Waiting for log file..."
        sleep 2
        continue
    fi

    # Count operations from log
    total_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

    # Count different operation types
    lookup_miss=$(grep -c "LOOKUP.*CACHE_MISS" "$LOG_FILE" 2>/dev/null || echo 0)
    lookup_hit=$(grep -c "LOOKUP.*CACHE_HIT" "$LOG_FILE" 2>/dev/null || echo 0)
    getattr_miss=$(grep -c "GETATTR.*CACHE_MISS" "$LOG_FILE" 2>/dev/null || echo 0)
    getattr_hit=$(grep -c "GETATTR.*CACHE_HIT" "$LOG_FILE" 2>/dev/null || echo 0)
    readdir_miss=$(grep -c "READDIR.*CACHE_MISS" "$LOG_FILE" 2>/dev/null || echo 0)
    readdir_hit=$(grep -c "READDIR.*CACHE_HIT" "$LOG_FILE" 2>/dev/null || echo 0)

    # Calculate totals
    total_lookup=$((lookup_miss + lookup_hit))
    total_getattr=$((getattr_miss + getattr_hit))
    total_readdir=$((readdir_miss + readdir_hit))
    total_ops=$((total_lookup + total_getattr + total_readdir))
    total_hits=$((lookup_hit + getattr_hit + readdir_hit))
    total_misses=$((lookup_miss + getattr_miss + readdir_miss))

    # Calculate percentages
    lookup_hit_rate=$(calc_percentage $lookup_hit $total_lookup)
    getattr_hit_rate=$(calc_percentage $getattr_hit $total_getattr)
    readdir_hit_rate=$(calc_percentage $readdir_hit $total_readdir)
    overall_hit_rate=$(calc_percentage $total_hits $total_ops)

    # Clear and redraw
    printf "\033[8A"  # Move cursor up 8 lines

    # Display stats
    echo -e "${CYAN}CACHE STATISTICS ($(date '+%H:%M:%S'))${NC}"
    echo "─────────────────────────────────────"

    # Overall stats
    if [ $total_ops -gt 0 ]; then
        if (( $(echo "$overall_hit_rate > 50" | bc -l) )); then
            color=$GREEN
        elif (( $(echo "$overall_hit_rate > 20" | bc -l) )); then
            color=$YELLOW
        else
            color=$RED
        fi
        echo -e "Overall Hit Rate: ${color}${overall_hit_rate}%${NC} ($total_hits hits / $total_misses misses)"
    else
        echo "Overall Hit Rate: No operations yet"
    fi

    echo ""
    echo "Operation Breakdown:"
    printf "  %-10s: %6d ops | Hit Rate: %5.1f%% | H:%d M:%d\n" "LOOKUP" $total_lookup $lookup_hit_rate $lookup_hit $lookup_miss
    printf "  %-10s: %6d ops | Hit Rate: %5.1f%% | H:%d M:%d\n" "GETATTR" $total_getattr $getattr_hit_rate $getattr_hit $getattr_miss
    printf "  %-10s: %6d ops | Hit Rate: %5.1f%% | H:%d M:%d\n" "READDIR" $total_readdir $readdir_hit_rate $readdir_hit $readdir_miss

    echo ""

    # Show recent activity (last 5 lines)
    if [ $total_lines -gt 0 ]; then
        echo "Recent Activity:"
        tail -5 "$LOG_FILE" | while IFS='|' read -r timestamp op status path; do
            op=$(echo "$op" | xargs)
            status=$(echo "$status" | xargs)

            if [[ "$status" == "CACHE_HIT" ]]; then
                status_color=$GREEN
            elif [[ "$status" == "CACHE_MISS" ]]; then
                status_color=$RED
            else
                status_color=$YELLOW
            fi

            printf "  %-10s: ${status_color}%-12s${NC}\n" "$op" "$status"
        done | tail -3
    fi

    sleep 2
done