# Forkspoon

A proof-of-concept FUSE filesystem that provides metadata caching for NFS mounts.

## Overview

Forkspoon is a POC implementation that demonstrates how to reduce metadata operations on NFS filesystems by implementing aggressive caching at the FUSE layer. It intercepts and caches metadata operations while passing through data operations directly to the backend.

## Purpose

This project explores the feasibility of improving NFS performance for metadata-heavy workloads by caching:
- File attributes (stat operations)
- Directory entry lookups
- Directory listings

Data operations (read/write) pass through directly to maintain data integrity.

## Requirements

- Linux kernel 3.15+ with FUSE support
- Go 1.21+
- FUSE libraries
- An existing NFS mount to accelerate

## Building from Source

```bash
# Clone repository
git clone https://github.com/blakegolliher/forkspoon.git
cd forkspoon

# Build
go mod download
go build -o forkspoon ./cmd/forkspoon

# Or use make
make build
```

## Usage

Basic usage to cache an NFS mount:

```bash
# Assume NFS is mounted at /mnt/nfs
# Create a cache mount point
mkdir /mnt/nfs-cached

# Mount with 5-minute cache TTL
./forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/nfs-cached \
  -cache-ttl 5m

# Access files through the cache mount
ls -la /mnt/nfs-cached
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `-backend` | required | Path to NFS mount |
| `-mountpoint` | required | Where to mount cached filesystem |
| `-cache-ttl` | 5m | Cache timeout duration |
| `-verbose` | false | Enable verbose logging |
| `-trans-log` | none | Transaction log file path |
| `-stats-file` | none | Statistics output file |

## Testing

Run the test suite:

```bash
# Quick functionality test
./scripts/quick_test.sh

# Performance benchmark
./scripts/benchmark.sh

# Cache behavior test
./scripts/test_cache.sh
```

## How It Works

1. Forkspoon mounts as a FUSE filesystem layered over your NFS mount
2. Metadata operations are cached for the configured TTL
3. The kernel serves cached metadata without calling our FUSE daemon
4. After TTL expires, the next access refreshes the cache
5. All data operations bypass the cache entirely

## Performance Expectations

For NFS mounts, typical improvements for metadata operations:
- Directory listings: 5-10x faster
- File stat operations: 5-15x faster
- Find operations: 10x+ faster

Actual improvements depend on network latency to the NFS server.

## Monitoring

View cache behavior with transaction logging:

```bash
# Enable transaction log
./forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/cached \
  -trans-log /tmp/forkspoon.log \
  -verbose

# Monitor cache misses
tail -f /tmp/forkspoon.log | grep CACHE_MISS
```

## Limitations

- This is a proof-of-concept, not production software
- No active cache invalidation (relies on TTL expiry)
- Cache is lost on unmount
- Changes made directly to the NFS mount won't be visible until cache expires

## Architecture

```
Application
    |
Linux VFS (kernel cache)
    |
FUSE Kernel Module
    |
Forkspoon Daemon
    |
NFS Mount
```

## License

MIT License - see LICENSE file

## Status

This is a proof-of-concept project for testing metadata caching strategies with NFS filesystems.