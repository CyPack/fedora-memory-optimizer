# Fedora Memory Optimizer - Değerlendirme Raporu

**Tarih:** 2026-01-27
**Sistem:** Fedora 43 (GNOME Wayland)
**RAM:** 15 GB | **Swap:** 22 GB

---

## 1. Özet

Bu rapor, Fedora masaüstü sisteminde OOM (Out of Memory) koruması için yapılan yapılandırmaları, test sonuçlarını ve mimari kararları belgelemektedir.

### Hedef
- 3rd party uygulamalar sistemi dolduramamalı
- Sistem kritik bileşenleri (gnome-shell, pipewire) her zaman korunmalı
- Memory pressure durumunda browser'lar önce öldürülmeli
- VS Code, terminal gibi geliştirme araçları korunmalı

### Sonuç
✅ **Sistem başarıyla yapılandırıldı ve test edildi.**

---

## 2. Sistem Mimarisi

### 2.1 Cgroup Hiyerarşisi

```
/ (root cgroup)
├── init.scope
│   └── systemd (PID 1)
│
├── system.slice
│   ├── earlyoom.service
│   ├── oom-protection-daemon.service
│   ├── systemd-oomd.service
│   └── Diğer sistem servisleri
│
└── user.slice
    └── user-1000.slice ◄── MemoryMax=87% (14GB) LİMİT
        └── user@1000.service
            │
            ├── session.slice ◄── GNOME kritik (MemoryMin=250MB koruma)
            │   ├── org.gnome.Shell@wayland.service (gnome-shell)
            │   ├── pipewire.service
            │   ├── pipewire-pulse.service
            │   └── wireplumber.service
            │
            └── app.slice ◄── Kullanıcı uygulamaları
                ├── Firefox
                ├── VS Code
                ├── Terminal apps
                └── 3rd party apps
```

### 2.2 Memory Limitleri

| Cgroup | memory.max | memory.high | memory.min | Açıklama |
|--------|------------|-------------|------------|----------|
| user-1000.slice | 14 GB (87%) | 12.3 GB (80%) | - | Hard limit |
| session.slice | inherit (14GB) | - | 250 MB | uresourced koruması |
| app.slice | inherit (14GB) | - | 0 | Koruma yok |

### 2.3 Swap Limitleri

| Cgroup | memory.swap.max | Açıklama |
|--------|-----------------|----------|
| user-1000.slice | infinity | Swap sınırı yok (earlyoom yönetir) |

### 2.4 Detaylı Cgroup Analizi

```
user-1000.slice: 14GB MAX (bizim limitimiz)
│
├── session.slice (gnome-shell, pipewire)
│   ├── memory.max: inherit → 14GB
│   └── memory.min: 250MB (uresourced koruması) ✓
│
└── app.slice (Firefox, VS Code, 3rd party)
    ├── memory.max: inherit → 14GB
    └── memory.min: 0 (koruma YOK)
```

### 2.5 Potansiyel Çakışma Senaryoları

| Senaryo | Ne Olur? |
|---------|----------|
| app.slice 13GB kullanırsa | session.slice için 1GB kalır (250MB garantili) |
| app.slice 14GB kullanmaya çalışırsa | user-1000.slice limiti devreye girer, OOM tetiklenir |
| OOM olursa kim ölür? | En yüksek oom_score'lu process (earlyoom browser'ı seçer) |

### 2.6 Fedora'nın Mevcut Koruma Mekanizmaları

1. **uresourced**: session.slice'a 250MB MemoryMin (soft protection)
2. **earlyoom**: oom_score'a göre kill (gnome-shell: -1000, korunuyor)
3. **systemd-oomd**: Pressure-based kill (ManagedOOMMemoryPressure=kill)

---

## 3. OOM Koruma Katmanları

### Katman 1: oom-protection-daemon (Proaktif)
**Dosya:** `/usr/local/bin/oom-protection-daemon`

Process'lerin `oom_score_adj` değerlerini dinamik olarak ayarlar:

