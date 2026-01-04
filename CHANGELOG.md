# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2025-01-04

### 🎯 Philosophy Change: Never-Kill Mode

This release fundamentally changes the approach from "controlled killing" to "never kill, only throttle".

### Core Features

- **Never-Kill Architecture**
  - earlyoom disabled (no browser/app killing)
  - systemd-oomd in passive mode (95% threshold)
  - User session MemoryHigh only (no MemoryMax = no kill)
  - System throttles under pressure, never kills

- **Swap Monitor (Desktop Notifications)**
  - Real-time swap usage monitoring
  - Desktop notifications when thresholds exceeded
  - Top RAM-consuming processes listed
  - User systemd timer (every 30 seconds)
  - Configurable thresholds and cooldown

- **Fail-Safe System**
  - 15+ anomaly types detected
  - Confidence levels: HIGH/MEDIUM/LOW/NONE
  - Unknown situation → STOP, don't assume
  - AI-ready diagnostic reports

- **Idempotent Operations**
  - Safe to run multiple times
  - Swapfile preserved if adequate
  - dracut skipped if resume module exists
  - Kernel params skipped if already correct

- **Bootloader Agnostic**
  - GRUB detection and configuration
  - systemd-boot detection and configuration
  - UKI detection and configuration
  - Unknown → skip with manual instructions

- **Smart RAM Detection**
  - Automatic tier selection (T4/T8/T16/T32/T64)
  - Appropriate zram/swapfile/limit sizing
  - No manual configuration needed for most users

### Scripts

| Script | Purpose |
|--------|---------|
| `memory-optimizer-v4.sh` | Main optimizer (never-kill) |
| `setup-hibernation-v4.sh` | Hibernate setup |
| `swap-monitor.sh` | Desktop notifications for swap usage |
| `uninstall.sh` | Clean removal |

### Config Examples

- `config/examples/4gb-ram.conf` - Low-end systems
- `config/examples/8gb-ram.conf` - Entry-level
- `config/examples/16gb-ram.conf` - Default/recommended
- `config/examples/32gb-ram.conf` - Developer/gaming
- `config/examples/64gb-ram.conf` - Workstation

### Removed

- `install.sh` (v1 - had earlyoom/firefox tab unloading)
- `setup-hibernation.sh` (v1)
- `setup-hibernation-v2.sh` (v2)
- `add-hibernate.sh` (legacy)
- `quick-hibernate-laptop.sh` (legacy)
- Firefox tab unloading (unnecessary with never-kill)
- Browser preference killing (unnecessary with never-kill)

### Documentation

- `README.md` - Complete rewrite for v4
- `docs/FAIL-SAFE.md` - Anomaly detection explained
- `CLAUDE.md` - AI context for assistance
- Config examples updated for v4 format

---

## Why v4?

### Problem with v1-v3 (Kill-based approach)

```
User opens 100 browser tabs
→ Memory pressure increases
→ earlyoom triggers
→ Firefox killed
→ 100 tabs LOST
→ User frustrated
```

### Solution in v4 (Never-kill approach)

```
User opens 100 browser tabs
→ Memory pressure increases  
→ zram absorbs (compressed)
→ Swapfile absorbs (overflow)
→ User session throttled (slower but alive)
→ 0 tabs lost
→ User happy (slightly slower but no data loss)
```

---

## Upgrade Path

If you used v1-v3:

```bash
# 1. Run new installer (safe - preserves swapfile)
sudo ./memory-optimizer-v4.sh

# 2. Disable earlyoom if installed
sudo systemctl disable --now earlyoom

# 3. Reboot
sudo reboot
```

---

## Future

- [ ] Environment variable support for configuration
- [ ] More granular throttle policies
- [ ] Per-application memory policies
- [ ] Integration with systemd scope units
