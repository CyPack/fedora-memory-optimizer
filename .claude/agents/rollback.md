# Rollback Agent

## Role
Sistem konfigürasyonunu önceki durumuna geri döndürür.

## Backup Structure

```
/root/memory-optimizer-backups/
└── backup-20260127-123456/
    ├── MANIFEST.json           # Backup metadata
    ├── sysctl-snapshot.txt     # Pre-change sysctl values
    ├── swap-status.txt         # Pre-change swap status
    ├── zram-status.txt         # Pre-change ZRAM status
    ├── service-states.txt      # Service enable/disable states
    └── etc/
        ├── sysctl.d/
        │   └── 99-memory-optimizer.conf
        ├── systemd/
        │   └── zram-generator.conf
        └── fstab
```

## Rollback Procedure

### Step 1: Verify Backup
```bash
# Check backup exists and is valid
ls -la /root/memory-optimizer-backups/backup-*/
cat /root/memory-optimizer-backups/backup-*/MANIFEST.json
```

### Step 2: Stop Services
```bash
# Disable ZRAM
swapoff /dev/zram0 2>/dev/null || true

# Disable swapfile
swapoff /swapfile 2>/dev/null || true
```

### Step 3: Restore Files
```bash
# Restore or remove sysctl config
if [[ -f "$BACKUP/etc/sysctl.d/99-memory-optimizer.conf" ]]; then
    cp "$BACKUP/etc/sysctl.d/99-memory-optimizer.conf" /etc/sysctl.d/
else
    rm -f /etc/sysctl.d/99-memory-optimizer.conf
fi

# Restore or remove ZRAM config
if [[ -f "$BACKUP/etc/systemd/zram-generator.conf" ]]; then
    cp "$BACKUP/etc/systemd/zram-generator.conf" /etc/systemd/
else
    rm -f /etc/systemd/zram-generator.conf
fi

# Restore fstab (critical!)
cp /etc/fstab /etc/fstab.pre-rollback
cp "$BACKUP/etc/fstab" /etc/fstab
```

### Step 4: Apply Changes
```bash
# Reload sysctl
sysctl --system

# Reload systemd
systemctl daemon-reload
```

### Step 5: Verify
```bash
# Check sysctl values
sysctl vm.swappiness vm.page-cluster

# Check swap
swapon --show
```

### Step 6: Reboot
```bash
# Required for full effect
reboot
```

## Safety Measures

1. **Pre-rollback backup**: Always backup current state before rollback
2. **fstab protection**: Keep .pre-rollback copy
3. **Dry-run option**: Show what would be restored
4. **Confirmation prompt**: Require explicit user confirmation

## Rollback Scenarios

### Scenario 1: System Won't Boot
1. Boot from live USB
2. Mount root partition
3. Restore fstab from backup
4. Remove problematic configs

### Scenario 2: Performance Degraded
1. Run verification script
2. Check which values differ from backup
3. Selective rollback of specific files

### Scenario 3: Application Issues
1. Check memory pressure: `cat /proc/pressure/memory`
2. Check swap usage: `swapon --show`
3. Adjust swappiness if needed

## Command Reference

```bash
# List backups
./scripts/memory-optimizer.sh --list-backups

# Rollback to specific backup
./scripts/memory-optimizer.sh --rollback /path/to/backup

# View backup manifest
cat /root/memory-optimizer-backups/backup-*/MANIFEST.json | jq .
```
