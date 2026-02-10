# Universal Memory Optimizer
## Cross-Distribution Linux Memory Optimization Template

---

## Purpose

Bu template, Linux sistemlerde memory optimizasyonu yapar:
- **ZRAM:** Compressed RAM-based swap (RAM/2)
- **Disk Swapfile:** Emergency fallback (ZRAM/2)
- **Kernel Tuning:** Best practices sysctl parametreleri

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MEMORY HIERARCHY (Priority Order)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ Tier 1: Physical RAM                                                         │
│         └── Primary working memory (~100ns latency)                          │
│                       ↓ (memory pressure)                                    │
│ Tier 2: ZRAM = RAM/2 (priority 100)                                          │
│         └── Compressed swap in RAM (~1μs latency)                            │
│         └── zstd compression (~5:1 ratio)                                    │
│         └── Example: 32GB RAM → 16GB ZRAM → ~80GB effective                  │
│                       ↓ (ZRAM exhausted)                                     │
│ Tier 3: Disk Swapfile = ZRAM/2 (priority 10)                                 │
│         └── NVMe/SSD fallback (~150μs latency)                               │
│         └── Example: 16GB ZRAM → 8GB Swapfile                                │
│                       ↓ (all swap exhausted)                                 │
│ Tier 4: Kernel OOM (system default)                                          │
│         └── Trusts kernel's built-in OOM killer                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

```bash
# 1. Standard installation
sudo ./scripts/memory-optimizer.sh

# 2. Verify after reboot
memory-optimizer-verify

# 3. If something goes wrong, rollback
sudo ./scripts/memory-optimizer.sh --rollback /root/memory-optimizer-backups/backup-YYYYMMDD-HHMMSS
```

---

## Usage

### Basic Installation
```bash
# Standard installation
sudo ./scripts/memory-optimizer.sh
```

### Dry-Run (Test without changes)
```bash
sudo ./scripts/memory-optimizer.sh --dry-run
```

### Force Mode (Override hibernate protection)
```bash
sudo ./scripts/memory-optimizer.sh --force
```

### Rollback
```bash
# List available backups
sudo ./scripts/memory-optimizer.sh --list-backups

# Rollback to specific backup
sudo ./scripts/memory-optimizer.sh --rollback /path/to/backup
```

---

## Configuration

### RAM Tier Table

| RAM | ZRAM (RAM/2) | Swapfile (ZRAM/2) | Effective Total |
|-----|--------------|-------------------|-----------------|
| 4GB | 2GB | 1GB | ~11GB |
| 8GB | 4GB | 2GB | ~22GB |
| 16GB | 8GB | 4GB | ~44GB |
| 32GB | 16GB | 8GB | ~88GB |
| 64GB | 32GB | 16GB | ~176GB |

*Effective total assumes 5:1 ZRAM compression with zstd*

### Kernel Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| vm.swappiness | 180 | Prefer ZRAM over evicting file cache |
| vm.page-cluster | 0 | Single page reads (optimal for ZRAM) |
| vm.vfs_cache_pressure | 50 | Protect file cache |
| vm.watermark_scale_factor | 125 | Early kswapd activation |

---

## Files Modified

| File | Purpose |
|------|---------|
| `/etc/sysctl.d/99-memory-optimizer.conf` | Kernel parameters |
| `/etc/systemd/zram-generator.conf` | ZRAM configuration |
| `/swapfile` | Disk swap fallback |
| `/etc/fstab` | Swapfile mount entry |

---

## Verification

After reboot:
```bash
# Run verification script
memory-optimizer-verify

# Manual checks
zramctl                           # ZRAM status
swapon --show                     # All swap devices
cat /proc/sys/vm/swappiness       # Should be 180
cat /sys/module/zswap/parameters/enabled  # Should be N or 0
```

---

## Rollback

Automatic backups are created at `/root/memory-optimizer-backups/`

```bash
# List backups
sudo ./scripts/memory-optimizer.sh --list-backups

# Restore
sudo ./scripts/memory-optimizer.sh --rollback /root/memory-optimizer-backups/backup-20260127-123456

# Reboot after rollback
sudo reboot
```

---

## Supported Systems

### Distributions
- Fedora, RHEL, CentOS, Rocky, Alma
- Debian, Ubuntu, Linux Mint, Pop!_OS
- Arch, Manjaro, EndeavourOS
- openSUSE

### Bootloaders
- GRUB (grubby)
- systemd-boot
- UKI (Unified Kernel Image)

### Filesystems
- ext4, xfs (standard swapfile)
- btrfs (special handling with NODATACOW)

---

## Troubleshooting

### ZRAM not active after reboot
```bash
systemctl status systemd-zram-setup@zram0.service
journalctl -u systemd-zram-setup@zram0.service
```

### Swapfile not mounting
```bash
# Check fstab entry
grep swapfile /etc/fstab

# Manual activation
sudo swapon /swapfile
```

### System still using ZSWAP
```bash
# Check runtime status
cat /sys/module/zswap/parameters/enabled

# Check kernel cmdline
cat /proc/cmdline | grep zswap
```

---

## Sources

Best Practices (2025-2026):
- [ArchWiki ZRAM](https://wiki.archlinux.org/title/Zram)
- [Kernel sysctl Documentation](https://docs.kernel.org/admin-guide/sysctl/vm.html)
- [Fedora SwapOnZRAM](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)
- [systemd-oomd](https://www.phoronix.com/news/Systemd-Facebook-OOMD)
- [zram-generator](https://github.com/systemd/zram-generator)
