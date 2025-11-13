# Forkspoon Cache Improvements Summary

## Problem Identified
Your NFS metadata caching FUSE filesystem was not getting any cache hits. Every operation was showing as a cache miss in the logs, even on repeated access to the same files/directories.

## Root Cause
The mount options in `main.go` were explicitly setting `AttrTimeout` and `EntryTimeout` to zero, which completely disabled kernel-level caching. This meant that every metadata operation was being passed through to the underlying NFS mount, defeating the purpose of the cache.

## Fixes Applied

### 1. Fixed Mount Options (main.go:711-721)
- **Before**: Setting `AttrTimeout` and `EntryTimeout` to zero
- **After**: Removed these settings to allow individual operations to control their cache timeouts
- This allows the kernel to cache metadata according to the TTL values set by each operation

### 2. Added Rotating Log System (log_rotation.go)
- Logs cache hits/misses to `/opt/forkspoon/forkspoon.log`
- Automatic rotation when log exceeds 2GB
- Compresses old logs with gzip
- Keeps only 6 old log files
- Thread-safe logging with proper locking

### 3. Enhanced Logging (main.go:58-79)
- Integrated rotating logger with existing transaction logging
- Logs to both rotating cache log and optional transaction log
- Clear timestamps and operation status (CACHE_HIT/CACHE_MISS/PASSTHROUGH)

### 4. Created Testing Scripts

#### compare_cache.sh
- Compares performance between cached mount (`/tmp/nfs-cached`) and uncached mount (`/mnt/nfs-dest`)
- Runs multiple iterations to test cache effectiveness
- Analyzes log file to detect cache hits/misses
- Provides clear visual feedback with color coding

#### diagnose_cache.sh
- Uses strace to detect if FUSE operations are being called
- Helps confirm if kernel caching is working
- Shows mount options and detailed analysis

## How FUSE Caching Actually Works

**Important Understanding**: In FUSE with kernel caching:
- **Cache HIT**: The kernel serves the data without calling our FUSE code at all
- **Cache MISS**: Our FUSE code gets called (what we see in logs)

When caching is working properly:
1. First access: Our code gets called (cache miss) → we set TTL
2. Subsequent accesses within TTL: Kernel serves from cache → our code is NOT called
3. After TTL expires: Our code gets called again (cache miss)

## Testing the Fix

1. **Rebuild the binary**:
   ```bash
   cd /home/vastdata/projects/forkspoon
   go build -o forkspoon cmd/forkspoon/*.go
   ```

2. **Mount with caching enabled**:
   ```bash
   ./forkspoon -backend /mnt/nfs-dest -mountpoint /tmp/nfs-cached -cache-ttl 30s -verbose
   ```

3. **Run the comparison test**:
   ```bash
   ./scripts/compare_cache.sh
   ```

4. **Run the diagnostic**:
   ```bash
   ./scripts/diagnose_cache.sh
   ```

## Expected Behavior After Fix

1. **First `ls` on a directory**: Shows CACHE_MISS in logs, takes normal time
2. **Subsequent `ls` within TTL**: NO new log entries (served from kernel cache), much faster
3. **After TTL expires**: Shows CACHE_MISS again as cache is refreshed

## Performance Expectations

With proper caching:
- Cached operations: ~0.01s or less
- Uncached operations: ~0.1-0.3s (depending on NFS latency)
- Cache hit ratio should be high for repeated operations within TTL

## Monitoring Cache Effectiveness

Check the cache log:
```bash
tail -f /opt/forkspoon/forkspoon.log
```

If you see continuous CACHE_MISS entries for the same paths, the cache is still not working.
If you see no new entries on repeated access, the cache is working (kernel is serving from cache).

## Note on Cache Behavior

The absence of log entries on repeated operations is actually a GOOD sign - it means the kernel cache is serving the requests without calling our FUSE code at all, which is exactly what we want for maximum performance.