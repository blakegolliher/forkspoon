# Implementation Guide - Metadata-Caching FUSE Filesystem

## Table of Contents
1. [Quick Start](#quick-start)
2. [System Requirements](#system-requirements)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Testing](#testing)
6. [Performance Tuning](#performance-tuning)
7. [Monitoring](#monitoring)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/forkspoon.git
cd forkspoon

# Install Go (if not installed)
./scripts/install_go.sh

# Build the filesystem
make build

# Run a quick test
./scripts/quick_test.sh

# Mount your filesystem
./forkspoon \
  -backend /mnt/slow-storage \
  -mountpoint /mnt/fast-cache \
  -cache-ttl 5m
```

---

## System Requirements

### Minimum Requirements
- Linux kernel 3.15+ (FUSE support)
- Go 1.19+ (1.21 recommended)
- 512MB RAM
- FUSE libraries installed

### Recommended Setup
- Linux kernel 5.4+
- Go 1.21+
- 2GB+ RAM for large directory trees
- SSD for transaction logs

### Installing Dependencies

#### RHEL/CentOS/Rocky Linux
```bash
sudo yum install -y fuse fuse-libs
sudo yum groupinstall -y "Development Tools"
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y fuse libfuse-dev build-essential
```

#### Enable FUSE for Non-root Users
```bash
# Add user to fuse group
sudo usermod -a -G fuse $USER

# Enable user_allow_other in fuse.conf
echo "user_allow_other" | sudo tee -a /etc/fuse.conf

# Logout and login for group changes to take effect
```

---

## Installation

### Method 1: From Source
```bash
# Clone repository
git clone https://github.com/yourusername/forkspoon.git
cd forkspoon

# Install Go if needed
./scripts/install_go.sh
source ~/.bashrc

# Build
make build

# Install system-wide (optional)
sudo make install
```

### Method 2: Pre-built Binary
```bash
# Download latest release
wget https://github.com/yourusername/forkspoon/releases/latest/download/forkspoon-linux-amd64.tar.gz

# Extract
tar -xzf forkspoon-linux-amd64.tar.gz

# Make executable
chmod +x forkspoon

# Move to PATH (optional)
sudo mv forkspoon /usr/local/bin/
```

### Method 3: Docker Container
```bash
# Build container
docker build -t forkspoon .

# Run with privileges for FUSE
docker run --privileged \
  -v /mnt/backend:/backend \
  -v /mnt/cache:/cache \
  forkspoon
```

---

## Configuration

### Command-Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `-backend` | (required) | Path to backend directory |
| `-mountpoint` | (required) | Where to mount cached filesystem |
| `-cache-ttl` | 5m | Cache timeout (e.g., 30s, 5m, 1h) |
| `-allow-other` | false | Allow other users to access mount |
| `-verbose` | false | Enable verbose logging |
| `-debug` | false | Enable FUSE debug output |
| `-trans-log` | (none) | Transaction log file path |
| `-stats-file` | (none) | Statistics output file (JSON) |

### Configuration File (optional)
Create `~/.forkspoon.yaml`:

```yaml
# Default configuration
cache_ttl: 5m
verbose: false
allow_other: false

# Logging
transaction_log: /var/log/cache-fuse/transactions.log
stats_file: /var/log/cache-fuse/stats.json

# Performance
max_background: 128
max_write: 1048576  # 1MB
max_readahead: 1048576  # 1MB

# Mount profiles
profiles:
  nfs:
    cache_ttl: 10m
    verbose: true

  dev:
    cache_ttl: 30s
    debug: true
```

### Environment Variables
```bash
export CACHE_FUSE_TTL="10m"
export CACHE_FUSE_VERBOSE="true"
export CACHE_FUSE_LOG_DIR="/var/log/cache-fuse"
```

---

## Testing

### 1. Basic Functionality Test
```bash
# Run automated test suite
make test

# Or manually
./scripts/test_basic.sh
```

### 2. Write Operations Test
```bash
# Test all write operations
./scripts/test_writes.sh

# What it tests:
# - File creation
# - Content modification
# - File deletion
# - Directory operations
# - Rename operations
```

### 3. Cache Behavior Test
```bash
# Verify caching is working
./scripts/test_cache.sh

# This will:
# 1. Mount with 5-second TTL
# 2. Access files (cache miss)
# 3. Re-access immediately (cache hit)
# 4. Wait for expiry
# 5. Access again (cache miss)
```

### 4. Performance Benchmark
```bash
# Run performance comparison
./scripts/benchmark.sh

# Compares:
# - Direct backend access
# - Cached access
# - Shows speedup factor
```

### 5. Stress Test
```bash
# High-load testing
./scripts/stress_test.sh \
  -files 10000 \
  -threads 50 \
  -duration 60s
```

---

## Performance Tuning

### Cache TTL Selection

| Use Case | Recommended TTL | Rationale |
|----------|-----------------|-----------|
| Development | 30s-1m | Quick feedback on changes |
| Read-heavy workloads | 5-10m | Maximum performance |
| Build systems | 1-5m | Balance freshness/speed |
| Home directories | 1-2m | User file changes |
| Archive/Backup | 30m-1h | Rarely changes |

### Kernel Parameters
```bash
# Increase inode cache
echo 50 | sudo tee /proc/sys/vm/vfs_cache_pressure

# Increase directory entry cache
echo 100000 | sudo tee /proc/sys/fs/dentry-state

# Monitor cache usage
cat /proc/meminfo | grep -E "Cached|Slab"
```

### Mount Options for Different Backends

#### NFS Backend
```bash
./forkspoon \
  -backend /mnt/nfs \
  -mountpoint /mnt/cached-nfs \
  -cache-ttl 10m \
  -allow-other
```

#### S3FS/Cloud Storage Backend
```bash
./forkspoon \
  -backend /mnt/s3fs \
  -mountpoint /mnt/cached-s3 \
  -cache-ttl 30m  # Higher TTL for slow backends
```

#### Local SSD Cache of HDD
```bash
./forkspoon \
  -backend /mnt/hdd-storage \
  -mountpoint /mnt/ssd-cache \
  -cache-ttl 1m
```

---

## Monitoring

### Real-time Monitoring
```bash
# Watch transaction log
tail -f /var/log/cache-fuse/transactions.log

# Monitor cache misses only
tail -f /var/log/cache-fuse/transactions.log | grep CACHE_MISS

# Count operations per second
watch -n 1 'tail -1000 /var/log/cache-fuse/transactions.log | grep "$(date +%H:%M)" | wc -l'
```

### Statistics Analysis
```bash
# Parse JSON statistics
cat /var/log/cache-fuse/stats.json | jq '.'

# Get cache hit rate
cat /var/log/cache-fuse/stats.json | jq '.cached_operations.getattr.hit_rate'

# Operations summary
cat /var/log/cache-fuse/stats.json | jq '.passthrough_operations'
```

### Grafana Dashboard
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'cache-fuse'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
```

### Health Checks
```bash
# Check if mounted
mountpoint -q /mnt/cache && echo "OK" || echo "NOT MOUNTED"

# Check cache effectiveness
./scripts/check_cache_health.sh

# Monitor memory usage
ps aux | grep forkspoon
```

---

## Troubleshooting

### Common Issues

#### 1. Mount Permission Denied
```bash
# Solution: Add user_allow_other to fuse.conf
echo "user_allow_other" | sudo tee -a /etc/fuse.conf

# Or run without -allow-other flag
./forkspoon -backend /src -mountpoint /dst
```

#### 2. Transport endpoint is not connected
```bash
# Force unmount and remount
fusermount -uz /mnt/cache
# or
sudo umount -l /mnt/cache

# Then remount
```

#### 3. Poor Cache Performance
```bash
# Check cache TTL is appropriate
# Increase TTL for better performance
./forkspoon ... -cache-ttl 10m

# Verify kernel cache pressure
cat /proc/sys/vm/vfs_cache_pressure  # Lower is better (10-50)
```

#### 4. High Memory Usage
```bash
# Reduce cache TTL
./forkspoon ... -cache-ttl 1m

# Clear kernel caches if needed
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
```

#### 5. Stale Data Issues
```bash
# Reduce cache TTL for fresher data
./forkspoon ... -cache-ttl 30s

# Or manually clear cache
fusermount -u /mnt/cache && mount_again
```

### Debug Mode
```bash
# Enable all debugging
./forkspoon \
  -backend /src \
  -mountpoint /dst \
  -verbose \
  -debug \
  -trans-log debug.log

# Analyze debug output
grep ERROR debug.log
grep -C3 "permission denied" debug.log
```

### Log Analysis
```bash
# Find slowest operations
awk -F'|' '{print $2, $4}' transactions.log | sort | uniq -c | sort -rn

# Cache miss patterns
grep CACHE_MISS transactions.log | awk -F'|' '{print $4}' | sort | uniq -c

# Error patterns
grep -E "ERROR|FAIL|errno" debug.log
```

---

## Production Deployment

### systemd Service
Create `/etc/systemd/system/forkspoon.service`:

```ini
[Unit]
Description=Metadata-Caching FUSE Filesystem
After=network.target
Wants=network-online.target

[Service]
Type=forking
User=root
ExecStart=/usr/local/bin/forkspoon \
  -backend /mnt/slow-storage \
  -mountpoint /mnt/fast-cache \
  -cache-ttl 5m \
  -trans-log /var/log/cache-fuse/transactions.log \
  -stats-file /var/log/cache-fuse/stats.json

ExecStop=/usr/bin/fusermount -u /mnt/fast-cache
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable forkspoon
sudo systemctl start forkspoon
```

### Auto-mount with fstab
Add to `/etc/fstab`:
```
forkspoon#/mnt/backend /mnt/cache fuse.forkspoon defaults,cache-ttl=5m,allow_other 0 0
```

### Monitoring with cron
```bash
# Add to crontab
*/5 * * * * /usr/local/bin/check_cache_health.sh

# Health check script
#!/bin/bash
if ! mountpoint -q /mnt/cache; then
    systemctl restart forkspoon
    echo "Cache FS restarted at $(date)" | mail -s "Cache FS Alert" admin@example.com
fi
```

---

## Performance Expectations

### Typical Speedup Factors

| Backend Type | Metadata Speedup | Notes |
|--------------|------------------|--------|
| NFS v3 | 5-10x | High latency operations |
| NFS v4 | 3-7x | Better native caching |
| S3FS | 10-50x | Very high latency |
| SSHFS | 5-15x | Network dependent |
| Local HDD | 1.5-3x | Seek time reduction |

### Resource Usage

| Cache TTL | Memory Usage (per 1M files) | CPU Usage |
|-----------|------------------------------|-----------|
| 1 minute | ~100MB | Low |
| 5 minutes | ~500MB | Very Low |
| 30 minutes | ~1GB | Minimal |

---

## Next Steps

1. **Test in Development**: Start with short cache TTL (30s)
2. **Monitor Performance**: Use transaction logs to understand access patterns
3. **Tune Cache TTL**: Adjust based on your workload
4. **Deploy to Production**: Use systemd service for reliability
5. **Set up Monitoring**: Configure alerts for mount status

---

## Support

- GitHub Issues: https://github.com/yourusername/forkspoon/issues
- Documentation: https://github.com/yourusername/forkspoon/wiki
- Performance Tuning Guide: [TUNING.md](docs/TUNING.md)