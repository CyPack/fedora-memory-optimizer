# 💤 Hibernate (Suspend-to-Disk) Guide

> **What is Hibernate?** Saving all RAM contents (open applications, documents, browser tabs)
> to disk and completely powering off the system. On startup, you continue exactly where you left off.

---

## 🎯 Hibernate vs Suspend vs Shutdown

| Feature | Shutdown | Suspend (Sleep) | Hibernate |
|---------|----------|-----------------|-----------|
| Power consumption | 0 | Low (~2-5W) | 0 |
| Startup time | 30-60 seconds | 1-2 seconds | 10-20 seconds |
| Session preserved | ❌ | ✅ | ✅ |
| Battery risk | None | Data loss if battery dies | None |
| Disk space | Not required | Not required | RAM amount |

### When to Use Hibernate?

- ✅ When putting laptop in bag (session preserved even if battery dies)
- ✅ When shutting down at night (continue where you left off in the morning)
- ✅ When many applications/tabs are open
- ✅ When power saving is critical
- ❌ Just for a 5-minute break (suspend is faster)

---

## 🛠️ Installation

### Automatic Installation

```bash
# Run the script
sudo ./setup-hibernation.sh

# Reboot
sudo reboot

# Test
sudo systemctl hibernate
```

### Manual Installation (Advanced)

<details>
<summary>Show manual steps</summary>

#### 1. Create Swapfile (btrfs)

```bash
# Create swap subvolume
sudo btrfs subvolume create /var/swap

# Create swapfile (1.5x RAM size)
sudo btrfs filesystem mkswapfile --size 24G --uuid clear /var/swap/swapfile

# Add to fstab
echo "/var/swap/swapfile none swap defaults,pri=10 0 0" | sudo tee -a /etc/fstab

# Activate
sudo swapon -a
```

#### 2. Calculate Resume Offset

```bash
# Find UUID
ROOT_UUID=$(findmnt -no UUID /)

# Find offset (btrfs)
OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /var/swap/swapfile)

echo "UUID: $ROOT_UUID"
echo "Offset: $OFFSET"
```

#### 3. Set Kernel Parameters

```bash
sudo grubby --update-kernel=ALL --args="resume=UUID=$ROOT_UUID resume_offset=$OFFSET"
```

#### 4. Configure Dracut

```bash
echo 'add_dracutmodules+=" resume "' | sudo tee /etc/dracut.conf.d/99-hibernate.conf
sudo dracut --force --regenerate-all
```

#### 5. Reboot and Test

```bash
sudo reboot
# Then:
sudo systemctl hibernate
```

</details>

---

## 📊 Swap Size Calculation

Swap size is critical for hibernate. If insufficient, hibernate will fail.

### Formula

```
Swap Size = RAM + (zram × 2)
```

### Recommended Sizes

| RAM | zram | Hibernate Swap | Total Swap |
|-----|------|----------------|------------|
| 4GB | 2GB | 8GB | 10GB |
| 8GB | 4GB | 16GB | 20GB |
| 16GB | 8GB | 24-32GB | 32-40GB |
| 32GB | 12GB | 32-48GB | 44-60GB |

### Why So Large?

1. **RAM**: All RAM contents will be written
2. **zram**: Compressed data expands when written (×2)
3. **Safety margin**: Full RAM + overhead

---

## ⚙️ Configuration Options

### Lid Close = Hibernate (Laptop)

Edit `/etc/systemd/logind.conf`:

```ini
[Login]
# Hibernate when lid closed
HandleLidSwitch=hibernate

# Suspend when on AC power (optional)
HandleLidSwitchExternalPower=suspend

# Do nothing when docked
HandleLidSwitchDocked=ignore
```

Apply changes:
```bash
sudo systemctl restart systemd-logind
```

### Idle Timeout = Hibernate

```ini
[Login]
# Hibernate after 30 minutes idle
IdleAction=hibernate
IdleActionSec=30min
```

### Hybrid Sleep (Recommended - Laptop)

Suspend first, auto-hibernate if battery becomes critical:

```bash
sudo systemctl hybrid-sleep
```

---

## 🖥️ Desktop Integration

### GNOME

Hibernate is not in the power menu by default. Solutions:

