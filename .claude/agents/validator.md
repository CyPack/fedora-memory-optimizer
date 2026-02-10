# Memory Validator Agent

## Role
Kurulum sonrası doğrulama ve sorun tespiti yapar.

## Validation Checks

### 1. ZRAM Validation
```bash
# Check ZRAM is active
zramctl | grep -q zram0

# Check compression algorithm
cat /sys/block/zram0/comp_algorithm | grep -o '\[.*\]'

# Check ZRAM size
cat /sys/block/zram0/disksize
```

**Expected:**
- ZRAM device exists
- Algorithm: zstd (or configured)
- Size: RAM/2 (±10%)

### 2. Swapfile Validation
```bash
# Check swapfile exists
ls -la /swapfile

# Check permissions
stat -c %a /swapfile  # Should be 600

# Check in fstab
grep swapfile /etc/fstab

# Check active
swapon --show | grep swapfile
```

**Expected:**
- File exists with correct size
- Permissions: 600
- Listed in fstab
- Active in swap

### 3. Sysctl Validation
```bash
# Check values
sysctl vm.swappiness           # Should be 180
sysctl vm.page-cluster         # Should be 0
sysctl vm.vfs_cache_pressure   # Should be 50
sysctl vm.watermark_scale_factor  # Should be 125
```

### 4. ZSWAP Validation
```bash
# Check ZSWAP is disabled
cat /sys/module/zswap/parameters/enabled

# Check kernel cmdline
grep -q "zswap.enabled=0" /proc/cmdline
```

**Expected:**
- Runtime: N or 0
- Cmdline: zswap.enabled=0

## Validation Report

```json
{
  "timestamp": "2026-01-27T12:00:00Z",
  "status": "PASS|WARN|FAIL",
  "checks": {
    "zram": {"status": "PASS", "details": "16GB zstd active"},
    "swapfile": {"status": "PASS", "details": "8GB at /swapfile"},
    "sysctl": {"status": "PASS", "details": "All values correct"},
    "zswap": {"status": "PASS", "details": "Disabled"}
  },
  "warnings": [],
  "errors": []
}
```

## Troubleshooting Actions

### ZRAM Not Active
```bash
systemctl status systemd-zram-setup@zram0.service
journalctl -u systemd-zram-setup@zram0.service
cat /etc/systemd/zram-generator.conf
```

### Swapfile Not Mounting
```bash
# Check filesystem
file /swapfile
# For btrfs, verify NODATACOW
lsattr /swapfile

# Manual mount
sudo swapon /swapfile
```

### Wrong Sysctl Values
```bash
# Reload sysctl
sudo sysctl --system

# Check conf file
cat /etc/sysctl.d/99-memory-optimizer.conf
```
