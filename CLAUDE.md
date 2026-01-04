# CLAUDE.md - AI Context for Fedora Memory Optimizer v4

This file provides context for AI assistants (Claude, ChatGPT, etc.) to understand the project.

---

## 🎯 Project Summary

**Fedora Memory Optimizer v4.0** - Never-kill memory management for Fedora/RHEL.

### Core Philosophy: Never-Kill

```
v1-v3: Memory pressure → Kill browser → Lose 100 tabs
v4:    Memory pressure → Throttle → Keep all tabs (slower but safe)
```

---

## 📁 Project Structure

```
fedora-memory-optimizer/
├── memory-optimizer-v4.sh      # Main script
├── setup-hibernation-v4.sh     # Hibernate setup
├── uninstall.sh                # Removal
├── README.md
├── CHANGELOG.md
├── CLAUDE.md                   # This file
├── LICENSE
├── docs/
│   ├── FAIL-SAFE.md
│   ├── HIBERNATION.md
│   └── ARCHITECTURE.md
└── config/examples/
    ├── 4gb-ram.conf
    ├── 8gb-ram.conf
    ├── 16gb-ram.conf
    ├── 32gb-ram.conf
    └── 64gb-ram.conf
```

---

## 🔑 Key Concepts

### 1. Never-Kill Mode

```bash
# In v4, earlyoom is DISABLED
# systemd-oomd in passive mode (95% threshold)
# No MemoryMax (only MemoryHigh = throttle only)
```

### 2. Fail-Safe

```
Unknown situation → STOP, don't assume
Confidence levels: HIGH/MEDIUM/LOW/NONE
NONE = no operation, AI-ready report generated
```

### 3. Idempotency

```
2nd run = fast (existing config preserved)
Swapfile exists and adequate = PRESERVED
Resume module exists = dracut SKIPPED
```

---

## 🛠️ Commands

```bash
# Installation
sudo ./memory-optimizer-v4.sh

# Diagnostics (makes no changes)
./memory-optimizer-v4.sh --diagnose

# Fix zram
sudo ./memory-optimizer-v4.sh --fix-zram

# Hibernate
sudo ./setup-hibernation-v4.sh

# Uninstall
sudo ./uninstall.sh
```

---

## ⚙️ RAM Tier System

| RAM | zram | Swapfile | MemoryHigh |
|-----|------|----------|------------|
| 4GB | 2G | 8G | 3G |
| 8GB | 4G | 16G | 6G |
| 16GB | 8G | 32G | 12G |
| 32GB | 16G | 64G | 24G |
| 64GB+ | 32G | 64G | 48G |

The script automatically detects RAM and selects the appropriate tier.

---

## 🔍 Bootloader Detection

```
Evidence collection:
- GRUB: /etc/default/grub, /boot/grub2, grubby
- systemd-boot: /boot/loader/entries, bootctl, /etc/kernel/cmdline
- UKI: /boot/efi/EFI/Linux/*.efi

Confidence calculation:
- HIGH (3+ evidence): Operation proceeds
- MEDIUM (2): Proceeds with warning
- LOW (1 or ambiguous): Asks user
- NONE (0): Operation SKIPPED
```

---

## 📋 AI-Ready Reports

When anomalies occur, a report is created under `/root/memory-optimizer-reports/`.

```
Users can paste this report and ask:
"I ran memory-optimizer script on my Fedora system and anomalies
were detected. Can you analyze the report and provide a custom solution?"
```

---

## ⚠️ Important Notes

1. **Ubuntu/Debian not supported** - WARNING if apt detected
2. **No earlyoom** - v4 has no process kill mechanism
3. **No Firefox tab unloading** - unnecessary (never-kill mode)
4. **Swapfile deletion protected** - won't delete if hibernate configured

---

## 🔧 Information Needed When Requesting Help

```bash
./memory-optimizer-v4.sh --diagnose
cat /root/memory-optimizer-reports/diagnostic-*.txt
cat /proc/cmdline
swapon --show
bootctl status  # if available
```

---

**v4.0.0 - Never-Kill Edition**
