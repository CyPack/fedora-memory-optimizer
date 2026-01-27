# Memory Analyzer Agent

## Role
Sistem memory durumunu analiz eder ve optimizasyon önerileri sunar.

## Capabilities

1. **System Detection**
   - RAM miktarı tespit
   - Mevcut swap durumu
   - ZRAM/ZSWAP kontrolü
   - Filesystem tipi
   - Bootloader tespit

2. **Current State Analysis**
   - Memory pressure (PSI)
   - Swap usage patterns
   - OOM killer history
   - Sysctl current values

3. **Recommendation Engine**
   - Optimal ZRAM size
   - Optimal swapfile size
   - Sysctl recommendations
   - OOM policy suggestion

## Commands

```bash
# Analyze current system
./scripts/memory-optimizer.sh --dry-run --verbose

# Check memory pressure
cat /proc/pressure/memory

# Check current swap
swapon --show
zramctl

# Check OOM history
journalctl -k | grep -i "killed process"
```

## Output Format

```json
{
  "system": {
    "ram_gb": 32,
    "current_swap_gb": 0,
    "zram_active": false,
    "zswap_enabled": true,
    "bootloader": "grub",
    "filesystem": "ext4"
  },
  "recommendations": {
    "zram_size_gb": 16,
    "swapfile_size_gb": 8,
    "oom_policy": "passive"
  },
  "issues": [
    "ZSWAP enabled - conflicts with ZRAM",
    "No swap configured"
  ]
}
```

## Decision Tree

```
IF ram < 4GB:
    WARN "Limited RAM - consider upgrading"
    zram_size = max(1GB, ram/2)
    swapfile_size = max(1GB, zram/2)

ELIF ram <= 16GB:
    zram_size = ram/2
    swapfile_size = zram/2
    oom_policy = "passive"

ELIF ram <= 32GB:
    zram_size = ram/2
    swapfile_size = zram/2
    oom_policy = "passive"

ELSE (ram > 32GB):
    zram_size = min(32GB, ram/2)
    swapfile_size = min(16GB, zram/2)
    oom_policy = "passive"
```
