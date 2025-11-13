#!/bin/bash

# Debug script to understand why caching isn't working

echo "============================================"
echo "FORKSPOON CACHE DEBUG"
echo "============================================"
echo ""

# First, check what process is running
echo "1. Current forkspoon processes:"
ps aux | grep forkspoon | grep -v grep
echo ""

# Check when the binary was built
echo "2. Binary build time:"
stat ./forkspoon | grep Modify
echo ""

# Check mount
echo "3. Current mount:"
mount | grep nfs-cached
echo ""

# Check mount options in /proc/mounts
echo "4. Mount options from /proc/mounts:"
grep nfs-cached /proc/mounts
echo ""

# Kill and restart with debug output
echo "5. Restarting forkspoon with fresh mount..."
echo ""

# Kill existing
pkill -f forkspoon
sleep 2
fusermount -u /tmp/nfs-cached 2>/dev/null

# Start with debug
echo "Starting forkspoon with debug enabled..."
./forkspoon -backend /mnt/nfs-dest -mountpoint /tmp/nfs-cached -cache-ttl 30s -verbose -debug 2>&1 | head -50 &
FUSE_PID=$!

sleep 3

echo ""
echo "6. Testing cache behavior..."
echo ""

# Simple test
cd /tmp/nfs-cached
echo "First ls:"
strace -e trace=stat,lstat,getdents64 -c ls r0/d5 2>&1 | tail -5
echo ""
echo "Second ls (should have fewer syscalls if cached):"
strace -e trace=stat,lstat,getdents64 -c ls r0/d5 2>&1 | tail -5

echo ""
echo "7. Checking FUSE protocol version..."
modinfo fuse | grep version

echo ""
echo "To stop debug mode: kill $FUSE_PID"