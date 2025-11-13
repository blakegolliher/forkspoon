#!/bin/bash

# Example: Accelerating NFS mount with caching
# This example shows how to use forkspoon to speed up an NFS mount

# Configuration
NFS_MOUNT="/mnt/nfs-server"
CACHE_MOUNT="/mnt/nfs-cached"
CACHE_TTL="10m"  # 10 minutes for NFS

# Ensure NFS is mounted
if ! mountpoint -q "$NFS_MOUNT"; then
    echo "Error: NFS not mounted at $NFS_MOUNT"
    echo "Mount NFS first: sudo mount -t nfs server:/path $NFS_MOUNT"
    exit 1
fi

# Create cache mount point
sudo mkdir -p "$CACHE_MOUNT"

# Mount with caching
echo "Mounting cached NFS..."
forkspoon \
    -backend "$NFS_MOUNT" \
    -mountpoint "$CACHE_MOUNT" \
    -cache-ttl "$CACHE_TTL" \
    -allow-other \
    -trans-log "/var/log/nfs-cache.log" \
    -stats-file "/var/log/nfs-cache-stats.json"

echo "NFS cache mounted at: $CACHE_MOUNT"
echo "Cache TTL: $CACHE_TTL"
echo ""
echo "Performance test:"
echo -n "Direct NFS: "
time ls -la "$NFS_MOUNT" > /dev/null 2>&1

echo -n "Cached NFS: "
time ls -la "$CACHE_MOUNT" > /dev/null 2>&1

echo -n "Cached (2nd access): "
time ls -la "$CACHE_MOUNT" > /dev/null 2>&1