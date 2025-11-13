# Forkspoon Testing Instructions

## What Was Fixed

### 1. **Mount Options (CRITICAL FIX)**
   - **Before**: Cache timeouts were being overridden to zero
   - **After**: Properly set `AttrTimeout`, `EntryTimeout`, and `NegativeTimeout` to enable kernel caching
   - Location: `main.go:735-741`

### 2. **Logging System**
   - Added automatic log rotation at 2GB
   - Falls back to `$HOME/forkspoon.log` if `/opt/forkspoon/` isn't writable
   - Simplified logging to only show cache misses (hits are implicit)

### 3. **Monitoring Tools**
   - `cache_monitor.sh` - Real-time cache effectiveness monitor
   - `compare_cache.sh` - Performance comparison tool
   - `diagnose_cache.sh` - Low-level cache diagnostic

## How to Test

### Step 1: Stop Any Running Instance
```bash
# If forkspoon is running, unmount it
fusermount -u /tmp/nfs-cached
# Or kill the process
pkill forkspoon
```

### Step 2: Start Fresh with New Binary
```bash
# Make sure you're using the newly built binary
./forkspoon -backend /mnt/nfs-dest -mountpoint /tmp/nfs-cached -cache-ttl 30s -verbose
```

Look for the log location message:
- It will either use `/opt/forkspoon/forkspoon.log`
- Or fall back to `~/forkspoon.log`

### Step 3: Monitor Cache in Real-Time
In a new terminal:
```bash
./scripts/cache_monitor.sh
```

This shows:
- Operations per second (lower is better - means cache is working)
- Cache effectiveness status
- Recent operations

### Step 4: Run Performance Test
In another terminal:
```bash
./scripts/compare_cache.sh
```

## Understanding Cache Behavior

### What "Cache Hit" Really Means in FUSE

**IMPORTANT**: With kernel-level caching in FUSE:
- **Cache HIT** = Kernel serves data, our code is NOT called, NO log entry
- **Cache MISS** = Kernel calls our code, we see a log entry

### Expected Behavior

1. **First `ls` on a directory**:
   - Monitor shows: Many operations (cache misses)
   - Time: ~0.12-0.14s
   - Log: Many CACHE_MISS entries

2. **Second `ls` within 30 seconds**:
   - Monitor shows: ZERO or very few operations
   - Time: Should be much faster (~0.01s)
   - Log: No new entries (THIS IS GOOD!)

3. **After 30 seconds (cache expired)**:
   - Operations appear again in log
   - Cache is refreshed

### How to Verify Cache is Working

Run this simple test:
```bash
# Terminal 1: Watch the log
tail -f ~/forkspoon.log  # or /opt/forkspoon/forkspoon.log

# Terminal 2: Run ls twice
time ls -la /tmp/nfs-cached/r0/d5/* | wc -l
sleep 2
time ls -la /tmp/nfs-cached/r0/d5/* | wc -l
```

**If cache is working**:
- First ls: Log shows many CACHE_MISS entries
- Second ls: Log shows NO new entries (or very few)
- Second ls is much faster than first

**If cache is NOT working**:
- Both ls commands show same number of log entries
- Both take similar time

## Troubleshooting

### Log File Not Created
```bash
# Check where it's trying to write
ls -la /opt/forkspoon/
ls -la ~/forkspoon.log

# Create /opt/forkspoon if needed (as root)
sudo mkdir -p /opt/forkspoon
sudo chown $USER:$USER /opt/forkspoon
```

### Still Seeing Cache Misses
1. Make sure you rebuilt the binary:
   ```bash
   go build -o forkspoon cmd/forkspoon/*.go
   ```

2. Verify mount options:
   ```bash
   mount | grep forkspoon
   cat /proc/mounts | grep nfs-cached
   ```

3. Check cache TTL is being set:
   - Look for "Cache TTL: 30s" in forkspoon startup messages

### Performance Not Improving
Use strace to verify kernel caching:
```bash
./scripts/diagnose_cache.sh
```

This will show if FUSE operations are being called on repeated access.

## Success Criteria

You know caching is working when:
1. ✅ Second `ls` is 10x+ faster than first
2. ✅ Log shows no new entries on repeated operations
3. ✅ `cache_monitor.sh` shows "EXCELLENT" or "GOOD" status
4. ✅ `diagnose_cache.sh` shows fewer/no FUSE operations on second run

## Performance Expectations

With working cache:
- Initial access: ~100-300ms (depending on NFS)
- Cached access: ~10-30ms
- Cache hit rate: >90% for repeated operations within TTL