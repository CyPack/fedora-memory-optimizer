# 🐧 Linux Distro Guide for Low RAM Systems

> **Target Audience**: Systems with 4GB and 8GB RAM
> **Goal**: Optimal distro selection and memory optimization

---

## 📊 Quick Comparison Table

### Idle Memory Usage (After Boot, No Applications Open)

| Distro | Desktop | Idle RAM | Min RAM | Recommended RAM | Difficulty |
|--------|---------|----------|---------|-----------------|------------|
| **antiX** | IceWM | 70-200 MB | 256 MB | 512 MB | Medium |
| **Puppy Linux** | JWM | 100-150 MB | 256 MB | 512 MB | Easy |
| **Tiny Core** | FLTK | 50-100 MB | 64 MB | 128 MB | Hard |
| **Lubuntu** | LXQt | 450-500 MB | 1 GB | 2 GB | Easy |
| **MX Linux Fluxbox** | Fluxbox | 500 MB | 1 GB | 2 GB | Medium |
| **Peppermint OS** | LXDE | 400-500 MB | 1 GB | 2 GB | Easy |
| **Linux Mint XFCE** | XFCE | 850-900 MB | 2 GB | 4 GB | Easy |
| **Xubuntu** | XFCE | 600-800 MB | 1 GB | 2 GB | Easy |
| **MX Linux XFCE** | XFCE | 500-600 MB | 1 GB | 2 GB | Easy |
| **Linux Mint MATE** | MATE | 850 MB | 2 GB | 4 GB | Easy |
| **Q4OS** | Trinity | 136-200 MB | 512 MB | 1 GB | Easy |
| **Bodhi Linux** | Moksha | 200-250 MB | 512 MB | 1 GB | Medium |

---

## 🏆 Recommendations by RAM

### 💾 4GB RAM Systems

#### Primary Recommendation: **Lubuntu**

```
✅ Pros:
- Ubuntu repository access (wide software selection)
- LXQt is light yet modern looking
- Snap/Flatpak support
- Easy installation and use
- Regular security updates

❌ Cons:
- Not as light as antiX
- Some modern websites may struggle

📊 Performance:
- Idle: ~450-500 MB
- Firefox + 10 tabs: ~1.5 GB
- LibreOffice: ~600-700 MB
```

**Installation:**
```bash
# Download ISO: https://lubuntu.me/downloads/
# Write to USB (on Linux):
sudo dd if=lubuntu-24.04-desktop-amd64.iso of=/dev/sdX bs=4M status=progress
```

#### Alternative 1: **antiX**

```
✅ Pros:
- Ultra lightweight (70-200 MB idle)
- 32-bit support (old hardware)
- systemd-free (runit/sysvinit)
- Works even on very old hardware

❌ Cons:
- Visually dated
- Complex for new users
- Less application support

📊 Performance:
- Idle: ~70-200 MB
- PaleMoon + 5 tabs: ~400 MB
- LibreOffice: ~350 MB
```

**Installation:**
```bash
# Download ISO: https://antixlinux.com/download/
# Choose 32-bit or 64-bit
# "Full" edition recommended (for beginners)
```

#### Alternative 2: **MX Linux Fluxbox**

```
✅ Pros:
- MX Tools (easy configuration)
- Debian stable based (reliable)
- More user-friendly than antiX
- Flatpak support

❌ Cons:
- Slightly heavier than antiX
- Fluxbox requires adjustment

📊 Performance:
- Idle: ~500 MB
- Firefox + 10 tabs: ~1.8 GB
```

**Installation:**
```bash
# Download ISO: https://mxlinux.org/download-links/
# Select "MX-23 Fluxbox"
```

---

### 💾 8GB RAM Systems

#### Primary Recommendation: **Linux Mint XFCE**

```
✅ Pros:
- Most user-friendly lightweight distro
- Ubuntu/Debian repo access
- No Snap (by default)
- Excellent documentation
- Timeshift backup included
- Easy driver management

❌ Cons:
- Slightly heavier than Lubuntu
- XFCE can sometimes feel "dated"

📊 Performance:
- Idle: ~850-900 MB
- Firefox + 20 tabs: ~2.5 GB
- VS Code: ~1 GB
- Docker: Each container +200-500 MB
```

