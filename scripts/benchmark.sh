#!/bin/bash

# Performance benchmark script for forkspoon
# Compares performance with and without caching

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BACKEND_DIR="/tmp/benchmark-backend"
MOUNT_DIR="/tmp/benchmark-mount"
NUM_FILES=1000
NUM_DIRS=50
NUM_OPS=1000

echo -e "${CYAN}=== Metadata-Caching FUSE Filesystem Benchmark ===${NC}"
echo

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"

    # Kill FUSE daemon if running
    [ ! -z "$FUSE_PID" ] && kill $FUSE_PID 2>/dev/null || true

    # Unmount if mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        fusermount -u "$MOUNT_DIR" 2>/dev/null || sudo umount "$MOUNT_DIR" 2>/dev/null || true
        sleep 1
    fi

    # Remove test directories
    [ -d "$MOUNT_DIR" ] && rmdir "$MOUNT_DIR" 2>/dev/null || true
    [ -d "$BACKEND_DIR" ] && rm -rf "$BACKEND_DIR" 2>/dev/null || true
}

# Set up cleanup on exit
trap cleanup EXIT INT TERM

# Function to create test data
create_test_data() {
    echo -e "${GREEN}Creating test data...${NC}"
    echo "  - Creating $NUM_DIRS directories"
    echo "  - Creating $NUM_FILES files"

    for i in $(seq 1 $NUM_DIRS); do
        mkdir -p "$BACKEND_DIR/dir$i"
        for j in $(seq 1 $((NUM_FILES / NUM_DIRS))); do
            echo "Test file $i-$j" > "$BACKEND_DIR/dir$i/file$j.txt"
        done
    done

    echo -e "${GREEN}✓ Test data created${NC}\n"
}

# Function to run benchmark
run_benchmark() {
    local description=$1
    local mount_path=$2
    local test_name=$3

    echo -e "${BLUE}Running: $description${NC}"

    # Warm up if testing cache
    if [ "$test_name" == "cached" ]; then
        find "$mount_path" -type f > /dev/null 2>&1
        echo "  Cache warmed up"
    fi

    # Test 1: find all files
    echo -n "  Finding all files ($NUM_FILES files): "
    TIME_FIND=$( { time -p find "$mount_path" -type f > /dev/null 2>&1; } 2>&1 | grep real | awk '{print $2}')
    echo "${TIME_FIND}s"

    # Test 2: stat operations
    echo -n "  Stat operations (${NUM_OPS} ops): "
    TIME_STAT=$( { time -p for i in $(seq 1 $NUM_OPS); do
        stat "$mount_path/dir$((i % NUM_DIRS + 1))/file$((i % 20 + 1)).txt" > /dev/null 2>&1
    done; } 2>&1 | grep real | awk '{print $2}')
    echo "${TIME_STAT}s"

    # Test 3: ls operations
    echo -n "  Directory listings (${NUM_DIRS} dirs): "
    TIME_LS=$( { time -p for i in $(seq 1 $NUM_DIRS); do
        ls -la "$mount_path/dir$i" > /dev/null 2>&1
    done; } 2>&1 | grep real | awk '{print $2}')
    echo "${TIME_LS}s"

    # Test 4: recursive ls
    echo -n "  Recursive ls (entire tree): "
    TIME_RECURSIVE=$( { time -p ls -laR "$mount_path" > /dev/null 2>&1; } 2>&1 | grep real | awk '{print $2}')
    echo "${TIME_RECURSIVE}s"

    # Store results for comparison
    if [ "$test_name" == "direct" ]; then
        DIRECT_FIND=$TIME_FIND
        DIRECT_STAT=$TIME_STAT
        DIRECT_LS=$TIME_LS
        DIRECT_RECURSIVE=$TIME_RECURSIVE
    else
        CACHED_FIND=$TIME_FIND
        CACHED_STAT=$TIME_STAT
        CACHED_LS=$TIME_LS
        CACHED_RECURSIVE=$TIME_RECURSIVE
    fi

    echo
}

