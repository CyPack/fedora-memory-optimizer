# 🏗️ Architecture Documentation

## Overview

This document explains the technical rationale behind each component of the Fedora Memory Optimizer.

## Memory Management: Linux vs macOS

### Why Linux Defaults Are Problematic

| Aspect | Linux Default | macOS | This Optimizer |
|--------|---------------|-------|----------------|
| Compression | None (or zswap) | WKdm proactive | zram + zstd |
| OOM behavior | Kernel kills randomly | Graceful pressure warnings | 6-layer defense |
| Swap strategy | Reactive | Proactive | Aggressive (swappiness=180) |
| App prioritization | None | App Nap | earlyoom preferences |

### The Freeze Problem

Linux default behavior under memory pressure:

```
RAM fills → kswapd struggles → system becomes unresponsive →
kernel OOM killer activates → random process killed → possible data loss
```

This optimizer's behavior:

```
RAM 80% → Firefox unloads tabs → RAM 90% → throttle to zram →
zram fills → overflow to NVMe → still pressure → earlyoom kills browser →
never reaches kernel OOM
```

## Component Deep Dive

### 1. Kernel Parameters

#### vm.swappiness = 180

```
Range: 0-200 (since kernel 5.8 with zram)
Default: 60
Pop!_OS: 180

Higher value = more aggressive swapping
```

Why 180? With zram, swap is nearly RAM-speed. High swappiness ensures:
- Inactive pages move to compressed zram early
- More RAM available for active processes
- Prevents sudden OOM situations

#### vm.page-cluster = 0

```
Default: 3 (read 8 pages at once)
Optimal for zram: 0 (read 1 page)
```

Page-cluster optimizes HDDs (sequential reads). zram has random access like RAM, so readahead wastes CPU on decompression.

#### vm.min_free_kbytes

```
Default: ~67MB on 16GB system
This optimizer: ~150MB (1% of RAM)
```

Reserves memory for kernel operations. Too low = freeze during allocation spikes. Too high = wasted RAM.

#### vm.watermark_scale_factor

```
Default: 10
This optimizer: 125
```

Controls when kswapd wakes up. Higher = earlier activation = smoother memory reclaim.

### 2. zram Configuration

#### Why zram over zswap?

| Feature | zram | zswap |
|---------|------|-------|
| Backing store | None (RAM only) | Required (disk) |
| Complexity | Simple | Complex |
| Performance | Consistent | Variable |
| Configuration | Straightforward | Many tunables |

For systems with fast NVMe, zram + swapfile is simpler and equally effective.

#### Compression Algorithm: zstd

```
Algorithms compared (16GB test):

| Algorithm | Ratio | Compress Speed | Decompress Speed |
|-----------|-------|----------------|------------------|
| lzo       | 2.5x  | 550 MB/s       | 850 MB/s         |
| lz4       | 2.2x  | 750 MB/s       | 3500 MB/s        |
| zstd      | 3.5x  | 450 MB/s       | 1200 MB/s        |
```

zstd offers the best compression ratio with acceptable speed. For 8GB zram, effective capacity is ~28-32GB.

### 3. Tiered Swap Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SWAP PRIORITY CHAIN                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Priority 100: zram (/dev/zram0)                          │
│   ├── Size: 8GB                                            │
│   ├── Effective: ~32GB (4x compression)                    │
│   ├── Speed: RAM-speed (ns latency)                        │
│   └── Used: FIRST (highest priority)                       │
│                                                             │
│   Priority 10: NVMe (/swapfile)                            │
│   ├── Size: 64GB                                           │
│   ├── Effective: 64GB (no compression)                     │
│   ├── Speed: NVMe-speed (~100μs latency)                   │
│   └── Used: OVERFLOW ONLY                                  │
│                                                             │
│   Total Capacity: ~96GB                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### Why This Order?

1. **zram first**: Near-RAM speed, reduces actual I/O
2. **NVMe backup**: Large capacity for extreme scenarios
3. **NVMe wear**: Minimal (zram handles 95% of swap)

### 4. systemd-oomd (PSI-based)

#### PSI (Pressure Stall Information)

```
$ cat /proc/pressure/memory
some avg10=0.00 avg60=0.00 avg300=0.00 total=123456
full avg10=0.00 avg60=0.00 avg300=0.00 total=12345
```

- **some**: At least one task stalled
- **full**: All tasks stalled
- **avg10/60/300**: 10s/60s/5min averages

systemd-oomd uses PSI to detect memory pressure before OOM.

#### Configuration Rationale

```ini
SwapUsedLimit=80%           # Don't wait until swap is full
DefaultMemoryPressureLimit=60%  # React to sustained pressure
DefaultMemoryPressureDurationSec=20s  # Avoid killing on spikes
```

### 5. earlyoom

#### Why Both oomd AND earlyoom?

| Feature | systemd-oomd | earlyoom |
|---------|--------------|----------|
| Trigger | PSI-based | Percentage-based |
| Scope | Per-cgroup | System-wide |
| Kill selection | Cgroup OOM score | Process OOM score + regex |
| Complexity | Higher | Simpler |

They complement each other:
- oomd handles cgroup-level pressure
- earlyoom handles system-wide emergencies with configurable preferences

#### Kill Preferences