| Kategori | oom_score_adj | Örnekler |
|----------|---------------|----------|
| IMMORTAL | -1000 | gnome-shell, pipewire, systemd, dbus |
| PROTECTED | -900 | code, vim, nvim, gnome-terminal |
| NORMAL | 0 | Diğer uygulamalar |
| KILLABLE | +500 | firefox, chrome, slack, discord |

**Çalışma prensibi:**
- Her 5 saniyede tüm process'leri tarar
- Yeni process'lere uygun score atar
- Kernel OOM killer'a hangi process'in önce öleceğini söyler

### Katman 2: earlyoom (Reaktif - Userspace)
**Config:** `/etc/default/earlyoom`

```bash
EARLYOOM_ARGS="-r 60 -m 5 -s 90 \
  --prefer '^(firefox|chrome|slack|discord|...)$' \
  --avoid '^(gnome-shell|pipewire|code|...)$' \
  -n"
```

| Parametre | Değer | Açıklama |
|-----------|-------|----------|
| -m | 5 | RAM < %5 olunca tetikle |
| -s | 90 | Swap > %90 olunca tetikle |
| --prefer | regex | Bu process'leri önce öldür |
| --avoid | regex | Bu process'leri asla öldürme |
| -n | - | Önce SIGTERM, sonra SIGKILL |

### Katman 3: systemd Slice Limitleri (Hard Limit)
**Config:** `/etc/systemd/system/user-.slice.d/50-memory-limit.conf`

```ini
[Slice]
MemoryHigh=80%              # Throttling başlangıcı
MemoryMax=87%               # Hard limit (OOM trigger)
MemorySwapMax=infinity      # Swap limiti yok
ManagedOOMSwap=kill         # systemd-oomd için
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=80%
```

### Katman 4: uresourced (Session Koruma)
**Config:** `/etc/uresourced.conf`

Fedora'nın varsayılan daemon'ı, aktif kullanıcının session.slice'ına koruma sağlar:

| Ayar | Değer | Açıklama |
|------|-------|----------|
| MemoryMin | 250 MB | session.slice için minimum garanti |
| CPUWeight | 500 | CPU önceliği |
| IOWeight | 500 | I/O önceliği |

### Katman 5: Kernel OOM Killer (Son Çare)
Tüm userspace çözümleri başarısız olursa kernel devreye girer ve `oom_score`'a göre process öldürür.

---

## 4. Kill Öncelik Sırası

Memory pressure durumunda process'ler şu sırayla öldürülür:

```
1. KILLABLE (+500): Firefox, Chrome, Slack, Discord, Zoom
         ↓
2. NORMAL (0): Diğer uygulamalar
         ↓
3. PROTECTED (-900): VS Code, Terminal, Vim
         ↓
4. IMMORTAL (-1000): gnome-shell, pipewire, systemd
         ↓
5. KERNEL: Asla öldürülmez
```

---

## 5. Test Sonuçları

### Test 1: stress-ng ile Memory Pressure
**Komut:** `stress-ng --vm 2 --vm-bytes 20G --timeout 300s --vm-keep`

| Zaman | RAM Used | RAM Avail | Swap Used | Olay |
|-------|----------|-----------|-----------|------|
| 23:12:46 | 74% | 25% | 6% | Stress başladı |
| 23:12:52 | 83% | 16% | 19% | Hızlı artış |
| 23:12:57 | 92% | 7% | 26% | Kritik seviye |
| 23:12:59 | 94% | 5% | 33% | earlyoom tetiklendi |
| 23:13:01 | 97% | 2% | 42% | **stress-ng ÖLDÜRÜLDÜ** |

### earlyoom Log:
```
Jan 27 23:13:00 earlyoom: low memory! at or below SIGTERM limits: mem 5.00%, swap 90.00%
Jan 27 23:13:01 earlyoom: sending SIGTERM to process 173803 uid 1000 "stress-ng-vm":
                         oom_score 1489, VmRSS 7013 MiB
```

### Sonuç:
- ✅ stress-ng öldürüldü (oom_score: 1489)
- ✅ gnome-shell korundu (oom_score: -1000)
- ✅ Firefox korundu (test sırasında memory kullanmıyordu)
- ✅ Sistem normale döndü (9.9GB available)

---

## 6. Servis Durumları