# Function to calculate speedup
calc_speedup() {
    local direct=$1
    local cached=$2
    echo "scale=2; $direct / $cached" | bc
}

# Main benchmark execution
main() {
    # Step 1: Setup
    echo -e "${GREEN}Step 1: Setting up benchmark environment${NC}"
    mkdir -p "$BACKEND_DIR"
    mkdir -p "$MOUNT_DIR"

    # Step 2: Create test data
    create_test_data

    # Step 3: Benchmark direct access
    echo -e "${CYAN}=== Benchmark 1: Direct Backend Access ===${NC}"
    run_benchmark "Direct access to $BACKEND_DIR" "$BACKEND_DIR" "direct"

    # Step 4: Build and mount FUSE filesystem
    echo -e "${GREEN}Building FUSE filesystem...${NC}"
    if [ -f ./forkspoon ]; then
        echo "Using existing binary"
    elif command -v go &> /dev/null; then
        go build -o forkspoon main.go
        echo "✓ Built successfully"
    else
        echo -e "${RED}Cannot build: Go not installed${NC}"
        exit 1
    fi
    echo

    # Step 5: Mount filesystem
    echo -e "${GREEN}Mounting FUSE filesystem...${NC}"
    ./forkspoon -backend "$BACKEND_DIR" -mountpoint "$MOUNT_DIR" -cache-ttl 10m 2>/dev/null &
    FUSE_PID=$!
    sleep 2

    if ! mountpoint -q "$MOUNT_DIR"; then
        echo -e "${RED}Mount failed!${NC}"
        exit 1
    fi
    echo "✓ Mounted successfully"
    echo

    # Step 6: Benchmark cached access
    echo -e "${CYAN}=== Benchmark 2: Cached FUSE Access ===${NC}"
    run_benchmark "FUSE cached access to $MOUNT_DIR" "$MOUNT_DIR" "cached"

    # Step 7: Calculate and display results
    echo -e "${CYAN}=== Performance Comparison ===${NC}"
    echo
    echo -e "${YELLOW}Operation          Direct    Cached    Speedup${NC}"
    echo "------------------------------------------------"

    if command -v bc &> /dev/null; then
        SPEEDUP_FIND=$(calc_speedup $DIRECT_FIND $CACHED_FIND)
        SPEEDUP_STAT=$(calc_speedup $DIRECT_STAT $CACHED_STAT)
        SPEEDUP_LS=$(calc_speedup $DIRECT_LS $CACHED_LS)
        SPEEDUP_RECURSIVE=$(calc_speedup $DIRECT_RECURSIVE $CACHED_RECURSIVE)

        printf "Find files         %6.2fs   %6.2fs   %5.1fx\n" $DIRECT_FIND $CACHED_FIND $SPEEDUP_FIND
        printf "Stat operations    %6.2fs   %6.2fs   %5.1fx\n" $DIRECT_STAT $CACHED_STAT $SPEEDUP_STAT
        printf "Directory listings %6.2fs   %6.2fs   %5.1fx\n" $DIRECT_LS $CACHED_LS $SPEEDUP_LS
        printf "Recursive ls       %6.2fs   %6.2fs   %5.1fx\n" $DIRECT_RECURSIVE $CACHED_RECURSIVE $SPEEDUP_RECURSIVE
    else
        printf "Find files         %6.2fs   %6.2fs\n" $DIRECT_FIND $CACHED_FIND
        printf "Stat operations    %6.2fs   %6.2fs\n" $DIRECT_STAT $CACHED_STAT
        printf "Directory listings %6.2fs   %6.2fs\n" $DIRECT_LS $CACHED_LS
        printf "Recursive ls       %6.2fs   %6.2fs\n" $DIRECT_RECURSIVE $CACHED_RECURSIVE
    fi

    echo
    echo -e "${GREEN}=== Benchmark Complete ===${NC}"
    echo
    echo "Notes:"
    echo "- Speedup values > 1.0x indicate cache is faster"
    echo "- Results vary based on backend filesystem type"
    echo "- Cache is most effective for network filesystems"
}

# Run the benchmark
main