**Installation:**
```bash
# Download ISO: https://linuxmint.com/edition.php?id=311
# Select "XFCE" edition (21.3 or 22)
```

#### Alternative 1: **MX Linux XFCE**

```
✅ Pros:
- Debian stable + backports
- MX Tools are excellent
- Snapshot feature (system backup)
- Easy switch to Fluxbox

❌ Cons:
- Not as popular as Mint (fewer resources)

📊 Performance:
- Idle: ~500-600 MB
- Firefox + 15 tabs: ~2 GB
```

#### Alternative 2: **Xubuntu**

```
✅ Pros:
- Ubuntu base (widest support)
- XFCE + Ubuntu tools
- Snap support (optional)

❌ Cons:
- Snap default (Firefox snap)
- Slightly heavier than Mint XFCE

📊 Performance:
- Idle: ~600-800 MB
```

---

## 🔧 Common Optimizations (For All Distros)

### 1. zram Installation (Debian/Ubuntu Based)

```bash
# Installation
sudo apt install zram-tools

# Configuration
sudo nano /etc/default/zramswap
```

```ini
# /etc/default/zramswap contents
ALGO=zstd
PERCENT=50
PRIORITY=100
```

```bash
# Restart
sudo systemctl restart zramswap

# Verification
zramctl
swapon --show
```

### 2. Swappiness Setting

```bash
# Temporary (until reboot)
sudo sysctl vm.swappiness=150

# Permanent
echo "vm.swappiness=150" | sudo tee -a /etc/sysctl.d/99-swap.conf
sudo sysctl --system
```

### 3. Firefox Optimization

Change in `about:config`:

| Setting | Value | Description |
|---------|-------|-------------|
| `browser.tabs.unloadOnLowMemory` | true | Tab unloading active |
| `browser.low_commit_space_threshold_mb` | 1000-2000 | When to start |
| `dom.ipc.processCount` | 2-4 | Content process count |
| `browser.sessionstore.restore_tabs_lazily` | true | Lazy tab loading |

### 4. Disable Unnecessary Services

```bash
# If not using Bluetooth
sudo systemctl disable bluetooth

# If not using printer
sudo systemctl disable cups

# If not using network shares
sudo systemctl disable smbd nmbd

# Which services are running?
systemctl list-unit-files --state=enabled
```

### 5. Lightweight Alternative Applications

| Category | Heavy | Lightweight Alternative |
|----------|-------|-------------------------|
| Browser | Firefox/Chrome | Falkon, Midori, PaleMoon |
| Office | LibreOffice | AbiWord, Gnumeric |
| Text Editor | VS Code | Geany, Featherpad, Mousepad |
| File Manager | Nautilus | PCManFM, Thunar |
| PDF Viewer | Evince | MuPDF, Zathura |
| Image Viewer | Eye of GNOME | feh, sxiv |
| Video Player | VLC | mpv |
| Email | Thunderbird | Claws Mail, Sylpheed |

---

## 📱 Avoid Electron Apps!

Electron applications each carry a mini Chromium:

| Application | Typical RAM | Alternative |
|-------------|-------------|-------------|
| Slack | 500-800 MB | IRC client, Matrix (Element web) |
| Discord | 300-500 MB | WebCord, Discord web |
| VS Code | 400-800 MB | Geany, Kate, Vim, Neovim |
| Teams | 500-1000 MB | Web version |
| Notion | 300-500 MB | Obsidian (lighter), Joplin |

---

## 🖥️ Desktop Environment Comparison

