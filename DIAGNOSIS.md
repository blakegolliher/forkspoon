# Cache Problem Diagnosis

## What Your Test Results Tell Us

### The Problem
Your test shows that caching is **completely not working**:

1. **Uncached NFS** (baseline):
   - First run: 0.31s
   - Second/Third run: 0.04s (NFS has its own caching)

2. **Cached FUSE mount** (should be faster):
   - First run: 0.14s with 643 cache misses
   - Second run: 0.13s with 642 cache misses (should be 0!)
   - Third run: 0.12s with 642 cache misses (should be 0!)

### What This Means
- **Every `ls` triggers ~640 FUSE operations** even on repeated runs
- The kernel is **NOT caching** anything
- Cache timeouts are being **ignored**

## Quick Verification Steps

### Step 1: Ensure Clean Start
```bash
# Kill ALL old forkspoon processes
pkill -9 forkspoon
fusermount -u /tmp/nfs-cached 2>/dev/null

# Verify nothing is running
ps aux | grep forkspoon
```

### Step 2: Start Fresh with New Binary
```bash
# Use the newly built binary (just rebuilt at 3:21 PM)
./forkspoon -backend /mnt/nfs-dest -mountpoint /tmp/nfs-cached -cache-ttl 30s -verbose
```

Look for this in the output:
- "Forkspoon Caching FUSE Filesystem v2.0"
- "Built: 2025-11-13 15:21:55" (or close to this time)

### Step 3: Run Simple Test
```bash
./scripts/simple_cache_test.sh
```

This tests without wildcards to eliminate shell expansion issues.

### Step 4: Check Debug Info
```bash
./scripts/debug_cache.sh
```

## Possible Root Causes

1. **Old Process Still Running**
   - An old forkspoon process might still be mounted
   - Solution: Kill all processes and remount

2. **Binary Not Updated**
   - Still using old binary without cache fixes
   - Solution: Verify build time, use new binary

3. **FUSE Library Issue**
   - The go-fuse library might have a bug
   - Need to verify with strace

4. **Mount Options Not Applied**
   - The options might not be getting to the kernel
   - Check /proc/mounts

## The Critical Code Issue

Looking at the code, the mount options should work:
```go
opts := &fs.Options{
    AttrTimeout:     &cacheTTL,  // Should enable caching
    EntryTimeout:    &cacheTTL,  // Should enable caching
    NegativeTimeout: &cacheTTL,
    ...
}
```

But they're clearly not working. This might be a go-fuse library issue.

## Next Steps

1. **Run the simple test** (no wildcards)
2. **Check if strace shows fewer syscalls** on second run
3. **Verify the process is using new binary**
4. If still not working, we may need to:
   - Use a different FUSE library
   - Explicitly set cache options in mount
   - Debug at the FUSE protocol level