# Performance Tuning Guide

## Cache TTL Optimization

### Finding Optimal TTL

1. **Monitor Access Patterns**
```bash
# Analyze transaction log for patterns
awk -F'|' '{print $4}' /var/log/cache-fuse/transactions.log | \
  sort | uniq -c | sort -rn | head -20
```

2. **Measure Cache Hit Rate**
```bash
# Check current hit rate
cat /var/log/cache-fuse/stats.json | \
  jq '.cached_operations | .[] | .hit_rate'
```

3. **TTL Guidelines by Hit Rate**

| Current Hit Rate | Action |
|-----------------|---------|
| < 50% | Increase TTL by 2x |
| 50-80% | Increase TTL by 50% |
| 80-95% | Keep current TTL |
| > 95% | Consider reducing if staleness is an issue |

## Kernel Tuning

### VFS Cache Pressure
```bash
# Reduce cache pressure (keep cache longer)
echo 50 | sudo tee /proc/sys/vm/vfs_cache_pressure

# Default is 100, lower values favor caching
# 50 = Moderate caching
# 10 = Aggressive caching
```

### Inode Cache
```bash
# Increase inode cache size
echo 2 | sudo tee /proc/sys/vm/drop_caches  # Clear first
echo 75 | sudo tee /proc/sys/vm/vfs_cache_pressure
```

### Directory Entry Cache
```bash
# Monitor dcache usage
slabtop -o | grep dentry

# Increase dcache if needed
echo 1000000 | sudo tee /proc/sys/fs/dentry-max
```

## Memory Management

### Calculate Memory Usage
```
Memory per cached entry ≈ 1KB
Memory usage = (number_of_files + number_of_dirs) * 1KB * cache_copies

Example: 100,000 files = ~100MB cache memory
```

### Memory Limits
```bash
# Limit FUSE process memory (systemd)
LimitAS=2G
LimitRSS=1G
```

## Network Optimization

### For NFS Backends
```bash
# Mount NFS with optimal settings
mount -t nfs -o rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  server:/path /mnt/nfs

# Then add caching layer
forkspoon -backend /mnt/nfs -mountpoint /mnt/cached -cache-ttl 10m
```

### For S3FS/Cloud Storage
```bash
# Longer TTL for high-latency backends
forkspoon -backend /mnt/s3 -mountpoint /mnt/cached -cache-ttl 30m
```

## Monitoring Performance

### Real-time Metrics
```bash
#!/bin/bash
# monitor.sh - Real-time cache performance

while true; do
    clear
    echo "=== Cache Performance ==="

    # Operations per second
    echo -n "Ops/sec: "
    tail -1000 /var/log/cache-fuse/transactions.log | \
      grep "$(date +%H:%M)" | wc -l

    # Cache hit rate
    echo -n "Hit Rate: "
    cat /var/log/cache-fuse/stats.json | \
      jq -r '.cached_operations.getattr.hit_rate'

    # Memory usage
    echo -n "Memory: "
    ps aux | grep cache-fuse | awk '{print $6/1024 "MB"}'

    sleep 1
done
```

### Grafana Dashboard Queries

```promql
# Cache hit rate
rate(cache_fuse_hits_total[5m]) /
  (rate(cache_fuse_hits_total[5m]) + rate(cache_fuse_misses_total[5m]))

# Operations per second
rate(cache_fuse_operations_total[1m])

# Latency percentiles
histogram_quantile(0.99, cache_fuse_operation_duration_seconds)
```

## Benchmarking

### Standard Benchmark
```bash
#!/bin/bash
# benchmark.sh

MOUNT="/mnt/cached"

echo "Metadata Performance Test"

# Find operation
time find $MOUNT -type f | wc -l

# Stat operation
time find $MOUNT -exec stat {} \; > /dev/null

# Directory listing
time ls -laR $MOUNT > /dev/null

# Random access
for i in {1..1000}; do
    stat "$MOUNT/random/file$RANDOM.txt" 2>/dev/null
done
```

### Comparison Script
```bash
#!/bin/bash
compare_performance() {
    local direct=$1
    local cached=$2

    echo "Testing: find operation"
    echo -n "Direct: "
    time find $direct -type f | wc -l

    echo -n "Cached: "
    time find $cached -type f | wc -l
}
```

## Troubleshooting Performance

### High CPU Usage
- Reduce debug/verbose logging
- Increase cache TTL
- Check for cache thrashing

### High Memory Usage
- Reduce cache TTL
- Limit cache size (kernel tuning)
- Monitor for memory leaks

### Low Hit Rate
- Increase cache TTL
- Check access patterns
- Verify cache is working

### Slow Performance
- Check backend latency
- Verify cache is enabled
- Monitor system resources

## Best Practices

1. **Start Conservative**: Begin with 1-minute TTL, increase gradually
2. **Monitor Continuously**: Use transaction logs to understand patterns
3. **Test Thoroughly**: Benchmark before and after changes
4. **Document Changes**: Keep notes on what works for your workload
5. **Regular Review**: Re-evaluate settings as usage patterns change