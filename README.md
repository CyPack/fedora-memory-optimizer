# 🚀 Fedora Memory Optimizer v4.0

### *"macOS-like memory management for Linux"*

> **No more OOM kills. No more frozen systems. No more lost work.**
>
> While other systems kill your apps when memory runs low, we keep them alive with intelligent compression and graceful throttling.

Production-grade memory optimization for Fedora/RHEL systems. Prevents OOM kills and system freezes using a **never-kill** approach with intelligent hibernate support.

![Fedora](https://img.shields.io/badge/Fedora-40--50+-blue?logo=fedora)
![License](https://img.shields.io/badge/License-MIT-green)
![Shell](https://img.shields.io/badge/Shell-Bash-orange?logo=gnu-bash)
![Version](https://img.shields.io/badge/Version-4.0.0-purple)

---

## 🧠 NEVER-KILL PHILOSOPHY

This optimizer **never kills processes**. Instead:

```
## 💡 Why This Exists

| Scenario | ❌ Default Linux | ✅ With This Script |
|----------|------------------|---------------------|
| RAM full while coding | VS Code killed, unsaved work **GONE** | VS Code slows down, you save & close |
| 50 browser tabs | Random tabs killed | Tabs compressed, system stays responsive |
| Large compilation | Build killed mid-process | Build slows, completes successfully |
| Gaming + streaming | Game crashes | Frame drops, but game survives |

**We turned Linux memory management from "survival of the fittest" into "everyone survives, some just walk slower."**

When Memory Pressure Increases →
┌─────────────────────────────────────────────────────────────────┐
│ 1. zram swap activates (compressed RAM)                         │
│ 2. Overflow to swapfile (NVMe/SSD)                              │
│ 3. User session gets throttled (slower but alive)               │
│ 4. System remains responsive                                     │
│                                                                 │
│ ❌ No processes killed                                           │
│ ❌ earlyoom DISABLED                                             │
│ ❌ OOM killer never triggered                                    │
└─────────────────────────────────────────────────────────────────┘
```

### Why Never-Kill?

| Approach | Problem |
|----------|---------|
| earlyoom | Kills browser → 100 tabs lost |
| systemd-oomd | Kills applications → Unsaved work lost |
| Kernel OOM | Kills random processes → System may become unstable |
| **Never-Kill** | ✅ Nothing lost, just slower |

---

## 🛡️ FAIL-SAFE ARCHITECTURE

This script **makes no assumptions**. When encountering unknown situations:

| Situation | ❌ Other Scripts | ✅ This Script |
|-----------|------------------|----------------|
| Bootloader not detected | "Probably GRUB" → write anyway | **STOPS**, reports anomaly |
| /boot space insufficient | `dracut --regenerate-all` | **STOPS**, suggests cleanup |
| Ambiguous config | Makes assumptions | **ASKS THE USER** |
| Error occurred | Says "Failed", continues | Produces **AI-ready report** |

---

## 📊 SUPPORTED SYSTEMS

### RAM Support

| RAM | zram | Swapfile | User Limit | Total Swap* |
|-----|------|----------|------------|-------------|
| **4GB** | 2GB | 8GB | 3GB | ~16GB |
| **8GB** | 4GB | 16GB | 6GB | ~32GB |
| **16GB** | 8GB | 32GB | 12GB | ~64GB |
| **32GB** | 16GB | 64GB | 24GB | ~128GB |
| **64GB+** | 32GB | 64GB | 48GB | ~192GB |

*Effective capacity with zram 4x compression

### Fedora Versions

| Version | Status | Notes |
|---------|--------|-------|
| Fedora 40-42 | ✅ **Fully Tested** | All features |
| Fedora 43-50 | ✅ Supported | Auto-detection |
| Fedora 50+ | ⚠️ Warning shown | AI report recommended |

### Bootloader Support

| Bootloader | Detection | Kernel Param |
|------------|-----------|--------------|
| **GRUB** | ✅ grubby + config | ✅ grubby --update-kernel |
| **systemd-boot** | ✅ bootctl + entries | ✅ /etc/kernel/cmdline |
| **UKI** | ✅ EFI/Linux/*.efi | ✅ cmdline + rebuild |
| **Unknown** | ⚠️ Anomaly | ❌ Skip + manual instructions |

---

## 🛠️ INSTALLATION

### Quick Install

```bash
git clone https://github.com/CyPack/fedora-memory-optimizer.git
cd fedora-memory-optimizer

# Memory Optimizer
sudo ./memory-optimizer-v4.sh

# Hibernate Support (optional)
sudo ./setup-hibernation-v4.sh
```

### Pre-Installation Diagnostics

```bash
# Check system (no root required, makes no changes)
./memory-optimizer-v4.sh --diagnose
./setup-hibernation-v4.sh --diagnose
```

### Post-Installation

```bash
# REBOOT REQUIRED
sudo reboot

# Verification
zramctl                    # Is zram active?
swapon --show              # Are swaps active?
cat /proc/sys/vm/swappiness  # Should be 180
```

---

## 🔄 IDEMPOTENCY (Safe Re-runs)

The script **can be safely run multiple times**:

| Component | On 2nd Run |
|-----------|------------|
| Swapfile | ✅ PRESERVED if exists and adequate |
| zram config | ✅ SKIPPED if same |
| dracut/initramfs | ✅ SKIPPED if resume module exists |
| Kernel params | ✅ SKIPPED if already correct |

```
First run:  ~3-5 minutes (swapfile creation)
Second run: ~1 second (everything skipped)
```

---

## ⚙️ CONFIGURATION

### Automatic RAM Detection

The script automatically detects RAM amount and selects the appropriate tier:

```bash
# On a 32GB RAM system:
[INFO] RAM: 32GB → Tier T32
[INFO] zram: 16G, swapfile: 64G, user_limit: 24G
```

### Manual Configuration

RAM tier examples are available under `config/examples/`:

```bash
cat config/examples/16gb-ram.conf

# Modify values in the script:
nano memory-optimizer-v4.sh
# Update ZRAM_SIZE, SWAPFILE_SIZE, USER_MEMORY_HIGH values
```

---

## 📦 FILE STRUCTURE

```
fedora-memory-optimizer/
├── memory-optimizer-v4.sh      # Main script
├── setup-hibernation-v4.sh     # Hibernate setup
├── uninstall.sh                # Removal
├── README.md
├── CHANGELOG.md
├── CLAUDE.md                   # AI context
├── LICENSE
├── docs/
│   ├── FAIL-SAFE.md            # Fail-safe details
│   ├── HIBERNATION.md          # Hibernate guide
│   └── ARCHITECTURE.md         # Technical architecture
└── config/
    └── examples/
        ├── 4gb-ram.conf
        ├── 8gb-ram.conf
        ├── 16gb-ram.conf
        ├── 32gb-ram.conf
        └── 64gb-ram.conf
```

---

## 🔍 ANOMALY DETECTION

The script automatically detects issues:

```
BOOTLOADER_CONFIDENCE = HIGH | MEDIUM | LOW | NONE

HIGH   → ✅ Operation proceeds
MEDIUM → ⚠️ Warning issued
LOW    → ⚠️ User is asked
NONE   → ❌ Operation SKIPPED, report generated
```

### AI-Ready Reports

When issues occur, a report is created under `/root/memory-optimizer-reports/`:

```
Send this report to your AI assistant (Claude, ChatGPT):

"I ran memory-optimizer on my Fedora system and anomalies
were detected. Can you analyze the report and provide
a custom solution?"

[PASTE REPORT]
```

---

## 📊 WHAT GETS INSTALLED?

| File | Purpose |
|------|---------|
| `/etc/sysctl.d/99-memory-optimizer.conf` | Kernel params (swappiness=180) |
| `/etc/systemd/zram-generator.conf` | zram config |
| `/etc/systemd/system/user-.slice.d/50-memory-limit.conf` | User throttle (no kill) |
| `/etc/systemd/oomd.conf.d/99-passive-nokill.conf` | oomd passive mode |
| `/swapfile` | Overflow swap |

---

## 🔧 TROUBLESHOOTING

### zram Not Active

```bash
# Diagnostics
./memory-optimizer-v4.sh --diagnose

# Fix
sudo ./memory-optimizer-v4.sh --fix-zram

# Manual check
zramctl
swapon --show
```

### Hibernate Not Working

```bash
# Diagnostics
./setup-hibernation-v4.sh --diagnose

# Checks
cat /proc/cmdline | tr ' ' '\n' | grep resume
sudo lsinitrd /boot/initramfs-$(uname -r).img | grep resume
```

---

## 🔔 SWAP MONITOR (Desktop Notifications)

Optional tool - receive desktop notifications when swap usage increases:

```bash
# Install (as user service)
./swap-monitor.sh --install

# Current status
./swap-monitor.sh --status

# Test notification
./swap-monitor.sh --test

# Uninstall
./swap-monitor.sh --uninstall
```

### Notification Examples

**When swap exceeds 50%:**
```
💾 Swap Usage: 52%

System has started swapping.
RAM: 14.2 / 16.0 GB (89%)
Swap: 8.3 / 16.0 GB
zram: 5.1 / 8.0 GB (64%)

Top RAM consumers:
  • firefox: 2048 MB (12.8%)
  • code: 1536 MB (9.6%)
  • docker: 1024 MB (6.4%)

ℹ️ Performance may decrease
```

**When swap exceeds 80% (CRITICAL):**
```
⚠️ Swap Critical: 82%

Swap nearly full! Remaining: 18%

Recommendations:
• Close unused applications
• Reduce browser tab count
• System may slow down
```

### Thresholds

| Threshold | Value | Notification |
|-----------|-------|--------------|
| Swap Warning | 50% | Normal (yellow) |
| Swap Critical | 80% | Critical (red) |
| zram Warning | 70% | Low (blue) |
| Cooldown | 5 minutes | Same warning won't repeat |

---

## 🗑️ UNINSTALL & RESTORE

```bash
# Show installed components
sudo ./uninstall.sh --status

# List existing backups
sudo ./uninstall.sh --list

# Uninstall (saves to backup)
sudo ./uninstall.sh

# Restore from backup
sudo ./uninstall.sh --restore

sudo reboot
```

### Backup Locations

| Source | Backup Directory |
|--------|------------------|
| memory-optimizer-v4.sh | `/root/memory-backup-TIMESTAMP/` |
| setup-hibernation-v4.sh | `/root/hibernate-backup-TIMESTAMP/` |
| uninstall.sh | `/root/memory-optimizer-uninstall-backup-TIMESTAMP/` |

### How Restore Works

```
sudo ./uninstall.sh --restore

RESTORE - Restore from Backup

  [1] /root/memory-backup-20250104-194501
      Files: 99-memory-optimizer.conf, zram-generator.conf, fstab

  [2] /root/hibernate-backup-20250104-195032
      Files: fstab, grub, dracut.conf.d

Which backup do you want to restore? (1-2): 1

✓ Kernel params: restored
✓ zram config: restored
ℹ️ User limits: already same (skipped)  ← IDEMPOTENCY

RESTORE COMPLETED
  Files restored: 2
```

---

## 📊 STRESS TEST

```bash
# Install stress-ng
sudo dnf install stress-ng

# Test (16GB RAM example)
stress-ng --vm 4 --vm-bytes 8G --timeout 60s

# Expected: System slows down but no process dies
```

---

## 🆕 v4.0 Features

- **Never-Kill Mode**: earlyoom disabled, throttle only
- **Fail-Safe Architecture**: Makes no assumptions, produces reports
- **AI-Ready Reports**: Copy-paste to Claude/ChatGPT
- **Bootloader Agnostic**: GRUB, systemd-boot, UKI
- **Idempotent**: Safe to run multiple times
- **Fedora 40-50+ Support**: Future-version ready

---

## 📜 License

MIT License - [LICENSE](LICENSE)

---

**Made with 💪 for Fedora users who hate losing their work to OOM kills**
