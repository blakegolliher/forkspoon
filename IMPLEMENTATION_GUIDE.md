# Forkspoon Implementation Guide

## Overview

Forkspoon is a proof-of-concept FUSE filesystem that caches metadata operations for NFS mounts while passing through data operations unchanged.

## System Requirements

- Linux kernel 3.15+ with FUSE support
- Go 1.21+
- FUSE development libraries
- An existing NFS mount

### Installing Dependencies

RHEL/CentOS/Rocky Linux:
```bash
sudo yum install -y fuse fuse-libs
sudo yum groupinstall -y "Development Tools"
```

Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y fuse libfuse-dev build-essential
```

## Building

```bash
# Clone and build
git clone https://github.com/blakegolliher/forkspoon.git
cd forkspoon

# Build with make
make build

# Or build directly
go build -o forkspoon ./cmd/forkspoon
```

## Basic Usage

### Standard NFS Cache Setup

```bash
# Verify NFS is mounted
mount | grep nfs

# Create cache mount point
sudo mkdir -p /mnt/nfs-cached

# Mount with caching (5-minute TTL)
sudo ./forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/nfs-cached \
  -cache-ttl 5m

# Use the cached mount
ls -la /mnt/nfs-cached
```

### Command-Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `-backend` | required | Path to NFS mount |
| `-mountpoint` | required | Cache mount location |
| `-cache-ttl` | 5m | Cache duration (30s, 5m, 1h) |
| `-verbose` | false | Enable detailed logging |
| `-debug` | false | FUSE debug output |
| `-trans-log` | none | Transaction log path |
| `-stats-file` | none | JSON statistics file |
| `-allow-other` | false | Allow other users access |

## Testing

### Functional Test
```bash
# Test basic operations
./scripts/test_cache.sh
```

### Performance Benchmark
```bash
# Compare cached vs direct access
./scripts/benchmark.sh
```

### Manual Testing
```bash
# Terminal 1: Mount with verbose logging
./forkspoon -backend /mnt/nfs -mountpoint /mnt/cached -verbose

# Terminal 2: Test caching
ls -la /mnt/cached  # First access - cache miss
ls -la /mnt/cached  # Second access - cache hit (no logs)

# Wait for TTL to expire
sleep 300  # 5 minutes
ls -la /mnt/cached  # Cache miss again
```

## Performance Tuning

### Cache TTL Guidelines for NFS

| Workload | Recommended TTL | Notes |
|----------|-----------------|--------|
| Development | 30s-1m | Frequent changes |
| Build systems | 2-5m | Balance performance/freshness |
| Read-heavy | 5-10m | Maximum performance |
| Static content | 10-30m | Rarely changes |

### Monitoring Cache Effectiveness

```bash
# Enable transaction logging
./forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/cached \
  -trans-log /var/log/forkspoon.log \
  -stats-file /var/log/forkspoon-stats.json

# Monitor cache misses
tail -f /var/log/forkspoon.log | grep CACHE_MISS

# Check statistics
cat /var/log/forkspoon-stats.json | jq '.cached_operations'
```

## Troubleshooting

### Mount Issues

Permission denied:
```bash
# Add to /etc/fuse.conf
echo "user_allow_other" | sudo tee -a /etc/fuse.conf
```

Transport endpoint not connected:
```bash
fusermount -u /mnt/cached
# Then remount
```

### Performance Issues

Cache not effective:
- Check cache TTL is appropriate for workload
- Verify with verbose logging that cache is being used
- Ensure NFS mount itself is working properly

High memory usage:
- Reduce cache TTL
- Monitor with: `ps aux | grep forkspoon`

## Architecture Details

### What Gets Cached

Cached operations (served by kernel VFS after first access):
- `stat()` - File attributes
- `lookup()` - Directory entry resolution
- `readdir()` - Directory listings

Passthrough operations (never cached):
- `read()` / `write()` - File contents
- `create()` / `unlink()` - File creation/deletion
- `mkdir()` / `rmdir()` - Directory operations
- `rename()` - File moves

### Cache Behavior

1. First access to file/directory triggers cache miss
2. Metadata is cached in kernel VFS for TTL duration
3. Subsequent accesses served from kernel cache (no FUSE calls)
4. After TTL expires, next access refreshes cache

## Limitations

- Proof-of-concept implementation
- No cache invalidation beyond TTL expiry
- Changes to NFS mount directly won't be visible until cache expires
- Cache is volatile (lost on unmount)

## systemd Service (Optional)

Create `/etc/systemd/system/forkspoon.service`:

```ini
[Unit]
Description=Forkspoon NFS Cache
After=network.target remote-fs.target

[Service]
Type=forking
ExecStart=/usr/local/bin/forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/nfs-cached \
  -cache-ttl 5m \
  -trans-log /var/log/forkspoon.log

ExecStop=/usr/bin/fusermount -u /mnt/nfs-cached
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable forkspoon
sudo systemctl start forkspoon
```