```bash
--prefer '^(firefox|chrome|chromium|brave|electron|slack|discord|teams)'
--avoid '^(gnome-shell|kwin|plasmashell|Xorg|Xwayland|systemd|sshd|pipewire)'
```

Browsers are memory hogs with internal recovery (tab restore). Desktop environment loss = session lost.

### 6. User Session Limits

#### MemoryHigh vs MemoryMax

```
MemoryHigh=14G (soft limit)
├── Triggers: cgroup throttling
├── Behavior: Slow down + aggressive swap
└── Result: No kill, graceful degradation

MemoryMax=15G (hard limit)
├── Triggers: cgroup OOM
├── Behavior: Kill processes in cgroup
└── Result: Contained damage (not system-wide)
```

#### Why 14G/15G for 16GB system?

```
Total RAM: 16GB
├── Kernel reserved: ~500MB
├── Desktop environment: ~1.5GB
└── User limit: 14-15GB
```

This ensures system services always have memory.

### 7. Firefox Tab Unloading

#### Default Behavior (Problematic)

```javascript
browser.low_commit_space_threshold_mb = 200  // Only 200MB left!
browser.low_commit_space_threshold_percent = 5
```

Firefox waits until near-OOM to unload tabs. By then, system is already struggling.

#### Optimized Settings

```javascript
browser.low_commit_space_threshold_mb = 4000  // 4GB remaining
browser.low_commit_space_threshold_percent = 25
dom.ipc.processCount = 4  // Fewer processes = less overhead
```

Proactive unloading prevents pressure buildup.

#### Tab Unload Priority

Firefox uses LRU (Least Recently Used) with exceptions:
- Active tab: Never unloaded
- Playing media: Protected
- WebRTC (video calls): Protected
- Picture-in-Picture: Protected
- Pinned tabs: Deprioritized

### 8. OOMScoreAdjust

#### Score Range

```
-1000 ──────────────── 0 ──────────────── +1000
 │                     │                    │
Never kill         Default            Kill first
```

#### This Optimizer's Values

```
+1000: Electron apps in memory-hogs slice
+500:  (available for user assignment)
0:     Default applications
-500:  VS Code, IDEs (work preservation)
-900:  Desktop environment
-1000: (reserved for critical system processes)
```

## Memory Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MEMORY FLOW                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Application requests memory                                        │
│           │                                                         │
│           ▼                                                         │
│  ┌─────────────────┐                                               │
│  │   RAM (16GB)    │◄──────────────────────────────────┐           │
│  └────────┬────────┘                                   │           │
│           │ Full?                                       │           │
│           ▼                                             │           │
│  ┌─────────────────┐                                   │           │
│  │   kswapd        │ Reclaim inactive pages            │           │
│  └────────┬────────┘                                   │           │
│           │                                             │           │
│           ▼                                             │           │
│  ┌─────────────────┐    ┌─────────────────────────┐   │           │
│  │   zram (8GB)    │───►│ Decompress on access    │───┘           │
│  │   compressed    │    └─────────────────────────┘               │
│  └────────┬────────┘                                               │
│           │ Full?                                                   │
│           ▼                                                         │
│  ┌─────────────────┐    ┌─────────────────────────┐               │
│  │  NVMe (64GB)    │───►│ Read on access          │───► RAM       │
│  │   swapfile      │    └─────────────────────────┘               │
│  └────────┬────────┘                                               │
│           │ Full?                                                   │
│           ▼                                                         │
│  ┌─────────────────┐                                               │
│  │   earlyoom      │ Kill preferred processes                      │
│  └────────┬────────┘                                               │
│           │ Still full?                                             │
│           ▼                                                         │
│  ┌─────────────────┐                                               │
│  │  systemd-oomd   │ Kill by cgroup                                │
│  └────────┬────────┘                                               │
│           │ Still full?                                             │
│           ▼                                                         │
│  ┌─────────────────┐                                               │
│  │   Kernel OOM    │ Last resort                                   │
│  └─────────────────┘                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Tuning Guide

### For Different RAM Sizes

| RAM | zram | NVMe Swap | MemoryHigh | MemoryMax |
|-----|------|-----------|------------|-----------|
| 8GB | 4GB | 32GB | 6G | 7G |
| 16GB | 8GB | 64GB | 14G | 15G |
| 32GB | 12GB | 64GB | 28G | 30G |
| 64GB | 16GB | 64GB | 56G | 60G |

### For Different Workloads

**Development (many small apps):**
```bash
USER_MEMORY_HIGH="12G"
FIREFOX_THRESHOLD_MB=6000
```

**Data Science (few large apps):**
```bash
USER_MEMORY_HIGH="14G"
VM_SWAPPINESS=100  # Less aggressive
```

**Gaming (single large app):**
```bash
EARLYOOM_ARGS="... --prefer '^(firefox|chrome)' ..."  # Protect game
```

## References

- [Kernel VM Documentation](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html)
- [zram Documentation](https://www.kernel.org/doc/html/latest/admin-guide/blockdev/zram.html)
- [systemd Resource Control](https://www.freedesktop.org/software/systemd/man/systemd.resource-control.html)
- [PSI Documentation](https://www.kernel.org/doc/html/latest/accounting/psi.html)
- [Firefox Tab Unloading](https://firefox-source-docs.mozilla.org/browser/tabunloader.html)
