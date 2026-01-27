# Lunar Lake 32GB Optimizasyonu - Quick Reference Guide v4.0

## 🔴 ÖNEMLİ DEĞİŞİKLİKLER (v4.0)

| Parametre | v3.0 | v4.0 | Neden |
|-----------|------|------|-------|
| **zram-size** | `ram / 2` (16GB) | `ram / 2` (16GB) | Aynı |
| **disk-swap** | ❌ Yok | ✅ 8GB (priority 10) | OOM prevention |
| **swap-tiers** | 2 tier | 3 tier | Daha güvenli |

---

## Swap Mimarisi v4.0

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         MEMORY HIERARCHY v4.0                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   TIER 1: Physical RAM (32GB)                                          │
│           └── Primary working memory                                    │
│           └── Latency: ~100 ns                                         │
│                        │                                                │
│                        ▼ (memory pressure)                              │
│                                                                         │
│   TIER 2: ZRAM Swap (16GB, priority 100)                               │
│           └── Compressed RAM swap, ~1μs latency                        │
│           └── With 3:1 compression: ~48GB effective                    │
│           └── Algorithm: zstd                                          │
│                        │                                                │
│                        ▼ (ZRAM exhausted)                               │
│                                                                         │
│   TIER 3: Disk Swap (8GB, priority 10) ← NEW in v4.0                   │
│           └── NVMe/SSD fallback, ~150μs latency                        │
│           └── Emergency buffer, prevents OOM                           │
│           └── Rarely used in normal operation                          │
│                        │                                                │
│                        ▼ (all swap exhausted)                           │
│                                                                         │
│   TIER 4: OOM Killer                                                   │
│           └── Last resort, kills highest oom_score process             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Neden 8GB Disk Swap?

| v3.0 Riski | v4.0 Güvenliği |
|------------|----------------|
| ZRAM dolarsa → OOM Killer | ZRAM dolarsa → Disk swap devreye girer |
| Process'ler ölür | Sistem yavaşlar ama çalışmaya devam eder |
| Veri kaybı riski | OOM önlenir |

### Priority Sistemi

| Priority | Device | Latency | Kullanım |
|----------|--------|---------|----------|
| 100 | ZRAM | ~1 μs | Normal operation (önce kullanılır) |
| 10 | Disk Swap | ~150 μs | Emergency only (ZRAM dolduktan sonra) |

**Kernel önce yüksek priority'li swap kullanır!**

---

## Efektif Kapasite

```
Physical RAM:      32 GB
ZRAM (3:1):       ~48 GB effective
Disk Swap:          8 GB
───────────────────────────
TOTAL:            ~88 GB before OOM
```

---

## Hızlı Kurulum

### 1. Script'i Çalıştır

```bash
# v4.0 script'i indir veya kopyala
chmod +x lunar-lake-32gb-optimizer-v4.sh
sudo ./lunar-lake-32gb-optimizer-v4.sh
```

### 2. Reboot

```bash
sudo reboot
```

### 3. Doğrula

```bash
sudo lunar-lake-verify.sh
```

---

## Sadece ZRAM (Disk Swap Olmadan)

v3.0 uyumlu mod - disk swap istemiyorsanız:

```bash
sudo ./lunar-lake-32gb-optimizer-v4.sh --no-disk-swap
```

---

## Manuel Kurulum (Alternatif)

### Adım 1: Paketler

```bash
sudo dnf install zram-generator-defaults util-linux
```

### Adım 2: ZRAM Konfigürasyonu

```bash
sudo tee /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
# v4.0: ram / 2 (16GB on 32GB system)
zram-size = ram / 2
max-zram-size = 16384
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
```

### Adım 3: Disk Swap Fallback (8GB)

```bash
# Swapfile oluştur
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile

# Aktive et (düşük priority - ZRAM'dan sonra)
sudo swapon --priority=10 /swapfile

# Kalıcı yap
echo '/swapfile none swap sw,pri=10 0 0' | sudo tee -a /etc/fstab
```

### Adım 4: Sysctl

