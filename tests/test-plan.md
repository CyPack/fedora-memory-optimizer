# Universal Memory Optimizer - Test Plan

## Test Environment Matrix

| OS | RAM | Bootloader | Filesystem | Status |
|----|-----|------------|------------|--------|
| Fedora 43 | 32GB | GRUB | ext4 | Primary |
| Fedora 43 | 16GB | systemd-boot | btrfs | Secondary |
| Ubuntu 24.04 | 8GB | GRUB | ext4 | Secondary |
| Debian 12 | 4GB | GRUB | xfs | Edge case |
| Arch | 64GB | systemd-boot | ext4 | Edge case |

---

## Test Categories

### TC1: Fresh Installation
**Preconditions:**
- Clean system, no previous memory optimizer
- No existing ZRAM configuration
- No existing swapfile

**Steps:**
1. Run `./scripts/memory-optimizer.sh --dry-run`
2. Verify dry-run output shows correct sizes
3. Run `./scripts/memory-optimizer.sh`
4. Confirm installation
5. Reboot
6. Run `memory-optimizer-verify`

**Expected Results:**
- [ ] ZRAM active with correct size (RAM/2)
- [ ] Swapfile exists with correct size (ZRAM/2)
- [ ] Sysctl values correct
- [ ] ZSWAP disabled
- [ ] Backup created

---

### TC2: Existing ZRAM Configuration
**Preconditions:**
- System has existing ZRAM (e.g., Fedora default)

**Steps:**
1. Note existing ZRAM size: `zramctl`
2. Run optimizer
3. Verify ZRAM reconfigured to new size
4. Verify old config backed up

**Expected Results:**
- [ ] Old ZRAM config in backup
- [ ] New ZRAM size = RAM/2
- [ ] Compression algorithm = zstd

---

### TC3: Existing Swapfile
**Preconditions:**
- System has existing /swapfile with different size

**Steps:**
1. Note existing swapfile size
2. Run optimizer
3. Verify swapfile resized or preserved (if hibernate)

**Expected Results:**
- [ ] Swapfile replaced if no hibernate
- [ ] Swapfile preserved if hibernate configured
- [ ] fstab updated correctly

---

### TC4: Hibernate Protection
**Preconditions:**
- System configured for hibernate
- Existing swapfile >= RAM size
- `resume=` in kernel cmdline

**Steps:**
1. Run optimizer (without --force)
2. Verify hibernate swapfile NOT modified
3. Run optimizer with --force
4. Verify swapfile replaced (with warning)

**Expected Results:**
- [ ] Without --force: swapfile preserved
- [ ] Warning about hibernate displayed
- [ ] With --force: swapfile replaced

---

### TC5: Btrfs Filesystem
**Preconditions:**
- Root filesystem is btrfs

**Steps:**
1. Run optimizer
2. Check swapfile attributes: `lsattr /swapfile`
3. Verify NODATACOW set

**Expected Results:**
- [ ] Swapfile created successfully
- [ ] `chattr +C` applied (NODATACOW)
- [ ] No compression on swapfile

---

### TC6: systemd-boot Bootloader
**Preconditions:**
- System uses systemd-boot (not GRUB)

**Steps:**
1. Run optimizer
2. Check `/etc/kernel/cmdline` for zswap.enabled=0
3. Verify bootloader detection correct

**Expected Results:**
- [ ] Bootloader detected as systemd-boot
- [ ] ZSWAP disabled via /etc/kernel/cmdline
- [ ] kernel-install executed

---

### TC7: Rollback
**Preconditions:**
- Optimizer previously installed
- Backup exists

**Steps:**
1. Run `./scripts/memory-optimizer.sh --list-backups`
2. Run `./scripts/memory-optimizer.sh --rollback <path>`
3. Reboot
4. Verify system returned to previous state

**Expected Results:**
- [ ] Backups listed correctly
- [ ] Files restored from backup
- [ ] sysctl values restored
- [ ] ZRAM config restored or removed

---

### TC8: Idempotency
**Steps:**
1. Run optimizer once
2. Note all configurations
3. Run optimizer again
4. Compare configurations

**Expected Results:**
- [ ] No duplicate fstab entries
- [ ] Same ZRAM size
- [ ] Same sysctl values
- [ ] New backup created

---

### TC9: Low RAM System (4GB)
**Steps:**
1. Test on 4GB RAM system
2. Verify minimum sizes applied

**Expected Results:**
- [ ] ZRAM = 2GB (minimum viable)
- [ ] Swapfile = 1GB (minimum viable)
- [ ] System remains stable

---

### TC10: High RAM System (64GB+)
**Steps:**
1. Test on 64GB+ RAM system
2. Verify maximum sizes respected

**Expected Results:**
- [ ] ZRAM = 32GB (capped)
- [ ] Swapfile = 16GB
- [ ] No memory waste

---

## Verification Commands

```bash
# Full verification
memory-optimizer-verify

# Individual checks
zramctl
swapon --show
sysctl vm.swappiness vm.page-cluster vm.vfs_cache_pressure
cat /sys/module/zswap/parameters/enabled
cat /proc/pressure/memory
free -h
```

## Stress Testing

```bash
# Memory stress test (requires stress-ng)
stress-ng --vm 2 --vm-bytes 75% --timeout 60s

# Monitor during stress
watch -n 1 'free -h; echo "---"; zramctl; echo "---"; cat /proc/pressure/memory'

# Check for OOM kills after
journalctl -k | grep -i "killed process"
```

## Regression Checklist

After any code change:
- [ ] TC1 passes (fresh install)
- [ ] TC4 passes (hibernate protection)
- [ ] TC9 passes (rollback)
- [ ] TC10 passes (idempotency)

## Known Issues

| Issue | Workaround | Status |
|-------|------------|--------|
| UKI requires manual rebuild | Display warning message | Documented |
| btrfs chattr may fail on non-empty file | Delete and recreate | Handled |
| Some distros lack zram-generator | Auto-install | Handled |