### 6.1 oom-protection-daemon
```
● oom-protection-daemon.service - OOM Protection Daemon
   Active: active (running)
   Memory: 2.7M

Korunan process sayıları:
  IMMORTAL  (score <= -1000): 88
  PROTECTED (score <= -500):  13
  KILLABLE  (score >= 500):   25
```

### 6.2 earlyoom
```
● earlyoom.service - Early OOM Daemon
   Active: active (running)
   Memory: 2.3M

   Her 60 saniyede memory durumu raporlanıyor
   mem avail: ~48% | swap free: ~94%
```

### 6.3 uresourced
```
● uresourced.service - User resource assignment daemon
   Active: active (running)
   Memory: 992K

   session.slice'a 250MB MemoryMin koruması sağlıyor
```

---

## 7. Dosya Konumları

### Yapılandırma Dosyaları
| Dosya | Konum | Açıklama |
|-------|-------|----------|
| Daemon script | `/usr/local/bin/oom-protection-daemon` | Ana daemon |
| Daemon service | `/etc/systemd/system/oom-protection-daemon.service` | Systemd unit |
| earlyoom config | `/etc/default/earlyoom` | earlyoom ayarları |
| User slice config | `/etc/systemd/system/user-.slice.d/50-memory-limit.conf` | Memory limitleri |
| uresourced config | `/etc/uresourced.conf` | Session koruması |

### Git Repository
| Konum | Açıklama |
|-------|----------|
| `/tmp/fedora-memory-optimizer-git/` | Kaynak dosyalar |
| GitHub | https://github.com/CyPack/fedora-memory-optimizer |

### Log Dosyaları
| Dosya | Açıklama |
|-------|----------|
| `/var/log/oom-protection-daemon.log` | Daemon logları |
| `journalctl -u earlyoom` | earlyoom logları |
| `journalctl -u oom-protection-daemon` | Daemon systemd logları |

---

## 8. Önemli Kararlar ve Gerekçeleri

### 8.1 Neden user-1000.slice'a Limit?
**Karar:** MemoryMax=87% (14GB)

**Gerekçe:**
- Tüm kullanıcı uygulamalarını kapsar (session.slice + app.slice)
- %13 (2GB) sistem için rezerve kalır
- gnome-shell de bu limite dahil AMA uresourced 250MB koruma sağlıyor
- earlyoom IMMORTAL process'leri asla öldürmez

**Risk:** session.slice (gnome-shell) de bu limite dahil
**Mitigasyon:** uresourced MemoryMin + earlyoom oom_score koruması

### 8.2 Neden MemorySwapMax=infinity?
**Karar:** Swap limiti yok