```
Lightweight ranking (lightest to heaviest):

Window Managers (Lightest):
├── i3wm          (~10-20 MB)
├── Openbox       (~10-20 MB)
├── Fluxbox       (~15-25 MB)
├── IceWM         (~15-25 MB)
└── JWM           (~10-15 MB)

Lightweight DEs:
├── LXQt          (~150-200 MB)
├── LXDE          (~100-150 MB)
├── XFCE          (~200-300 MB)
└── MATE          (~250-350 MB)

Full DEs (Heavy):
├── KDE Plasma    (~400-600 MB)
├── Cinnamon      (~400-500 MB)
└── GNOME         (~600-800 MB)
```

---

## 📈 Practical Scenario Recommendations

### Scenario 1: "Just web browsing and email"

**4GB RAM:**
- Distro: Lubuntu or antiX
- Browser: Falkon or Firefox (max 10 tabs)
- Email: Claws Mail

**8GB RAM:**
- Distro: Linux Mint XFCE
- Browser: Firefox (max 30 tabs)
- Email: Thunderbird OK

### Scenario 2: "Office work (Word, Excel, PDF)"

**4GB RAM:**
- Distro: Lubuntu
- Office: LibreOffice (keep single document open)
- PDF: MuPDF

**8GB RAM:**
- Distro: Linux Mint XFCE or MX Linux
- Office: LibreOffice (3-4 documents OK)
- PDF: Evince OK

### Scenario 3: "Light software development"

**4GB RAM:**
- Distro: Lubuntu or antiX
- Editor: Geany, Vim, nano
- Git: Terminal
- Docker: ❌ NOT RECOMMENDED

**8GB RAM:**
- Distro: Linux Mint XFCE
- Editor: VS Code (use carefully) or Geany
- Git: Terminal or GitKraken (heavy)
- Docker: Maximum 2-3 containers

### Scenario 4: "Reviving old laptop"

**2GB RAM (very old):**
- Distro: antiX or Puppy Linux
- Browser: Dillo, NetSurf, Links2
- Everything minimal

**4GB RAM:**
- Distro: Lubuntu, Q4OS Trinity
- Browser: PaleMoon, Falkon

---

## 🔗 Useful Links

### Distro Downloads
- [Lubuntu](https://lubuntu.me/downloads/)
- [Linux Mint](https://linuxmint.com/download.php)
- [MX Linux](https://mxlinux.org/download-links/)
- [antiX](https://antixlinux.com/download/)
- [Xubuntu](https://xubuntu.org/download/)
- [Peppermint OS](https://peppermintos.com/guide/downloading/)
- [Q4OS](https://q4os.org/downloads1.html)
- [Bodhi Linux](https://www.bodhilinux.com/download/)

### Documentation
- [Arch Wiki (universal)](https://wiki.archlinux.org/)
- [Debian Wiki](https://wiki.debian.org/)
- [Ubuntu Community Help](https://help.ubuntu.com/community)
- [Linux Mint Forums](https://forums.linuxmint.com/)
- [MX Linux Wiki](https://mxlinux.org/wiki/)

### Memory Optimization
- [zram Wiki](https://wiki.debian.org/ZRam)
- [Firefox Memory](https://support.mozilla.org/en-US/kb/firefox-uses-too-much-memory-or-cpu-resources)

---

## 📋 Checklist: Post-Installation

```
[ ] zram installed and active
[ ] Swappiness set (150-180)
[ ] Unnecessary services disabled
[ ] Firefox optimizations applied
[ ] Electron apps minimized
[ ] Timeshift/backup installed
[ ] Updates applied
```

---

## 🆘 Troubleshooting

### "System freezes"
1. `dmesg | grep -i oom` - OOM killer logs
2. `journalctl -k | grep -i memory` - Kernel memory logs
3. Check zram and swap: `swapon --show`

### "Too slow"
1. Find RAM-consuming processes with `htop`
2. Check disk I/O with `iotop`
3. If swap usage is too high, RAM is insufficient

### "Browser using too much RAM"
1. Reduce tab count
2. Install uBlock Origin (ads = RAM)
3. Trigger GC from about:memory page
4. Try alternative lightweight browser

---

*Last updated: 2026-01-02*
*This guide is optimized for 4GB and 8GB RAM systems.*