1. **Extension**: Install "Hibernate Status Button"
   - https://extensions.gnome.org/extension/755/hibernate-status-button/

2. **Command line**: `systemctl hibernate`

3. **Keyboard shortcut**: Settings > Keyboard > Custom Shortcuts
   - Command: `systemctl hibernate`

### KDE Plasma

System Settings > Power Management > Button Events Handling:
- "When laptop lid closed": Hibernate

### XFCE / MATE

Hibernate can be selected from Power Manager settings.

---

## 🔧 Troubleshooting

### "Hibernate" option not visible

```bash
# Check if hibernate is supported
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager CanHibernate

# Should return "yes". If "na" or "no":
cat /sys/power/state
# Should contain "disk"
```

### Hibernate starts but doesn't resume

```bash
# Check kernel parameters
cat /proc/cmdline | grep resume

# Expected: resume=UUID=xxx resume_offset=yyy
# If missing, repeat dracut and grubby steps
```

### Black screen during resume

```bash
# May be GPU driver issue
# For NVIDIA:
sudo nano /etc/modprobe.d/nvidia-power-management.conf
```

```
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
```

```bash
sudo systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume
sudo dracut --force
```

### "Not enough swap space" error

```bash
# Check current swap size
swapon --show

# Enlarge swap file
sudo swapoff /var/swap/swapfile
sudo btrfs filesystem mkswapfile --size 48G --uuid clear /var/swap/swapfile
sudo swapon /var/swap/swapfile

# Offset changes! Recalculate
OFFSET=$(sudo btrfs inspect-internal map-swapfile -r /var/swap/swapfile)
sudo grubby --update-kernel=ALL --args="resume_offset=$OFFSET"
```

### Not working with Secure Boot (Fedora 40-)

```bash
# Secure Boot + Hibernate problematic on Fedora 40 and earlier
# Options:
# 1. Upgrade to Fedora 41+
# 2. Disable Secure Boot (in BIOS)
# 3. Use swap partition (instead of swapfile)
```

---

## 🔒 Security Notes

### Encryption (LUKS)

Hibernate is secure if swap is on encrypted partition. If swapfile is on root partition and root is encrypted, it's also secure.

### RAM Contents on Disk

During hibernate, all RAM is written to disk. This may include:
- Passwords (remaining in memory)
- Encryption keys
- Open documents

**Recommendation**: Use disk encryption (LUKS).

---

## 📈 Performance Tips

### Speed Up Hibernate

```bash
# Reduce image_size (less data to write)
echo 0 > /sys/power/image_size

# Or permanently:
echo 'w /sys/power/image_size - - - - 0' | sudo tee /etc/tmpfiles.d/hibernate-image-size.conf
```

### SSD/NVMe Optimization

Already fast, no additional settings needed. For 16GB RAM:
- Write: 3-8 seconds
- Resume: 5-15 seconds

### HDD Systems

Hibernate is slower (30-60 seconds). But safer than suspend.

---

## 🔄 Using with zram

**Important**: zram and hibernate can work together, but:

1. Compressed data in zram is also hibernated
2. Swap size should be: RAM + (zram × 2)
3. Hibernate swap should have lower priority than zram (pri=10)

```
Normal usage:
RAM → zram (compressed, fast)

Hibernate:
RAM + zram contents → Disk swap (slower but persistent)
```

---

## 📋 Checklist

### Post-Installation

```
[ ] Reboot completed
[ ] cat /proc/cmdline | grep resume - parameters present
[ ] swapon --show - hibernate swap active
[ ] busctl ... CanHibernate - returns "yes"
[ ] sudo systemctl hibernate - test successful
[ ] All applications open after resume
```

### If Issues Occur

```
[ ] journalctl -b -1 | grep -i hibernate
[ ] journalctl -b -1 | grep -i resume
[ ] dmesg | grep -i swap
[ ] lsinitrd | grep resume
```

---

## 🔗 References

- [Fedora Magazine: Hibernation](https://fedoramagazine.org/hibernation-in-fedora-36-workstation/)
- [Arch Wiki: Suspend and Hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
- [BTRFS Swapfile Docs](https://btrfs.readthedocs.io/en/latest/Swapfile.html)
- [Kernel Power Management](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)

---

*Last updated: 2026-01-02*
