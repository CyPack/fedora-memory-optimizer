# Universal Memory Optimizer

Cross-distribution Linux memory optimizer with ZRAM + Disk Swap.

## Features

- **Universal Compatibility**: Fedora, Debian/Ubuntu, Arch, openSUSE
- **Bootloader Detection**: GRUB, systemd-boot, UKI support
- **Filesystem Aware**: ext4, xfs, btrfs (special handling)
- **Hibernate Protection**: Preserves existing hibernate configuration
- **Rollback System**: Timestamped backups with easy restoration
- **OOM Policies**: Choose between never-kill, passive, or active
- **Dry-Run Mode**: Test before applying changes
- **Verification Script**: Confirm installation after reboot

## Architecture

```
RAM → ZRAM (RAM/2) → Swapfile (ZRAM/2) → OOM Policy
      ↓              ↓                    ↓
      Fast           Emergency            Configurable
      Compressed     Fallback             Response
```

### Size Calculation

| RAM | ZRAM | Swapfile | Effective Capacity |
|-----|------|----------|-------------------|
| 4GB | 2GB | 1GB | ~11GB |
| 8GB | 4GB | 2GB | ~22GB |
| 16GB | 8GB | 4GB | ~44GB |
| 32GB | 16GB | 8GB | ~88GB |
| 64GB | 32GB | 16GB | ~176GB |

## Quick Start

```bash
# Install
sudo ./scripts/memory-optimizer.sh

# Reboot
sudo reboot

# Verify
memory-optimizer-verify
```

## Options

```
--dry-run           Show what would be done
--force             Override hibernate protection
--verbose           Enable debug output
--yes               Skip confirmation prompts
--oom-policy=X      never-kill | passive | active
--rollback PATH     Restore previous configuration
--list-backups      Show available backups
--verify            Run verification checks
```

## OOM Policy Guide

| Policy | Behavior | Best For |
|--------|----------|----------|
| never-kill | System slows but never kills | ML training, databases |
| passive | OOM at 95% (default) | General desktop |
| active | OOM at 80% | Gaming, real-time apps |

## Kernel Parameters

Based on 2025-2026 best practices:

| Parameter | Value | Source |
|-----------|-------|--------|
| vm.swappiness | 180 | ArchWiki, Pop!_OS |
| vm.page-cluster | 0 | ChromeOS, Android |
| vm.vfs_cache_pressure | 50 | Kernel docs |
| vm.watermark_scale_factor | 125 | Fedora testing |

## Requirements

- Linux with systemd
- Root privileges
- zram-generator (auto-installed if missing)

## Files

| Location | Purpose |
|----------|---------|
| `/etc/sysctl.d/99-memory-optimizer.conf` | Kernel parameters |
| `/etc/systemd/zram-generator.conf` | ZRAM configuration |
| `/swapfile` | Disk swap fallback |
| `/usr/local/bin/memory-optimizer-verify` | Verification script |
| `/root/memory-optimizer-backups/` | Configuration backups |

## Rollback

```bash
# List available backups
sudo ./scripts/memory-optimizer.sh --list-backups

# Restore a backup
sudo ./scripts/memory-optimizer.sh --rollback /root/memory-optimizer-backups/backup-20260127-123456

# Reboot
sudo reboot
```

## Sources

- [ArchWiki ZRAM](https://wiki.archlinux.org/title/Zram)
- [Kernel Documentation](https://docs.kernel.org/admin-guide/sysctl/vm.html)
- [Fedora Changes](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)
- [systemd-oomd](https://www.phoronix.com/news/Systemd-Facebook-OOMD)
- [zram-generator](https://github.com/systemd/zram-generator)

## License

MIT
