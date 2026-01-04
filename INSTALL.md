# 🚀 INSTALLATION GUIDE

## Quick Start

```bash
# 1. Navigate to the Downloads folder
cd ~/Downloads/fedora-memory-optimizer

# 2. Make scripts executable
chmod +x *.sh

# 3. Run Memory Optimizer (zram + swapfile + never-kill)
sudo ./memory-optimizer-v4.sh

# 4. Hibernate setup (optional)
sudo ./setup-hibernation-v4.sh

# 5. Swap notifications (optional, no root required)
./swap-monitor.sh --install

# 6. Reboot
sudo reboot
```

---

## 📋 Script Descriptions

| Script | What It Does | Command |
|--------|--------------|---------|
| `memory-optimizer-v4.sh` | zram + swapfile + never-kill | `sudo ./memory-optimizer-v4.sh` |
| `setup-hibernation-v4.sh` | Hibernate configuration | `sudo ./setup-hibernation-v4.sh` |
| `swap-monitor.sh` | Desktop notifications | `./swap-monitor.sh --install` |

---

## ⚙️ Custom RAM Configs

> **Note:** Memory Optimizer automatically detects your RAM amount. These files are only for those who want manual configuration.

```
config/examples/
├── 4gb-ram.conf    # Low RAM systems
├── 8gb-ram.conf    
├── 16gb-ram.conf   # DEFAULT
├── 32gb-ram.conf   
└── 64gb-ram.conf   # High RAM systems
```

---

## 🗑️ Uninstall

> ⚠️ **If you want to revert all changes:**

```bash
sudo ./uninstall.sh
```

A backup is created and can be restored with `--restore`:

```bash
sudo ./uninstall.sh --restore
```

---

## ✅ Post-Installation Test

```bash
# Hibernate test
systemctl hibernate

# Swap status
swap-monitor --status

# Memory status
free -h
```