```bash
sudo tee /etc/sysctl.d/99-zram-lunar-lake.conf << 'EOF'
# ZRAM optimization
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0

# 32GB RAM optimization
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF

sudo sysctl -p /etc/sysctl.d/99-zram-lunar-lake.conf
```

### Adım 5: ZSWAP Devre Dışı

```bash
sudo grubby --update-kernel=ALL --args="zswap.enabled=0"
```

### Adım 6: Reboot

```bash
sudo reboot
```

---

## Doğrulama Komutları

```bash
# Swap durumu (İKİ swap bekleniyor!)
swapon --show
# Expected:
# NAME       TYPE       SIZE  USED PRIO
# /dev/zram0 partition  16G    0B  100   ← ZRAM (primary)
# /swapfile  file        8G    0B   10   ← Disk (fallback)

# ZRAM durumu
zramctl
# Expected: /dev/zram0  zstd  16G  ...

# ZSWAP durumu
cat /sys/module/zswap/parameters/enabled
# Expected: N

# Sysctl değerleri
sysctl vm.swappiness vm.page-cluster vm.vfs_cache_pressure
# Expected: 180, 0, 50

# Memory pressure (PSI)
cat /proc/pressure/memory
# avg10 < 10 = healthy

# Disk swap kullanılıyor mu?
swapon --show=NAME,USED | grep swapfile
# Eğer USED > 0 ise: Memory pressure yüksek!
```

---

## v3.0 vs v4.0 Karşılaştırma

| Özellik | v3.0 | v4.0 |
|---------|------|------|
| ZRAM boyutu | 16GB | 16GB |
| Disk swap | ❌ Yok | ✅ 8GB (fallback) |
| OOM riski | ZRAM dolarsa OOM | Disk swap buffer var |
| SSD yazma | Minimum | Biraz artabilir (nadiren) |
| Efektif kapasite | ~80GB | ~88GB |

### Ne Zaman v3.0 Tercih Edilir?

- SSD ömrünü maksimize etmek isteyenler
- Memory kullanımı hiçbir zaman %90'ı geçmeyenler
- "Disk swap asla istemiyorum" diyenler

### Ne Zaman v4.0 Tercih Edilir?

- ✅ Heavy workloads (VMs, containers, IDE + browsers)
- ✅ OOM Killer'dan kaçınmak isteyenler
- ✅ "Yavaşlasın ama ölmesin" diyenler
- ✅ Server workload'ları
- ✅ Memory leak riski olan uygulamalar

---

## Sistem Metrikleri İzleme

### Hangi Swap Kullanılıyor?

```bash
# Real-time izleme
watch -n1 'swapon --show && echo && cat /proc/pressure/memory'
```

### Performans Durumu

| Durum | ZRAM Used | Disk Swap Used | PSI some | Aksiyon |
|-------|-----------|----------------|----------|---------|
| ✅ Normal | < 50% | 0 | < 5 | - |
| ⚠️ Yüksek yük | > 50% | 0 | 5-15 | Monitor et |
| 🟠 Uyarı | > 90% | > 0 | 15-30 | Process'leri kontrol et |
| 🔴 Kritik | FULL | > 50% | > 30 | Acil müdahale |

### Disk Swap Kullanılıyorsa?

```bash
# En çok swap kullanan process'ler
for f in /proc/*/status; do
  awk '/VmSwap/{swap=$2} /Name/{name=$2}
  END{if(swap>0)print swap,name}' "$f" 2>/dev/null
done | sort -rn | head -10
```

---

## Troubleshooting

### Disk Swap Sürekli Kullanılıyor

```bash
# Memory pressure kontrol
cat /proc/pressure/memory
# avg10 > 25 = ciddi sorun

# ZRAM dolu mu?
zramctl
# DATA sütunu DISKSIZE'a yakınsa: ZRAM dolu

# Çözüm:
# 1. Memory leak var mı kontrol et (htop)
# 2. Gereksiz process'leri kapat
# 3. vm.swappiness'ı düşür (150?)
```

### ZRAM veya Disk Swap Aktif Değil

