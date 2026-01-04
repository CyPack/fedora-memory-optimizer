# 🐧 Memory Optimizer for Debian/Ubuntu

> This guide explains zram + swap optimization for Debian, Ubuntu, Linux Mint and derivatives.

---

## ⚠️ IMPORTANT NOTE: v4 Never-Kill Philosophy

This project uses a **never-kill** approach for Fedora:
- earlyoom DISABLED
- No process killing
- Throttle only (slow down)

The guide below shows the **legacy v1 approach** (with earlyoom).
For never-kill mode, skip the earlyoom section and only install zram + swapfile.

---

## ⚠️ Fedora vs Debian/Ubuntu Differences

| Feature | Fedora | Debian/Ubuntu |
|---------|--------|---------------|
| Package manager | dnf | apt |
| zram tool | zram-generator | zram-tools |
| Default FS | btrfs | ext4 |
| systemd-oomd | Default enabled | Manual install |
| earlyoom | dnf install | apt install |

---

## 🚀 Quick Installation

### 1. zram Installation

```bash
# Install zram-tools
sudo apt update
sudo apt install zram-tools

# Configure
sudo nano /etc/default/zramswap
```

**`/etc/default/zramswap` contents:**
```ini
# Compression algorithm (zstd recommended)
ALGO=zstd

# RAM percentage (50% of 4GB RAM = 2GB zram)
PERCENT=50

# Priority (higher = used first)
PRIORITY=100
```

```bash
# Restart service
sudo systemctl restart zramswap

# Verify
zramctl
swapon --show
```

### 2. Kernel Parameters

```bash
# sysctl settings
sudo tee /etc/sysctl.d/99-memory-optimizer.conf << 'EOF'
# Aggressive swap for zram
vm.swappiness = 150

# Optimized for zram
vm.page-cluster = 0

# Cache management
vm.vfs_cache_pressure = 50

# Watermark
vm.watermark_scale_factor = 125
EOF

# Apply
sudo sysctl --system
```

### 3. earlyoom Installation

```bash
sudo apt install earlyoom

# Configure
sudo nano /etc/default/earlyoom
```

**`/etc/default/earlyoom` contents:**
```ini
EARLYOOM_ARGS="-r 60 -m 8 -s 90 --prefer '(firefox|chromium|chrome|electron|slack|discord|teams)' --avoid '(Xorg|sshd|systemd|pulseaudio|pipewire)' -n"
```

```bash
sudo systemctl enable --now earlyoom
sudo systemctl status earlyoom
```

### 4. NVMe/SSD Swapfile

```bash
# Create swapfile
sudo fallocate -l 32G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile

# Add to fstab
echo '/swapfile none swap sw,pri=10 0 0' | sudo tee -a /etc/fstab

# Activate
sudo swapon /swapfile
swapon --show
```

---

## 📊 Recommended Settings by RAM

### 4GB RAM

```ini
# /etc/default/zramswap
ALGO=zstd
PERCENT=50
PRIORITY=100

# /etc/sysctl.d/99-memory-optimizer.conf
vm.swappiness = 180
vm.page-cluster = 0
vm.vfs_cache_pressure = 75

# Swapfile: 16GB
sudo fallocate -l 16G /swapfile
```

### 8GB RAM

```ini
# /etc/default/zramswap
ALGO=zstd
PERCENT=50
PRIORITY=100

# /etc/sysctl.d/99-memory-optimizer.conf
vm.swappiness = 150
vm.page-cluster = 0
vm.vfs_cache_pressure = 60

# Swapfile: 32GB
sudo fallocate -l 32G /swapfile
```

### 16GB RAM

```ini
# /etc/default/zramswap
ALGO=zstd
PERCENT=50
PRIORITY=100

# /etc/sysctl.d/99-memory-optimizer.conf
vm.swappiness = 150
vm.page-cluster = 0
vm.vfs_cache_pressure = 50

# Swapfile: 64GB
sudo fallocate -l 64G /swapfile
```

---

## 🔧 Verification Commands

```bash
# zram status
zramctl

# All swaps
swapon --show

# Kernel parameters
sysctl vm.swappiness vm.page-cluster vm.vfs_cache_pressure

# earlyoom status
systemctl status earlyoom

# Memory pressure
cat /proc/pressure/memory
```

---

## 🆘 Troubleshooting

### "zram installed but not active"

```bash
sudo systemctl enable zramswap
sudo systemctl start zramswap
zramctl
```

### "Swappiness not changing"

```bash
# Temporary change (until reboot)
sudo sysctl vm.swappiness=150

# Check permanent change
cat /etc/sysctl.d/99-memory-optimizer.conf

# Reload
sudo sysctl --system
```

### "earlyoom not killing processes"

```bash
# Check logs
journalctl -u earlyoom -f

# Check configuration
cat /etc/default/earlyoom
```

---

## 📚 References

- [Debian Wiki: ZRam](https://wiki.debian.org/ZRam)
- [Ubuntu Handbook: Enable Zram](https://ubuntuhandbook.org/index.php/2024/08/enable-zram-ubuntu/)
- [earlyoom GitHub](https://github.com/rfjakob/earlyoom)

---

*This guide has been tested with Debian 12+, Ubuntu 22.04+, Linux Mint 21+.*
