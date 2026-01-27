# Universal Memory Optimizer

### *Cross-distribution Linux memory optimization*

> **Intelligent swap management with ZRAM + Disk fallback**
>
> Works on Fedora, Debian/Ubuntu, Arch, openSUSE and more.

Production-grade memory optimization for Linux systems. Combines the best features from multiple optimizers into a single, universal solution.

![Linux](https://img.shields.io/badge/Linux-Universal-blue?logo=linux)
![License](https://img.shields.io/badge/License-MIT-green)
![Shell](https://img.shields.io/badge/Shell-Bash-orange?logo=gnu-bash)
![Version](https://img.shields.io/badge/Version-1.0.0-purple)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MEMORY HIERARCHY                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│ Tier 1: Physical RAM                                                         │
│         └── Primary working memory (~100ns latency)                          │
│                       ↓ (memory pressure)                                    │
│ Tier 2: ZRAM = RAM/2 (priority 100)                                          │
│         └── Compressed swap in RAM (~1μs latency)                            │
│         └── zstd compression (~5:1 ratio)                                    │
│                       ↓ (ZRAM exhausted)                                     │
│ Tier 3: Swapfile = ZRAM/2 (priority 10)                                      │
│         └── NVMe/SSD fallback (~150μs latency)                               │
│                       ↓ (all swap exhausted)                                 │
│ Tier 4: Kernel OOM (system default)                                          │
│         └── Trusts kernel's built-in OOM killer                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Size Calculation

| RAM | ZRAM (RAM/2) | Swapfile (ZRAM/2) | Effective Capacity |
|-----|--------------|-------------------|-------------------|
| 4GB | 2GB | 1GB | ~11GB |
| 8GB | 4GB | 2GB | ~22GB |
| 16GB | 8GB | 4GB | ~44GB |
| 32GB | 16GB | 8GB | ~88GB |
| 64GB | 32GB | 16GB | ~176GB |

*Effective capacity assumes 5:1 ZRAM compression with zstd*

---

## Features

| Feature | Description |
|---------|-------------|
| **Multi-Distribution** | Fedora, RHEL, Debian, Ubuntu, Arch, openSUSE |
| **Multi-Bootloader** | GRUB, systemd-boot, UKI (auto-detection) |
| **Multi-Filesystem** | ext4, xfs, btrfs (NODATACOW handling) |
| **Hibernate Protection** | Auto-detects and preserves hibernate config |
| **Rollback System** | Timestamped backups with easy restoration |
| **Dry-Run Mode** | Test before applying changes |
| **Verification Script** | Post-reboot configuration check |

---

## Quick Start

```bash
# Clone
git clone https://github.com/CyPack/fedora-memory-optimizer.git
cd fedora-memory-optimizer

# Test (dry-run)
sudo ./scripts/memory-optimizer.sh --dry-run

# Install
sudo ./scripts/memory-optimizer.sh

# Reboot
sudo reboot

# Verify
memory-optimizer-verify
```

---

## Usage

### Basic Installation

```bash
# Standard installation
sudo ./scripts/memory-optimizer.sh
```

### Options

```
--dry-run           Show what would be done without changes
--force             Override hibernate protection
--verbose           Enable debug output
--yes               Skip confirmation prompts
--rollback PATH     Restore previous configuration
--list-backups      Show available backups
--verify            Run verification checks
--help              Show help
```

---

## Kernel Parameters

Based on 2025-2026 best practices:

| Parameter | Value | Source |
|-----------|-------|--------|
| vm.swappiness | 180 | [ArchWiki](https://wiki.archlinux.org/title/Zram), Pop!_OS |
| vm.page-cluster | 0 | ChromeOS, Android |
| vm.vfs_cache_pressure | 50 | [Kernel Docs](https://docs.kernel.org/admin-guide/sysctl/vm.html) |
| vm.watermark_scale_factor | 125 | Fedora testing |
| Compression | zstd | 5:1 ratio |

---

## File Structure

```
fedora-memory-optimizer/
├── scripts/
│   └── memory-optimizer.sh    # Main script (1600+ lines)
├── tests/
│   └── test-plan.md           # Test scenarios
├── .claude/
│   └── agents/                # AI agent definitions
├── config.yaml                # Configuration options
├── CLAUDE.md                  # AI instructions
├── README.md                  # This file
├── LICENSE                    # MIT License
├── input/                     # User input files
├── output/                    # Generated output
└── reports/                   # Diagnostic reports
```

---

## Files Modified

| File | Purpose |
|------|---------|
| `/etc/sysctl.d/99-memory-optimizer.conf` | Kernel parameters |
| `/etc/systemd/zram-generator.conf` | ZRAM configuration |
| `/swapfile` | Disk swap fallback |
| `/etc/fstab` | Swapfile mount entry |
| `/usr/local/bin/memory-optimizer-verify` | Verification script |

---

## Rollback

Automatic backups are created at `/root/memory-optimizer-backups/`

```bash
# List available backups
sudo ./scripts/memory-optimizer.sh --list-backups

# Restore a backup
sudo ./scripts/memory-optimizer.sh --rollback /root/memory-optimizer-backups/backup-YYYYMMDD-HHMMSS

# Reboot after rollback
sudo reboot
```

---

## Verification

After reboot:

```bash
# Run verification script
memory-optimizer-verify

# Or manual checks
zramctl                           # ZRAM status
swapon --show                     # All swap devices
cat /proc/sys/vm/swappiness       # Should be 180
cat /sys/module/zswap/parameters/enabled  # Should be N or 0
```

---

## Troubleshooting

### ZRAM Not Active

```bash
systemctl status systemd-zram-setup@zram0.service
journalctl -u systemd-zram-setup@zram0.service
```

### Swapfile Not Mounting

```bash
# Check fstab
grep swapfile /etc/fstab

# Manual activation
sudo swapon /swapfile
```

### Wrong Sysctl Values

```bash
# Reload
sudo sysctl --system

# Check config
cat /etc/sysctl.d/99-memory-optimizer.conf
```

---

## Requirements

- Linux with systemd
- Root privileges
- zram-generator (auto-installed if missing)

### Tested On

| Distribution | Version | Status |
|--------------|---------|--------|
| Fedora | 40-43 | ✅ Tested |
| Ubuntu | 22.04, 24.04 | ✅ Tested |
| Debian | 12 | ✅ Tested |
| Arch | Rolling | ✅ Tested |
| openSUSE | Tumbleweed | ✅ Tested |

---

## Sources

- [ArchWiki ZRAM](https://wiki.archlinux.org/title/Zram)
- [Kernel sysctl Documentation](https://docs.kernel.org/admin-guide/sysctl/vm.html)
- [Fedora SwapOnZRAM](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)
- [zram-generator](https://github.com/systemd/zram-generator)
- [systemd-oomd](https://www.phoronix.com/news/Systemd-Facebook-OOMD)

---

## License

MIT License - [LICENSE](LICENSE)

---

**Made for Linux users who want intelligent memory management**
