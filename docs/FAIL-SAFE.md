# 🛡️ Fail-Safe Architecture (v4.0)

This document explains the **fail-safe** approach of memory-optimizer v4 in detail.

---

## 📚 TABLE OF CONTENTS

1. [Philosophy](#philosophy)
2. [Anomaly Detection](#anomaly-detection)
3. [Confidence Levels](#confidence-levels)
4. [AI-Ready Reports](#ai-ready-reports)
5. [Bootloader Detection](#bootloader-detection)
6. [Operation Flow](#operation-flow)

---

## Philosophy

### Core Principles

```
1. UNKNOWN = STOP
   - If an unrecognized configuration exists, don't blindly continue
   - Generate detailed report, present to user

2. MAKE NO ASSUMPTIONS
   - Don't say "probably this"
   - Either know for certain, or say "I don't know"

3. AI-READY OUTPUT
   - Make reports copy-paste ready for Claude/ChatGPT
   - Include all context: what was expected, what was found, what couldn't be done
```

### Why Is This Necessary?

**Scenario: Fedora 45 + Mixed Bootloader**

```
❌ BAD SCENARIO (v3 and earlier scripts):

1. Script executed
2. GRUB evidence: 2, systemd-boot evidence: 3
3. Script: "Highest score is systemd-boot, continuing"
4. /etc/kernel/cmdline written
5. But system actually boots from GRUB!
6. Hibernate doesn't work after reboot
7. User debugs for hours
8. Root cause unclear

✅ GOOD SCENARIO (v4):

1. Script executed
2. GRUB evidence: 2, systemd-boot evidence: 3
3. Script: "ANOMALY! Multiple bootloader evidence found"
4. Script: "Kernel param addition SKIPPED"
5. Detailed report generated
6. User sends report to AI
7. AI: "Check bootctl status output, find active bootloader"
8. Problem solved in 5 minutes
```

---

## Anomaly Detection

### Anomaly Structure

Each anomaly contains the following information:

```json
{
  "timestamp": "2025-01-04T21:45:00+01:00",
  "severity": "CRITICAL | WARNING | INFO",
  "component": "bootloader | zram | hibernate | init_system | ...",
  "expected": "What was expected",
  "found": "What was found",
  "impact": "What couldn't be done because of this",
  "suggestion": "What the user should do"
}
```

### Detected Anomalies

| Component | Severity | Trigger | Impact |
|-----------|----------|---------|--------|
| `bootloader` | CRITICAL | No bootloader detected | Kernel params cannot be added |
| `bootloader` | WARNING | Multiple bootloader evidence | Risk of writing to wrong location |
| `bootloader` | WARNING | Weak detection (≤1 evidence) | Verification required |
| `boot_space` | CRITICAL | /boot < 150MB | initramfs cannot be generated |
| `init_system` | CRITICAL | dracut/initramfs-tools missing | Resume module cannot be added |
| `zram_install` | WARNING | zram-generator installation failed | zram won't work |
| `btrfs_swapfile` | WARNING | btrfs mkswapfile failed | Swapfile not created |
| `resume_offset` | CRITICAL | Offset calculation failed | Hibernate won't work |
| `fedora_version` | INFO | Fedora > 42 | Untested version |
| `distro` | WARNING | apt detected | Debian/Ubuntu, compatibility issues |
| `gpu_driver` | WARNING | kmod-nvidia (static) | Kernel update risk |

### Code Example

```bash
add_anomaly() {
    local severity="$1"      # CRITICAL, WARNING, INFO
    local component="$2"     # bootloader, zram, etc.
    local expected="$3"      # What was expected
    local found="$4"         # What was found
    local impact="$5"        # What couldn't be done
    local suggestion="$6"    # Suggestion
    
    ANOMALIES+=("$(cat << EOF
{
  "severity": "$severity",
  "component": "$component",
  "expected": "$expected",
  "found": "$found",
  "impact": "$impact",
  "suggestion": "$suggestion"
}
EOF
)")
    
    ((ANOMALY_COUNT++))
    [[ "$severity" == "CRITICAL" ]] && CRITICAL_ANOMALY=true
}
```

---

## Confidence Levels

### Definition

```bash
BOOTLOADER_CONFIDENCE = "HIGH" | "MEDIUM" | "LOW" | "NONE"
```

### Decision Matrix

| Confidence | Evidence | Script Behavior |
|------------|----------|-----------------|
| **HIGH** | ≥3 points, clear winner | ✅ Operation proceeds |
| **MEDIUM** | 2 points | ⚠️ Operation proceeds, warning issued |
| **LOW** | 1 point or ambiguous | ⚠️ User is asked |
| **NONE** | 0 points | ❌ Operation SKIPPED |

### Evidence System

Evidence is collected for each bootloader:

```bash
# GRUB Evidence
[[ -f /etc/default/grub ]]                    → +1
[[ -d /boot/grub2 ]]                          → +1
[[ -f /boot/efi/EFI/fedora/grub.cfg ]]       → +1
grubby command (not sdubby)                   → +1

# systemd-boot Evidence
[[ -d /boot/loader/entries ]]                 → +1
[[ -d /boot/efi/loader/entries ]]             → +1
[[ -f /etc/kernel/cmdline ]]                  → +1
bootctl status confirms systemd-boot          → +2
grubby is symlink to sdubby                   → +1

# UKI Evidence
/boot/efi/EFI/Linux/*.efi exists              → +2
```

### Ambiguity Handling

```bash
if [[ $((max_evidence - second_place)) -le 1 ]] && [[ $second_place -gt 0 ]]; then
    BOOTLOADER_CONFIDENCE="LOW"
    
    add_anomaly "WARNING" "bootloader" \
        "Single bootloader" \
        "Multiple bootloader evidence found" \
        "Risk of writing to wrong bootloader" \
        "Manually verify active bootloader"
fi
```

---

## AI-Ready Reports

### Report Location

```
/root/memory-optimizer-reports/diagnostic-YYYYMMDD-HHMMSS.txt
/root/hibernate-reports/diagnostic-YYYYMMDD-HHMMSS.txt
```

### Report Structure

```
═══════════════════════════════════════════════════════════════════════════════
  MEMORY OPTIMIZER v4.0 - DIAGNOSTIC REPORT
  Send this report to your AI assistant to receive a custom solution.
═══════════════════════════════════════════════════════════════════════════════

[SYSTEM SNAPSHOT]
Date: 2025-01-04T21:45:00+01:00
Hostname: mypc
Kernel: 6.17.13-200.fc42.x86_64
Architecture: x86_64
...

[DETECTED CONFIGURATION]
Bootloader Type: systemd-boot
Bootloader Confidence: MEDIUM
...

[ANOMALIES DETECTED: 2]
{ "severity": "WARNING", "component": "bootloader", ... }
---
{ "severity": "INFO", "component": "fedora_version", ... }

[SKIPPED OPERATIONS: 1]
zswap kernel param | Bootloader confidence low | bootloader_confidence

[SUCCESSFUL OPERATIONS: 4]
✓ Kernel params: sysctl.d config written
✓ zram config: 16G (zstd)
...

[RAW SYSTEM DATA]
--- /proc/cmdline ---
BOOT_IMAGE=... root=UUID=xxx rhgb quiet

--- swapon --show ---
NAME       TYPE SIZE USED PRIO
/swapfile  file  32G   0B   10

--- Available commands ---
  ✓ grubby: /usr/sbin/grubby
  ✓ bootctl: /usr/bin/bootctl
  ...

═══════════════════════════════════════════════════════════════════════════════
[AI PROMPT]
Send this report to your AI assistant as follows:

"I ran memory-optimizer script on my Fedora system and anomalies
were detected. Please analyze the diagnostic report below and:

1. Explain what the detected anomalies mean
2. Show how to manually perform the skipped operations
3. Provide optimized commands specific to my system

[PASTE REPORT HERE]"
═══════════════════════════════════════════════════════════════════════════════
```

### Using the Report

```bash
# Copy (with xclip)
cat /root/memory-optimizer-reports/diagnostic-*.txt | xclip -selection clipboard

# Copy (with xsel)
cat /root/memory-optimizer-reports/diagnostic-*.txt | xsel --clipboard

# View in terminal
cat /root/memory-optimizer-reports/diagnostic-*.txt
```

---

## Bootloader Detection

### Detection Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    BOOTLOADER DETECTION                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Evidence Collection                                         │
│     ├── GRUB files & commands                                   │
│     ├── systemd-boot files & bootctl                            │
│     └── UKI .efi files                                          │
│                                                                 │
│  2. Scoring                                                     │
│     ├── GRUB: X points                                          │
│     ├── systemd-boot: Y points                                  │
│     └── UKI: Z points                                           │
│                                                                 │
│  3. Decision                                                    │
│     ├── max_evidence == 0 → CONFIDENCE=NONE                     │
│     ├── max_evidence <= 1 → CONFIDENCE=LOW                      │
│     ├── ambiguous (max - second <= 1) → CONFIDENCE=LOW          │
│     ├── max_evidence >= 3 → CONFIDENCE=HIGH                     │
│     └── else → CONFIDENCE=MEDIUM                                │
│                                                                 │
│  4. Action                                                      │
│     ├── HIGH/MEDIUM → Proceed with operation                    │
│     ├── LOW → Ask user confirmation                             │
│     └── NONE → Skip operation, generate report                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Bootloader-Specific Operations

| Bootloader | Kernel Param Method | Config File |
|------------|---------------------|-------------|
| GRUB | `grubby --update-kernel=ALL --args="..."` | /etc/default/grub |
| systemd-boot | `/etc/kernel/cmdline` + `kernel-install add-all` | /etc/kernel/cmdline |
| UKI | `/etc/kernel/cmdline` + UKI rebuild | /etc/kernel/cmdline |
| Unknown | SKIP + manual instructions | N/A |

---

## Operation Flow

### Install Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    INSTALLATION FLOW                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Pre-flight Checks                                           │
│     ├── detect_bootloader_safe()                                │
│     ├── detect_init_system_safe()                               │
│     ├── detect_package_manager_safe()                           │
│     ├── detect_zram_backend_safe()                              │
│     └── detect_ram_and_configure()                              │
│                                                                 │
│  2. Anomaly Review                                              │
│     ├── CRITICAL_ANOMALY? → Ask confirmation                    │
│     └── No anomalies? → Proceed                                 │
│                                                                 │
│  3. Backup                                                      │
│     └── /root/memory-backup-YYYYMMDD-HHMMSS/                    │
│                                                                 │
│  4. Safe Operations                                             │
│     ├── configure_kernel_params_safe()    → Always works        │
│     ├── configure_zram_safe()             → May skip            │
│     ├── configure_swapfile_safe()         → May skip            │
│     ├── configure_user_limits_safe()      → Always works        │
│     ├── disable_kill_mechanisms_safe()    → Always works        │
│     └── disable_zswap_safe()              → May skip            │
│                                                                 │
│  5. Summary                                                     │
│     ├── Generate diagnostic report                              │
│     ├── Show successful operations                              │
│     ├── Show skipped operations                                 │
│     └── Offer reboot                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Skip Logic

```bash
# Inside each safe operation:

some_operation_safe() {
    # Prerequisite check
    if [[ -z "$REQUIRED_COMPONENT" ]]; then
        add_skipped_operation "Operation name" \
            "Required component not detected" \
            "component_name"
        return 1  # Skip
    fi
    
    # Confidence check
    if [[ "$BOOTLOADER_CONFIDENCE" == "NONE" ]]; then
        add_skipped_operation "Operation name" \
            "Bootloader not detected" \
            "bootloader_detection"
        return 1  # Skip
    fi
    
    # Low confidence: ask user
    if [[ "$BOOTLOADER_CONFIDENCE" == "LOW" ]]; then
        read -r -p "Continue? (y/N) " response
        [[ ! "$response" =~ ^[Yy] ]] && {
            add_skipped_operation "Operation name" \
                "User declined (LOW confidence)" \
                "user_confirmation"
            return 1  # Skip
        }
    fi
    
    # Proceed with actual operation
    ...
    
    add_success "Operation name" "Details"
}
```

---

## Comparison: v3 vs v4

| Feature | v3 | v4 |
|---------|-----|-----|
| Unknown bootloader | Makes assumptions | STOPS, reports |
| Evidence system | Basic | 4-level confidence |
| Error handling | Continues | Anomaly record + skip |
| User notification | Log message | AI-ready report |
| Ambiguous situation | First match | Asks user |
| Report format | None | JSON + human-readable |

---

## Best Practices

### When Using the Script

1. **Run `--diagnose` first**
   ```bash
   ./memory-optimizer-v4.sh --diagnose
   ```

2. **Review anomalies**
   - CRITICAL → Fix or accept risk
   - WARNING → Investigate
   - INFO → Informational

3. **Save the report**
   ```bash
   cp /root/memory-optimizer-reports/diagnostic-*.txt ~/
   ```

4. **Get help from AI**
   - Paste the report
   - Request custom commands

### When Developing

1. **When adding new anomaly:**
   ```bash
   add_anomaly "SEVERITY" "component" \
       "Expected behavior" \
       "What was found" \
       "Impact on system" \
       "User action suggestion"
   ```

2. **When adding skip logic:**
   ```bash
   add_skipped_operation "Operation" "Reason" "Dependency"
   ```

3. **Always think about fallback:**
   - Primary method fails → try secondary
   - Secondary fails → skip + report
   - Never crash

---

## FAQ

### Q: Why can I continue with CRITICAL anomaly?

A: Users can take their own risk. The script warns but doesn't block. Some operations can still work (e.g., sysctl settings work independently of bootloader).

### Q: Where is the report saved?

A: `/root/memory-optimizer-reports/` or `/root/hibernate-reports/`

### Q: Can a report be generated without anomalies?

A: Yes, a report is generated after every installation. If there are no anomalies, only successful operations are listed.

### Q: What does LOW confidence mean?

A: The script made a guess but isn't certain. It asks the user and won't proceed without confirmation.

---

**This document is valid for v4.0.0.**