**Gerekçe:**
- earlyoom swap %90'ı geçince devreye giriyor
- Hard swap limiti tüm uygulamaları etkiler (VS Code dahil)
- Swap'ın amacı emergency buffer olmak
- earlyoom daha akıllı karar veriyor (oom_score'a göre)

### 8.3 Neden app.slice'a Ayrı Limit Yok?
**Karar:** app.slice'a ayrı MemoryMax koymadık

**Gerekçe:**
- session.slice ve app.slice zaten aynı parent limiti paylaşıyor
- Ayrı limit karmaşıklık ekler, debug zorlaşır
- earlyoom zaten uygulamaları oom_score'a göre seçiyor
- Test'te sistem doğru çalıştı

---

## 9. Alternatif Stratejiler Değerlendirmesi

Bu bölüm, mevcut yapılandırma dışında değerlendirilen alternatifleri ve neden seçilmediklerini açıklar.

### Strateji A: Mevcut Yapı (SEÇİLDİ ✓)

```
user-1000.slice: MemoryMax=87% (14GB)
├── session.slice: uresourced 250MB koruma
└── app.slice: earlyoom oom_score yönetimi
```

**Avantajlar:**
- Test'te başarıyla çalıştı
- Basit ve anlaşılır
- earlyoom akıllı seçim yapıyor

**Dezavantajlar:**
- session.slice ve app.slice aynı havuzu paylaşıyor

### Strateji B: app.slice'a Ayrı Limit

```
user-1000.slice: Limit YOK
├── session.slice: Limit YOK (gnome-shell özgür)
└── app.slice: MemoryMax=75%
```

**Avantajlar:**
- gnome-shell tamamen bağımsız
- Daha güçlü izolasyon

**Dezavantajlar:**
- Her uygulama aynı %75'i paylaşır
- VS Code da bu limitten etkilenir
- Daha karmaşık yapılandırma

**Neden seçilmedi:** earlyoom zaten oom_score'a göre doğru seçim yapıyor

### Strateji C: session.slice Korumasını Artır

```
uresourced config:
  MemoryMin: 250MB → 1GB
```

**Avantajlar:**
- gnome-shell için daha güçlü garanti

**Dezavantajlar:**
- uresourced config değişikliği gerekir
- Fedora varsayılanından sapma
- Test edilmedi

**Neden seçilmedi:** Mevcut 250MB + earlyoom koruması yeterli

### Strateji Karşılaştırma Tablosu

| Strateji | gnome-shell Koruması | Karmaşıklık | Test Durumu |
|----------|---------------------|-------------|-------------|
| A (Mevcut) | uresourced + earlyoom | Düşük | ✅ Test edildi |
| B (app.slice limit) | Tam izolasyon | Orta | ❌ Test edilmedi |
| C (MemoryMin artır) | 1GB garanti | Düşük | ❌ Test edilmedi |

### Kaynaklar

- [Fedora Reserve Resources](https://fedoraproject.org/wiki/Changes/Reserve_resources_for_active_user_WS)
- [uresourced Package](https://packages.fedoraproject.org/pkgs/uresourced/uresourced/)
- [systemd.resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)

---

## 10. Bilinen Sorunlar ve Çözümler

### Sorun 1: gnome-shell memory leak
**Belirti:** gnome-shell zamanla çok RAM kullanır
**Çözüm:** `gnome-shell --replace` veya logout/login

### Sorun 2: earlyoom yanlış process öldürüyor
**Belirti:** Korunması gereken app öldürüldü
**Çözüm:**
- `--avoid` regex'ine ekle
- oom-protection-daemon PROTECTED listesine ekle

### Sorun 3: Sistem donuyor, earlyoom çalışmıyor
**Belirti:** Kernel OOM devreye giriyor
**Çözüm:**
- earlyoom threshold'larını yükselt (-m 10 -s 80)
- Daha erken müdahale

---

## 11. Komutlar Referansı

### Durum Kontrolü
```bash
# Servis durumları
systemctl status oom-protection-daemon earlyoom uresourced

# OOM score'ları görüntüle
/usr/local/bin/oom-protection-daemon status

# Tek seferlik tarama
sudo /usr/local/bin/oom-protection-daemon run-once

# Memory durumu
free -h
cat /proc/meminfo | grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree"

# Cgroup limitleri
systemctl show user-1000.slice | grep -E "^Memory"
```

### Log Takibi
```bash
# earlyoom logları (canlı)
sudo journalctl -u earlyoom -f

# oom-protection-daemon logları
sudo journalctl -u oom-protection-daemon -f
tail -f /var/log/oom-protection-daemon.log

# Kernel OOM logları
dmesg | grep -i oom
```

### Test
```bash
# Memory stress testi
stress-ng --vm 2 --vm-bytes 20G --timeout 300s --vm-keep

# Belirli process'in oom_score'u
cat /proc/$(pgrep gnome-shell)/oom_score_adj
```

---

## 12. Sonuç

Fedora Memory Optimizer başarıyla yapılandırıldı:

| Bileşen | Durum | Görevi |
|---------|-------|--------|
| oom-protection-daemon | ✅ Aktif | Process score yönetimi |
| earlyoom | ✅ Aktif | Userspace OOM killer |
| User slice limiti | ✅ Aktif | Hard memory limit |
| uresourced | ✅ Aktif | Session koruması |

**Test sonucu:** Memory pressure altında sistem doğru davrandı - stress-ng öldürüldü, gnome-shell korundu.

---

*Rapor oluşturulma tarihi: 2026-01-27 23:30*
*Oluşturan: Claude (Anthropic)*