```bash
# Servisleri restart et
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service

# Disk swap manuel aktive
sudo swapon --priority=10 /swapfile
```

### Compression Ratio Düşük (< 2:1)

```bash
cat /sys/block/zram0/mm_stat | awk '{print "Ratio: " $1/$2}'

# Düşük ratio nedenleri:
# - Encrypted containers/VMs
# - Random/binary data
# - Already compressed files
# → Normal davranış, sorun değil
```

---

## Sysctl Parametreleri Açıklaması

| Parametre | Değer | Açıklama |
|-----------|-------|----------|
| `vm.swappiness` | 180 | ZRAM RAM hızında, erken swap OK |
| `vm.watermark_boost_factor` | 0 | ZRAM için gereksiz, devre dışı |
| `vm.watermark_scale_factor` | 125 | Daha smooth memory management |
| `vm.page-cluster` | 0 | ZRAM'da batch I/O gereksiz |
| `vm.vfs_cache_pressure` | 50 | 32GB RAM var, cache uzun tut |
| `vm.dirty_ratio` | 10 | SSD için daha sık sync |
| `vm.dirty_background_ratio` | 5 | Erken background writeback |

---

## Dosya Konumları

| Dosya | Açıklama |
|-------|----------|
| `/etc/systemd/zram-generator.conf` | ZRAM konfigürasyonu |
| `/etc/sysctl.d/99-zram-lunar-lake.conf` | Sysctl optimizasyonları |
| `/swapfile` | 8GB disk swap fallback |
| `/var/log/lunar-lake-optimizer.log` | Script log dosyası |
| `/var/backup/lunar-lake-optimizer/` | Backup dizini |
| `/usr/local/bin/lunar-lake-verify.sh` | Doğrulama scripti |

---

## Rollback

```bash
# En son backup'ı bul
ls -la /var/backup/lunar-lake-optimizer/

# Rollback yap (disk swap opsiyonel kaldırılabilir)
sudo ./lunar-lake-32gb-optimizer-v4.sh --rollback /var/backup/lunar-lake-optimizer/YYYYMMDD_HHMMSS

# Reboot
sudo reboot
```

---

## Kaynaklar

### Resmi Dokümantasyon
- [Kernel Docs - ZRAM](https://docs.kernel.org/admin-guide/blockdev/zram.html)
- [Kernel Docs - Sysctl VM](https://docs.kernel.org/admin-guide/sysctl/vm.html)
- [Fedora Wiki - SwapOnZRAM](https://fedoraproject.org/wiki/Changes/SwapOnZRAM)

### Community & Benchmarks
- [Arch Wiki - ZRAM](https://wiki.archlinux.org/title/Zram)
- [Arch Wiki - Swap](https://wiki.archlinux.org/title/Swap)

---

## Hızlı Referans Kartı

```
┌─────────────────────────────────────────────────────────────────────────┐
│ LUNAR LAKE 32GB - ZRAM + DISK SWAP v4.0 QUICK CARD                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│ SWAP HIERARCHY:                                                         │
│   [1] ZRAM      → 16GB  → Priority 100 (fast, primary)                 │
│   [2] Disk Swap →  8GB  → Priority  10 (slow, fallback)                │
│                                                                         │
│ Sysctl:                                                                 │
│   swappiness=180  page-cluster=0  vfs_cache_pressure=50                │
│   watermark_boost=0  watermark_scale=125                               │
│   dirty_ratio=10  dirty_background=5                                   │
│                                                                         │
│ Verify: swapon --show && cat /proc/pressure/memory                     │
│                                                                         │
│ Expected:                                                               │
│   /dev/zram0 partition 16G  0B  100  ← Primary (always used first)     │
│   /swapfile  file       8G  0B   10  ← Fallback (emergency only)       │
│                                                                         │
│ Effective capacity: ~88GB before OOM                                   │
│                                                                         │
│ ⚠️  Disk swap used > 0 = High memory pressure, investigate!            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

**Version:** 4.0.0 | **Date:** 2026-01-27 | **Target:** Fedora 43 + Lunar Lake 32GB
