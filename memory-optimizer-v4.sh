#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#
#  ███████╗███████╗██████╗  ██████╗ ██████╗  █████╗ 
#  ██╔════╝██╔════╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗
#  █████╗  █████╗  ██║  ██║██║   ██║██████╔╝███████║
#  ██╔══╝  ██╔══╝  ██║  ██║██║   ██║██╔══██╗██╔══██║
#  ██║     ███████╗██████╔╝╚██████╔╝██║  ██║██║  ██║
#  ╚═╝     ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
#  
#  MEMORY OPTIMIZER v4.0 - FAIL-SAFE EDITION
#  ═══════════════════════════════════════════════════════════════════════════
#  
#  ✅ Anomaly Detection - Stops on unknown situations
#  ✅ AI-Ready Diagnostic Reports - Can be sent to AI agents
#  ✅ No Hallucination - Makes no assumptions, admits uncertainty
#  ✅ Safe Defaults - Skips operation when uncertain
#
#═══════════════════════════════════════════════════════════════════════════════
#
#  PHILOSOPHY:
#  
#  1. UNKNOWN = STOP
#     - If unrecognized configuration exists, do not blindly continue
#     - Generate detailed report, present to user
#  
#  2. MAKE NO ASSUMPTIONS
#     - Do not say "probably this"
#     - Ya kesin bil, ya da "bilmiyorum" de
#  
#  3. AI-READY OUTPUT
#     - Make report copy-paste ready for Claude/ChatGPT
#     - Include all context: what expected, found, could not do
#
#═══════════════════════════════════════════════════════════════════════════════

SCRIPT_VERSION="4.0.0"
SCRIPT_NAME="memory-optimizer-v4"
REPORT_FILE=""

# Error handling - tolerant mode (report, don't crash)
set +e
set +u
set -o pipefail

#───────────────────────────────────────────────────────────────────────────────
# COLORS & LOGGING
#───────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()         { echo -e "[$(date '+%H:%M:%S')] $1"; }
log_info()    { log "${BLUE}ℹ️  $1${NC}"; }
log_success() { log "${GREEN}✅ $1${NC}"; }
log_warning() { log "${YELLOW}⚠️  $1${NC}"; }
log_error()   { log "${RED}❌ $1${NC}"; }
log_header()  { 
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    log "${BOLD}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
}

#───────────────────────────────────────────────────────────────────────────────
# ANOMALY TRACKING SYSTEM
#───────────────────────────────────────────────────────────────────────────────

# Arrays to track anomalies and skipped operations
declare -a ANOMALIES=()
declare -a SKIPPED_OPERATIONS=()
declare -a WARNINGS=()
declare -a SUCCESSFUL_OPERATIONS=()

# Counters
ANOMALY_COUNT=0
CRITICAL_ANOMALY=false

# Add an anomaly to the tracking system
add_anomaly() {
    local severity="$1"      # CRITICAL, WARNING, INFO
    local component="$2"     # bootloader, zram, kernel, etc.
    local expected="$3"      # What we expected
    local found="$4"         # What we found
    local impact="$5"        # What couldn't be done because of this
    local suggestion="$6"    # AI-ready suggestion
    
    local timestamp=$(date -Iseconds)
    
    ANOMALIES+=("$(cat << EOF
{
  "timestamp": "$timestamp",
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
    
    if [[ "$severity" == "CRITICAL" ]]; then
        CRITICAL_ANOMALY=true
    fi
    
    # Log to console
    case "$severity" in
        CRITICAL)
            log_error "ANOMALY [$component]: $found (expected: $expected)"
            log_error "  → IMPACT: $impact"
            ;;
        WARNING)
            log_warning "ANOMALY [$component]: $found (expected: $expected)"
            log_warning "  → IMPACT: $impact"
            ;;
        INFO)
            log_info "ANOMALY [$component]: $found"
            ;;
    esac
}

# Track skipped operations
add_skipped_operation() {
    local operation="$1"
    local reason="$2"
    local dependency="$3"
    
    SKIPPED_OPERATIONS+=("$(cat << EOF
{
  "operation": "$operation",
  "reason": "$reason",
  "blocked_by": "$dependency"
}
EOF
)")
    
    log_warning "SKIPPED: $operation"
    log_warning "  → REASON: $reason"
}

# Track successful operations
add_success() {
    local operation="$1"
    local details="$2"
    
    SUCCESSFUL_OPERATIONS+=("$operation: $details")
    log_success "$operation: $details"
}

#───────────────────────────────────────────────────────────────────────────────
# AI-READY DIAGNOSTIC REPORT GENERATOR
#───────────────────────────────────────────────────────────────────────────────

generate_diagnostic_report() {
    local report_dir="/root/memory-optimizer-reports"
    mkdir -p "$report_dir"
    
    REPORT_FILE="$report_dir/diagnostic-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << 'HEADER'
═══════════════════════════════════════════════════════════════════════════════
  MEMORY OPTIMIZER v4.0 - DIAGNOSTIC REPORT
  Send this report to your AI assistant (Claude, ChatGPT vb.) to receive
  a custom solution for your system.
═══════════════════════════════════════════════════════════════════════════════

HEADER

    # System snapshot
    cat >> "$REPORT_FILE" << EOF
[SYSTEM SNAPSHOT]
═══════════════════════════════════════════════════════════════════════════════
Date: $(date -Iseconds)
Hostname: $(hostname)
Kernel: $(uname -r)
Architecture: $(uname -m)

OS Info:
$(cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION|ID)=" | sed 's/^/  /')

Memory:
$(free -h | sed 's/^/  /')

Disk:
$(df -h / /boot 2>/dev/null | sed 's/^/  /')

Filesystem Type: $(df -T / | tail -1 | awk '{print $2}')

EOF

    # Detected configuration
    cat >> "$REPORT_FILE" << EOF
[DETECTED CONFIGURATION]
═══════════════════════════════════════════════════════════════════════════════
Bootloader Type: ${DETECTED_BOOTLOADER:-"NOT DETECTED"}
Bootloader Detection Method: ${BOOTLOADER_DETECTION_METHOD:-"N/A"}
Bootloader Confidence: ${BOOTLOADER_CONFIDENCE:-"UNKNOWN"}

Init System: ${DETECTED_INIT_SYSTEM:-"NOT DETECTED"}
Package Manager: ${DETECTED_PKG_MANAGER:-"NOT DETECTED"}

zram Backend: ${DETECTED_ZRAM_BACKEND:-"NOT DETECTED"}
zram Status: ${ZRAM_STATUS:-"UNKNOWN"}

Hibernate Status: ${HIBERNATE_STATUS:-"NOT CHECKED"}
Existing Swapfile: ${EXISTING_SWAPFILE:-"NONE"}

EOF

    # Anomalies section
    cat >> "$REPORT_FILE" << EOF
[ANOMALIES DETECTED: $ANOMALY_COUNT]
═══════════════════════════════════════════════════════════════════════════════
EOF

    if [[ $ANOMALY_COUNT -eq 0 ]]; then
        echo "No anomalies detected." >> "$REPORT_FILE"
    else
        for anomaly in "${ANOMALIES[@]}"; do
            echo "$anomaly" >> "$REPORT_FILE"
            echo "---" >> "$REPORT_FILE"
        done
    fi
    
    echo "" >> "$REPORT_FILE"

    # Skipped operations
    cat >> "$REPORT_FILE" << EOF
[SKIPPED OPERATIONS: ${#SKIPPED_OPERATIONS[@]}]
═══════════════════════════════════════════════════════════════════════════════
EOF

    if [[ ${#SKIPPED_OPERATIONS[@]} -eq 0 ]]; then
        echo "No operations were skipped." >> "$REPORT_FILE"
    else
        for skipped in "${SKIPPED_OPERATIONS[@]}"; do
            echo "$skipped" >> "$REPORT_FILE"
            echo "---" >> "$REPORT_FILE"
        done
    fi
    
    echo "" >> "$REPORT_FILE"

    # Successful operations
    cat >> "$REPORT_FILE" << EOF
[SUCCESSFUL OPERATIONS: ${#SUCCESSFUL_OPERATIONS[@]}]
═══════════════════════════════════════════════════════════════════════════════
EOF

    if [[ ${#SUCCESSFUL_OPERATIONS[@]} -eq 0 ]]; then
        echo "No operations were completed successfully." >> "$REPORT_FILE"
    else
        for success in "${SUCCESSFUL_OPERATIONS[@]}"; do
            echo "✓ $success" >> "$REPORT_FILE"
        done
    fi
    
    echo "" >> "$REPORT_FILE"

    # Raw system data for AI analysis
    cat >> "$REPORT_FILE" << 'EOF'
[RAW SYSTEM DATA - FOR AI ANALYSIS]
═══════════════════════════════════════════════════════════════════════════════

--- /proc/cmdline ---
EOF
    cat /proc/cmdline >> "$REPORT_FILE" 2>/dev/null || echo "Could not read" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- swapon --show ---
EOF
    swapon --show >> "$REPORT_FILE" 2>/dev/null || echo "Could not read" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- zramctl ---
EOF
    zramctl >> "$REPORT_FILE" 2>/dev/null || echo "No zram or could not read" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- /etc/fstab (swap entries) ---
EOF
    grep -E "swap|swapfile" /etc/fstab >> "$REPORT_FILE" 2>/dev/null || echo "Swap entry yok" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- Bootloader files ---
EOF
    echo "GRUB:" >> "$REPORT_FILE"
    ls -la /etc/default/grub /boot/grub2 /boot/efi/EFI/fedora 2>/dev/null | sed 's/^/  /' >> "$REPORT_FILE" || echo "  GRUB files not found" >> "$REPORT_FILE"
    
    echo "systemd-boot:" >> "$REPORT_FILE"
    ls -la /boot/loader /boot/efi/loader /etc/kernel/cmdline 2>/dev/null | sed 's/^/  /' >> "$REPORT_FILE" || echo "  systemd-boot files not found" >> "$REPORT_FILE"
    
    echo "UKI:" >> "$REPORT_FILE"
    ls -la /boot/efi/EFI/Linux 2>/dev/null | sed 's/^/  /' >> "$REPORT_FILE" || echo "  UKI files not found" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- Available commands ---
EOF
    for cmd in grubby grub2-mkconfig bootctl sdubby kernel-install dracut update-initramfs dnf dnf5 apt rpm dpkg; do
        if command -v "$cmd" &>/dev/null; then
            echo "  ✓ $cmd: $(which $cmd)" >> "$REPORT_FILE"
        else
            echo "  ✗ $cmd: not found" >> "$REPORT_FILE"
        fi
    done
    
    cat >> "$REPORT_FILE" << 'EOF'

--- Kernel sysctl (memory related) ---
EOF
    sysctl vm.swappiness vm.page-cluster vm.vfs_cache_pressure vm.min_free_kbytes 2>/dev/null >> "$REPORT_FILE" || echo "Could not read" >> "$REPORT_FILE"
    
    cat >> "$REPORT_FILE" << 'EOF'

--- systemd services ---
EOF
    for svc in earlyoom systemd-oomd zram-setup@zram0; do
        echo -n "  $svc: " >> "$REPORT_FILE"
        systemctl is-active "$svc" 2>/dev/null >> "$REPORT_FILE" || echo "unknown" >> "$REPORT_FILE"
    done

    # AI prompt suggestion
    cat >> "$REPORT_FILE" << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
[AI ASSISTANT PROMPT]
═══════════════════════════════════════════════════════════════════════════════

Send this report to your AI assistant with the following prompt:

---
I ran memory-optimizer script on my Fedora system and some anomalies
were detected. Please analyze the diagnostic report below and:

1. Explain what the detected anomalies mean
2. Show how to manually perform the skipped operations
3. Provide optimized commands specific to my system

[PASTE REPORT HERE]
---

EOF

    echo "═══════════════════════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "Report generated: $(date -Iseconds)" >> "$REPORT_FILE"
    echo "Script version: $SCRIPT_VERSION" >> "$REPORT_FILE"
}

#───────────────────────────────────────────────────────────────────────────────
# SAFE DETECTION FUNCTIONS (WITH CONFIDENCE LEVELS)
#───────────────────────────────────────────────────────────────────────────────

DETECTED_BOOTLOADER=""
BOOTLOADER_DETECTION_METHOD=""
BOOTLOADER_CONFIDENCE=""  # HIGH, MEDIUM, LOW, NONE

detect_bootloader_safe() {
    log_header "Bootloader Detection (Safe Mode)"
    
    DETECTED_BOOTLOADER=""
    BOOTLOADER_DETECTION_METHOD=""
    BOOTLOADER_CONFIDENCE="NONE"
    
    local evidence_grub=0
    local evidence_sdboot=0
    local evidence_uki=0
    local detection_notes=()
    
    # Evidence collection for GRUB
    if [[ -f /etc/default/grub ]]; then
        ((evidence_grub++))
        detection_notes+=("GRUB: /etc/default/grub exists")
    fi
    if [[ -d /boot/grub2 ]]; then
        ((evidence_grub++))
        detection_notes+=("GRUB: /boot/grub2 directory exists")
    fi
    if [[ -d /boot/efi/EFI/fedora ]] && [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
        ((evidence_grub++))
        detection_notes+=("GRUB: grub.cfg in EFI partition")
    fi
    if command -v grubby &>/dev/null; then
        local grubby_target=$(readlink -f "$(which grubby)" 2>/dev/null || echo "grubby")
        if [[ "$grubby_target" != *"sdubby"* ]]; then
            ((evidence_grub++))
            detection_notes+=("GRUB: grubby command available (not sdubby)")
        fi
    fi
    
    # Evidence collection for systemd-boot
    if [[ -d /boot/loader/entries ]] || [[ -d /boot/efi/loader/entries ]]; then
        ((evidence_sdboot++))
        detection_notes+=("SD-BOOT: loader/entries directory exists")
    fi
    if [[ -f /etc/kernel/cmdline ]]; then
        ((evidence_sdboot++))
        detection_notes+=("SD-BOOT: /etc/kernel/cmdline exists")
    fi
    if command -v bootctl &>/dev/null; then
        local bootctl_check=$(bootctl status 2>/dev/null | head -10)
        if echo "$bootctl_check" | grep -qi "systemd-boot"; then
            ((evidence_sdboot+=2))
            detection_notes+=("SD-BOOT: bootctl confirms systemd-boot")
        fi
    fi
    if command -v grubby &>/dev/null; then
        local grubby_target=$(readlink -f "$(which grubby)" 2>/dev/null || echo "")
        if [[ "$grubby_target" == *"sdubby"* ]]; then
            ((evidence_sdboot++))
            detection_notes+=("SD-BOOT: grubby is symlink to sdubby")
        fi
    fi
    
    # Evidence collection for UKI
    if [[ -d /boot/efi/EFI/Linux ]]; then
        if ls /boot/efi/EFI/Linux/*.efi &>/dev/null 2>&1; then
            ((evidence_uki+=2))
            detection_notes+=("UKI: .efi files in /boot/efi/EFI/Linux")
        fi
    fi
    
    # Decision logic
    log_info "Evidence scores: GRUB=$evidence_grub, SD-BOOT=$evidence_sdboot, UKI=$evidence_uki"
    
    for note in "${detection_notes[@]}"; do
        log_info "  $note"
    done
    
    # Determine winner
    local max_evidence=0
    local winner=""
    local second_place=0
    
    if [[ $evidence_grub -gt $max_evidence ]]; then
        second_place=$max_evidence
        max_evidence=$evidence_grub
        winner="grub"
    fi
    if [[ $evidence_sdboot -gt $max_evidence ]]; then
        second_place=$max_evidence
        max_evidence=$evidence_sdboot
        winner="systemd-boot"
    elif [[ $evidence_sdboot -gt $second_place ]]; then
        second_place=$evidence_sdboot
    fi
    if [[ $evidence_uki -gt $max_evidence ]]; then
        second_place=$max_evidence
        max_evidence=$evidence_uki
        winner="uki"
    elif [[ $evidence_uki -gt $second_place ]]; then
        second_place=$evidence_uki
    fi
    
    # Confidence calculation
    if [[ $max_evidence -eq 0 ]]; then
        BOOTLOADER_CONFIDENCE="NONE"
        BOOTLOADER_DETECTION_METHOD="No evidence found"
        
        add_anomaly "CRITICAL" "bootloader" \
            "GRUB, systemd-boot, or UKI" \
            "No bootloader detected" \
            "Kernel parameters cannot be set, hibernate resume may not work" \
            "Please manually specify your bootloader type and check kernel cmdline"
            
    elif [[ $max_evidence -le 1 ]]; then
        BOOTLOADER_CONFIDENCE="LOW"
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_DETECTION_METHOD="Weak evidence ($max_evidence point)"
        
        add_anomaly "WARNING" "bootloader" \
            "Clear bootloader detection" \
            "$winner detected but evidence is weak (score: $max_evidence)" \
            "Kernel parameter changes may not be safe" \
            "Verify bootloader type with 'bootctl status' or 'grubby --info=ALL'"
            
    elif [[ $((max_evidence - second_place)) -le 1 ]] && [[ $second_place -gt 0 ]]; then
        BOOTLOADER_CONFIDENCE="LOW"
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_DETECTION_METHOD="Ambiguous (winner: $max_evidence, runner-up: $second_place)"
        
        add_anomaly "WARNING" "bootloader" \
            "Single bootloader" \
            "Multiple bootloader evidence found (GRUB=$evidence_grub, SD-BOOT=$evidence_sdboot, UKI=$evidence_uki)" \
            "Risk of writing to wrong bootloader" \
            "May be dual-boot or migration. Manually verify active bootloader"
            
    elif [[ $max_evidence -ge 3 ]]; then
        BOOTLOADER_CONFIDENCE="HIGH"
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_DETECTION_METHOD="Strong evidence ($max_evidence points)"
        log_success "Bootloader: $winner (Confidence: HIGH)"
        
    else
        BOOTLOADER_CONFIDENCE="MEDIUM"
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_DETECTION_METHOD="Moderate evidence ($max_evidence points)"
        log_info "Bootloader: $winner (Confidence: MEDIUM)"
    fi
}

DETECTED_INIT_SYSTEM=""
INIT_SYSTEM_CONFIDENCE=""

detect_init_system_safe() {
    log_info "Detecting init system..."
    
    DETECTED_INIT_SYSTEM=""
    INIT_SYSTEM_CONFIDENCE="NONE"
    
    if command -v dracut &>/dev/null; then
        DETECTED_INIT_SYSTEM="dracut"
        
        # Verify dracut is actually functional
        if dracut --help &>/dev/null; then
            INIT_SYSTEM_CONFIDENCE="HIGH"
            log_success "Init system: dracut (functional)"
        else
            INIT_SYSTEM_CONFIDENCE="MEDIUM"
            log_warning "Init system: dracut (command exists but may have issues)"
        fi
        
    elif command -v update-initramfs &>/dev/null; then
        DETECTED_INIT_SYSTEM="initramfs-tools"
        INIT_SYSTEM_CONFIDENCE="HIGH"
        log_success "Init system: initramfs-tools"
        
    else
        add_anomaly "CRITICAL" "init_system" \
            "dracut or update-initramfs" \
            "No initramfs management tool found" \
            "initramfs cannot be regenerated, hibernate resume module cannot be added" \
            "System must have dracut or initramfs-tools installed"
    fi
}

DETECTED_PKG_MANAGER=""

detect_package_manager_safe() {
    log_info "Package manager detection..."
    
    DETECTED_PKG_MANAGER=""
    
    if command -v dnf5 &>/dev/null; then
        DETECTED_PKG_MANAGER="dnf5"
        log_info "Package manager: dnf5"
    elif command -v dnf &>/dev/null; then
        DETECTED_PKG_MANAGER="dnf"
        log_info "Package manager: dnf"
    elif command -v apt &>/dev/null; then
        DETECTED_PKG_MANAGER="apt"
        log_info "Package manager: apt"
        
        add_anomaly "WARNING" "distro" \
            "Fedora/RHEL system" \
            "apt package manager detected (Debian/Ubuntu)" \
            "This script is optimized for Fedora, some features may not work" \
            "A separate script for Ubuntu/Debian is recommended"
    else
        add_anomaly "CRITICAL" "package_manager" \
            "dnf, dnf5, or apt" \
            "No supported package manager found" \
            "Required packages (zram-generator etc.) cannot be installed" \
            "Manually specify package manager"
    fi
}

DETECTED_ZRAM_BACKEND=""
ZRAM_STATUS=""

detect_zram_backend_safe() {
    log_info "Detecting zram backend..."
    
    DETECTED_ZRAM_BACKEND=""
    ZRAM_STATUS="unknown"
    
    local evidence=()
    
    # Check zram-generator
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        evidence+=("config_exists")
    fi
    if [[ -f /usr/lib/systemd/system-generators/zram-generator ]]; then
        evidence+=("generator_exists")
    fi
    if rpm -q zram-generator &>/dev/null 2>&1; then
        evidence+=("rpm_installed")
    fi
    
    # Check if zram is active
    if [[ -b /dev/zram0 ]]; then
        ZRAM_STATUS="active"
        evidence+=("device_active")
    else
        ZRAM_STATUS="inactive"
    fi
    
    # Decision
    if [[ ${#evidence[@]} -ge 2 ]]; then
        DETECTED_ZRAM_BACKEND="zram-generator"
        log_success "zram backend: zram-generator (evidence: ${evidence[*]})"
    elif [[ ${#evidence[@]} -eq 1 ]]; then
        DETECTED_ZRAM_BACKEND="zram-generator"
        log_warning "zram backend: zram-generator (partial evidence: ${evidence[*]})"
        
        add_anomaly "INFO" "zram" \
            "Full zram-generator installation" \
            "zram-generator partially installed (${evidence[*]})" \
            "zram may not work properly" \
            "Reinstall zram-generator: sudo dnf reinstall zram-generator"
    else
        DETECTED_ZRAM_BACKEND="none"
        log_info "zram backend: none (will be installed)"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# HIBERNATE STATUS CHECK
#───────────────────────────────────────────────────────────────────────────────

HIBERNATE_STATUS=""
EXISTING_SWAPFILE=""
EXISTING_SWAPFILE_SIZE_GB=0

check_hibernate_status_safe() {
    log_header "Hibernate Status Check"
    
    HIBERNATE_STATUS="not_configured"
    EXISTING_SWAPFILE=""
    EXISTING_SWAPFILE_SIZE_GB=0
    
    local evidence=()
    
    # Check kernel params
    if grep -q "resume=" /proc/cmdline 2>/dev/null; then
        evidence+=("kernel_resume_param")
    fi
    if grep -q "resume_offset=" /proc/cmdline 2>/dev/null; then
        evidence+=("kernel_offset_param")
    fi
    
    # Check dracut config
    if [[ -f /etc/dracut.conf.d/99-hibernate.conf ]]; then
        evidence+=("dracut_config")
    fi
    
    # Check swapfile
    if [[ -f /swapfile ]]; then
        EXISTING_SWAPFILE="/swapfile"
        local size_bytes=$(stat -c%s /swapfile 2>/dev/null || echo 0)
        EXISTING_SWAPFILE_SIZE_GB=$((size_bytes / 1024 / 1024 / 1024))
        evidence+=("swapfile_exists:${EXISTING_SWAPFILE_SIZE_GB}GB")
    fi
    
    # Decision
    if [[ ${#evidence[@]} -ge 3 ]]; then
        HIBERNATE_STATUS="fully_configured"
        log_success "Hibernate: Tam kurulu (${evidence[*]})"
    elif [[ ${#evidence[@]} -ge 1 ]]; then
        HIBERNATE_STATUS="partially_configured"
        log_warning "Hibernate: Partially installed (${evidence[*]})"
        
        add_anomaly "WARNING" "hibernate" \
            "Full hibernate setup (kernel param + dracut + swapfile)" \
            "Partial installation detected: ${evidence[*]}" \
            "Hibernate may not work properly" \
            "Complete hibernate setup with setup-hibernation-v4.sh"
    else
        HIBERNATE_STATUS="not_configured"
        log_info "Hibernate: Not installed"
    fi
    
    # Protection decision
    if [[ "$HIBERNATE_STATUS" == "fully_configured" ]] || [[ "$HIBERNATE_STATUS" == "partially_configured" ]]; then
        if [[ -n "$EXISTING_SWAPFILE" ]]; then
            log_success "🛡️  Hibernate swapfile will be preserved: $EXISTING_SWAPFILE (${EXISTING_SWAPFILE_SIZE_GB}GB)"
            return 0  # Protected
        fi
    fi
    
    return 1  # Not protected
}

#───────────────────────────────────────────────────────────────────────────────
# RAM DETECTION & CONFIG
#───────────────────────────────────────────────────────────────────────────────

RAM_KB=0
RAM_MB=0
RAM_GB=0
RAM_TIER=0

detect_ram_and_configure() {
    RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    RAM_MB=$((RAM_KB / 1024))
    RAM_GB=$((RAM_KB / 1024 / 1024))
    
    # Tier calculation
    if [[ $RAM_GB -lt 6 ]]; then
        RAM_TIER=4
    elif [[ $RAM_GB -lt 12 ]]; then
        RAM_TIER=8
    elif [[ $RAM_GB -lt 24 ]]; then
        RAM_TIER=16
    elif [[ $RAM_GB -lt 48 ]]; then
        RAM_TIER=32
    else
        RAM_TIER=64
    fi
    
    # Tier-based config
    case $RAM_TIER in
        4)  ZRAM_SIZE_GB=2;  SWAPFILE_SIZE_GB=8;  USER_MEMORY_HIGH="3G"  ;;
        8)  ZRAM_SIZE_GB=4;  SWAPFILE_SIZE_GB=16; USER_MEMORY_HIGH="6G"  ;;
        16) ZRAM_SIZE_GB=8;  SWAPFILE_SIZE_GB=32; USER_MEMORY_HIGH="12G" ;;
        32) ZRAM_SIZE_GB=16; SWAPFILE_SIZE_GB=64; USER_MEMORY_HIGH="24G" ;;
        64) ZRAM_SIZE_GB=32; SWAPFILE_SIZE_GB=64; USER_MEMORY_HIGH="48G" ;;
    esac
    
    # Calculated values
    ZRAM_SIZE="${ZRAM_SIZE_GB}G"
    ZRAM_SIZE_BYTES=$((ZRAM_SIZE_GB * 1024 * 1024 * 1024))
    SWAPFILE_SIZE="${SWAPFILE_SIZE_GB}G"
    
    # Common values
    ZRAM_ALGORITHM="zstd"
    ZRAM_PRIORITY=100
    SWAPFILE_PRIORITY=10
    VM_SWAPPINESS=180
    VM_PAGE_CLUSTER=0
    VM_VFS_CACHE_PRESSURE=50
    VM_MIN_FREE_KB=$((RAM_TIER * 16384))
    [[ $VM_MIN_FREE_KB -lt 65536 ]] && VM_MIN_FREE_KB=65536
    [[ $VM_MIN_FREE_KB -gt 262144 ]] && VM_MIN_FREE_KB=262144
    
    log_success "RAM: ${RAM_GB}GB → Tier: ${RAM_TIER}GB"
}

#───────────────────────────────────────────────────────────────────────────────
# SAFE OPERATION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

configure_kernel_params_safe() {
    log_header "[1/6] Kernel Parametreleri (Safe Mode)"
    
    # This is always safe - just writing to sysctl.d
    cat > /etc/sysctl.d/99-memory-optimizer.conf << EOF
# Memory Optimizer v${SCRIPT_VERSION}
# Generated: $(date -Iseconds)
# Anomalies at generation: $ANOMALY_COUNT

vm.swappiness = $VM_SWAPPINESS
vm.page-cluster = $VM_PAGE_CLUSTER
vm.vfs_cache_pressure = $VM_VFS_CACHE_PRESSURE
vm.min_free_kbytes = $VM_MIN_FREE_KB
vm.watermark_scale_factor = 125
vm.overcommit_memory = 0
vm.panic_on_oom = 0
vm.oom_kill_allocating_task = 0
EOF

    sysctl --system > /dev/null 2>&1 || true
    
    add_success "Kernel params" "sysctl.d config written"
}

configure_zram_safe() {
    log_header "[2/6] zram Configuration (Safe Mode)"
    
    # Check if we can proceed
    if [[ -z "$DETECTED_PKG_MANAGER" ]]; then
        add_skipped_operation "zram installation" \
            "Package manager not detected" \
            "package_manager"
        return 1
    fi
    
    # IDEMPOTENCY: Check if zram-generator is already installed and configured
    local zram_installed=false
    local zram_config_exists=false
    local current_zram_size=""
    
    if rpm -q zram-generator &>/dev/null 2>&1; then
        zram_installed=true
    fi
    
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        zram_config_exists=true
        current_zram_size=$(grep -oP 'zram-size\s*=\s*\K[^\s]+' /etc/systemd/zram-generator.conf 2>/dev/null || echo "unknown")
    fi
    
    if [[ "$zram_installed" == "true" ]] && [[ "$zram_config_exists" == "true" ]]; then
        if [[ "$current_zram_size" == "$ZRAM_SIZE" ]]; then
            log_success "zram-generator already installed and configured ($ZRAM_SIZE)"
            
            # Just ensure zram is active
            if [[ ! -b /dev/zram0 ]]; then
                log_info "zram not active, will be active after reboot"
            fi
            
            add_success "zram config" "Existing config preserved ($ZRAM_SIZE)"
            return 0
        else
            log_info "zram config exists but size differs: $current_zram_size → $ZRAM_SIZE"
        fi
    fi
    
    # Install if needed
    if [[ "$zram_installed" != "true" ]]; then
        log_info "zram-generator kuruluyor..."
        
        case "$DETECTED_PKG_MANAGER" in
            dnf|dnf5)
                $DETECTED_PKG_MANAGER install -y zram-generator 2>/dev/null || {
                    add_anomaly "WARNING" "zram_install" \
                        "zram-generator installation successful" \
                        "zram-generator could not be installed" \
                        "zram swap will not be available" \
                        "Try manual installation: sudo dnf install zram-generator"
                    return 1
                }
                ;;
            apt)
                add_skipped_operation "zram-generator installation" \
                    "apt systems require different package instead of zram-generator" \
                    "distro_compatibility"
                return 1
                ;;
        esac
    fi
    
    # Write config
    cat > /etc/systemd/zram-generator.conf << EOF
# Memory Optimizer v${SCRIPT_VERSION}
# Generated: $(date -Iseconds)

[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = ${ZRAM_ALGORITHM}
swap-priority = ${ZRAM_PRIORITY}
fs-type = swap
EOF

    add_success "zram config" "${ZRAM_SIZE} (${ZRAM_ALGORITHM})"
    
    if [[ "$ZRAM_STATUS" != "active" ]]; then
        log_warning "zram will be active after REBOOT"
    fi
}

configure_swapfile_safe() {
    log_header "[3/6] Swapfile Configuration (Safe Mode)"
    
    local swapfile_path="/swapfile"
    local needed_gb=${SWAPFILE_SIZE_GB}
    
    # Hibernate protection - always preserve hibernate swapfile
    if check_hibernate_status_safe; then
        log_success "🛡️  Preserving hibernate swapfile"
        
        # Just ensure it's active
        if ! swapon --show | grep -q "$swapfile_path"; then
            swapon "$swapfile_path" 2>/dev/null || true
        fi
        
        add_success "Swapfile" "Existing preserved (${EXISTING_SWAPFILE_SIZE_GB}GB)"
        return 0
    fi
    
    # IDEMPOTENCY CHECK: If swapfile exists and size is adequate, keep it
    if [[ -f "$swapfile_path" ]]; then
        local existing_bytes=$(stat -c%s "$swapfile_path" 2>/dev/null || echo 0)
        local existing_gb=$((existing_bytes / 1024 / 1024 / 1024))
        
        if [[ $existing_gb -ge $needed_gb ]]; then
            log_success "Existing swapfile is sufficient: ${existing_gb}GB (required: ${needed_gb}GB)"
            
            # Ensure it's in fstab
            if ! grep -q "$swapfile_path" /etc/fstab 2>/dev/null; then
                echo "$swapfile_path none swap sw,pri=$SWAPFILE_PRIORITY 0 0" >> /etc/fstab
            fi
            
            # Ensure it's active
            if ! swapon --show | grep -q "$swapfile_path"; then
                swapon "$swapfile_path" 2>/dev/null || {
                    mkswap "$swapfile_path" > /dev/null 2>&1
                    swapon "$swapfile_path" 2>/dev/null || true
                }
            fi
            
            add_success "Swapfile" "Existing used (${existing_gb}GB)"
            return 0
        else
            log_warning "Existing swapfile insufficient: ${existing_gb}GB < ${needed_gb}GB"
            echo ""
            read -r -p "Do you want to recreate swapfile? (y/N) " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                log_info "Preserving existing swapfile"
                
                # Ensure active
                if ! swapon --show | grep -q "$swapfile_path"; then
                    swapon "$swapfile_path" 2>/dev/null || true
                fi
                
                add_success "Swapfile" "Existing preserved (user preference))"
                return 0
            fi
        fi
    fi
    
    # Create new swapfile
    local fstype=$(df -T / | tail -1 | awk '{print $2}')
    
    # Disable existing
    if swapon --show | grep -q "$swapfile_path"; then
        swapoff "$swapfile_path" 2>/dev/null || true
    fi
    [[ -f "$swapfile_path" ]] && rm -f "$swapfile_path"
    
    log_info "Creating swapfile (this may take a few minutes))"
    
    if [[ "$fstype" == "btrfs" ]]; then
        # Check for modern btrfs command
        if btrfs filesystem mkswapfile --help &>/dev/null 2>&1; then
            btrfs filesystem mkswapfile --size "$SWAPFILE_SIZE" --uuid clear "$swapfile_path" || {
                add_anomaly "WARNING" "btrfs_swapfile" \
                    "btrfs mkswapfile successful" \
                    "btrfs mkswapfile failed" \
                    "Swapfile could not be created" \
                    "Create manually or try legacy method"
                    
                add_skipped_operation "Swapfile creation" \
                    "btrfs mkswapfile failed" \
                    "btrfs_command"
                return 1
            }
        else
            # Legacy method
            truncate -s 0 "$swapfile_path"
            chattr +C "$swapfile_path" 2>/dev/null || true
            fallocate -l "$SWAPFILE_SIZE" "$swapfile_path" || dd if=/dev/zero of="$swapfile_path" bs=1G count=$SWAPFILE_SIZE_GB status=progress
            chmod 600 "$swapfile_path"
            mkswap "$swapfile_path" > /dev/null
        fi
    else
        # ext4/xfs
        fallocate -l "$SWAPFILE_SIZE" "$swapfile_path" || dd if=/dev/zero of="$swapfile_path" bs=1G count=$SWAPFILE_SIZE_GB status=progress
        chmod 600 "$swapfile_path"
        mkswap "$swapfile_path" > /dev/null
    fi
    
    # fstab
    sed -i "\|$swapfile_path|d" /etc/fstab
    echo "$swapfile_path none swap sw,pri=$SWAPFILE_PRIORITY 0 0" >> /etc/fstab
    
    # Activate
    swapon "$swapfile_path" || {
        add_anomaly "WARNING" "swapfile_activate" \
            "Swapfile activation successful" \
            "swapon failed" \
            "Swapfile not active" \
            "Manuel aktivasyon: sudo swapon /swapfile"
    }
    
    add_success "Swapfile" "$SWAPFILE_SIZE created"
}

configure_user_limits_safe() {
    log_header "[4/6] User Session Limits (Safe Mode)"
    
    mkdir -p /etc/systemd/system/user-.slice.d
    
    cat > /etc/systemd/system/user-.slice.d/50-memory-limit.conf << EOF
# Memory Optimizer v${SCRIPT_VERSION}
# Generated: $(date -Iseconds)
# THROTTLE ONLY - NO KILL

[Slice]
MemoryHigh=${USER_MEMORY_HIGH}
# MemoryMax= DELIBERATELY REMOVED - No kill!
MemorySwapMax=infinity
EOF

    systemctl daemon-reload 2>/dev/null || true
    
    add_success "User limits" "MemoryHigh=${USER_MEMORY_HIGH} (throttle only)"
}

disable_kill_mechanisms_safe() {
    log_header "[5/6] Kill Mechanisms (Safe Mode)"
    
    # earlyoom
    if systemctl list-unit-files 2>/dev/null | grep -q earlyoom; then
        systemctl stop earlyoom 2>/dev/null || true
        systemctl disable earlyoom 2>/dev/null || true
        add_success "earlyoom" "disabled"
    else
        log_info "earlyoom not installed"
    fi
    
    # systemd-oomd - PASSIVE MODE
    mkdir -p /etc/systemd/oomd.conf.d
    
    cat > /etc/systemd/oomd.conf.d/99-passive-nokill.conf << EOF
# Memory Optimizer v${SCRIPT_VERSION}
# PASSIVE MODE - Very high thresholds

[OOM]
SwapUsedLimit=95%
DefaultMemoryPressureLimit=90%
DefaultMemoryPressureDurationSec=60s
EOF

    systemctl daemon-reload 2>/dev/null || true
    systemctl restart systemd-oomd 2>/dev/null || true
    
    add_success "systemd-oomd" "passive mode (95% threshold)"
}

disable_zswap_safe() {
    log_header "[6/6] zswap Check (Safe Mode)"
    
    if [[ ! -f /sys/module/zswap/parameters/enabled ]]; then
        log_info "zswap module not found"
        return 0
    fi
    
    local zswap_status=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N")
    
    if [[ "$zswap_status" == "Y" ]]; then
        # Disable runtime
        echo 0 > /sys/module/zswap/parameters/enabled 2>/dev/null || true
        
        # Permanent disable - ONLY if we're confident about bootloader
        if [[ "$BOOTLOADER_CONFIDENCE" == "HIGH" ]]; then
            case "$DETECTED_BOOTLOADER" in
                grub)
                    if command -v grubby &>/dev/null; then
                        grubby --update-kernel=ALL --args="zswap.enabled=0" 2>/dev/null || true
                        add_success "zswap" "disabled (grubby)"
                    fi
                    ;;
                systemd-boot)
                    if [[ -f /etc/kernel/cmdline ]]; then
                        if ! grep -q "zswap.enabled=0" /etc/kernel/cmdline; then
                            echo " zswap.enabled=0" >> /etc/kernel/cmdline
                            kernel-install add-all 2>/dev/null || true
                        fi
                        add_success "zswap" "disabled (kernel cmdline)"
                    fi
                    ;;
                *)
                    add_skipped_operation "zswap kernel param" \
                        "Bootloader type unknown, kernel param not added" \
                        "bootloader_confidence"
                    ;;
            esac
        else
            add_skipped_operation "zswap kernel param (permanent)" \
                "Bootloader confidence low, only runtime disable done" \
                "bootloader_confidence"
            add_success "zswap" "runtime disabled (permanent skip)"
        fi
    else
        log_info "zswap already disabled"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
#───────────────────────────────────────────────────────────────────────────────

preflight_checks() {
    log_header "Pre-flight Checks (Safe Mode)"
    
    # Root check
    if [[ $EUID -ne 0 ]]; then
        log_error "Root required: sudo $0"
        exit 1
    fi
    
    # IDEMPOTENCY: Check if already installed
    local already_installed=false
    local installed_components=()
    
    if [[ -f /etc/sysctl.d/99-memory-optimizer.conf ]]; then
        installed_components+=("sysctl")
        already_installed=true
    fi
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        installed_components+=("zram-generator")
        already_installed=true
    fi
    if [[ -f /etc/systemd/system/user-.slice.d/50-memory-limit.conf ]]; then
        installed_components+=("user-limits")
        already_installed=true
    fi
    if [[ -f /etc/systemd/oomd.conf.d/99-passive-nokill.conf ]]; then
        installed_components+=("oomd-passive")
        already_installed=true
    fi
    
    if [[ "$already_installed" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}⚠️  EXISTING INSTALLATION DETECTED${NC}                                    ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}║${NC}  Installed components:                                                  ${YELLOW}║${NC}"
        for comp in "${installed_components[@]}"; do
            echo -e "${YELLOW}║${NC}    • $comp                                                  ${YELLOW}║${NC}"
        done
        echo -e "${YELLOW}║${NC}                                                                       ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Config files will be updated (existing values will not be preserved))       ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Swapfile will be PRESERVED if exists and adequate                             ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -r -p "Continue? (y/N) " response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            log_info "Cancelled"
            exit 0
        fi
    fi
    
    # Detect everything with safety
    detect_bootloader_safe
    detect_init_system_safe
    detect_package_manager_safe
    detect_zram_backend_safe
    detect_ram_and_configure
    
    # Check Fedora version
    if [[ -f /etc/fedora-release ]]; then
        local fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "0")
        log_info "Fedora $fedora_ver"
        
        if [[ $fedora_ver -gt 42 ]]; then
            add_anomaly "INFO" "fedora_version" \
                "Tested Fedora version (≤42)" \
                "Fedora $fedora_ver (untested)" \
                "Some behaviors may differ" \
                "Please verify results and report issues"
        fi
    fi
    
    # Print summary
    echo ""
    echo -e "${BOLD}Detection Summary:${NC}"
    echo "  Bootloader:  $DETECTED_BOOTLOADER (confidence: $BOOTLOADER_CONFIDENCE)"
    echo "  Init:        $DETECTED_INIT_SYSTEM"
    echo "  Pkg Manager: $DETECTED_PKG_MANAGER"
    echo "  zram:        $DETECTED_ZRAM_BACKEND ($ZRAM_STATUS)"
    echo "  RAM:         ${RAM_GB}GB → Tier ${RAM_TIER}GB"
    echo ""
    
    # Critical anomaly check
    if [[ "$CRITICAL_ANOMALY" == "true" ]]; then
        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}⛔ CRITICAL ANOMALY DETECTED${NC}                                     ${RED}║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
        echo -e "${RED}║${NC}  Critical differences detected in system.                         ${RED}║${NC}"
        echo -e "${RED}║${NC}  Some operations will be SKIPPED in safe mode.                             ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
        echo -e "${RED}║${NC}  Detailed report will be generated after installation.                        ${RED}║${NC}"
        echo -e "${RED}║${NC}  Send this report to your AI assistant to receive for custom solutions.      ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -r -p "Do you want to continue in safe mode? (y/N) " response
        [[ ! "$response" =~ ^[Yy] ]] && exit 1
    else
        read -r -p "Continue? (Y/n) " response
        [[ "$response" =~ ^[Nn] ]] && exit 0
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# BACKUP
#───────────────────────────────────────────────────────────────────────────────

create_backup() {
    log_header "Creating Backup"
    
    local backup_dir="/root/memory-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    [[ -f /etc/sysctl.d/99-memory-optimizer.conf ]] && cp /etc/sysctl.d/99-memory-optimizer.conf "$backup_dir/" 2>/dev/null || true
    [[ -f /etc/systemd/zram-generator.conf ]] && cp /etc/systemd/zram-generator.conf "$backup_dir/" 2>/dev/null || true
    [[ -f /etc/fstab ]] && cp /etc/fstab "$backup_dir/"
    
    log_success "Backup: $backup_dir"
}

#───────────────────────────────────────────────────────────────────────────────
# SUMMARY WITH REPORT
#───────────────────────────────────────────────────────────────────────────────

print_summary() {
    generate_diagnostic_report
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ${BOLD}MEMORY OPTIMIZER v${SCRIPT_VERSION} - SUMMARY REPORT${NC}${CYAN}                        ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    
    # Successful operations
    echo -e "${CYAN}║${NC}  ${GREEN}Successful Operations: ${#SUCCESSFUL_OPERATIONS[@]}${NC}                                        ${CYAN}║${NC}"
    for op in "${SUCCESSFUL_OPERATIONS[@]}"; do
        echo -e "${CYAN}║${NC}    ${GREEN}✓${NC} $op                                ${CYAN}║${NC}"
    done
    echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    
    # Skipped operations
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]]; then
        echo -e "${CYAN}║${NC}  ${YELLOW}Skipped Operations: ${#SKIPPED_OPERATIONS[@]}${NC}                                           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    fi
    
    # Anomalies
    if [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo -e "${CYAN}║${NC}  ${RED}Detected Anomalies: $ANOMALY_COUNT${NC}                                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    fi
    
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]] || [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}📋 DETAILED REPORT:${NC}                                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  $REPORT_FILE  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Send this report to your AI assistant (Claude, ChatGPT vb.) to receive          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  a custom solution for your system.                               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${DIM}cat $REPORT_FILE | xclip -selection clipboard${NC}  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    fi
    
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}⚠️  REBOOT REQUIRED - for zram to activate                        ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show report preview if anomalies exist
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]] || [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo ""
        read -r -p "Do you want to view the diagnostic report? (y/N) " response
        if [[ "$response" =~ ^[Yy] ]]; then
            echo ""
            cat "$REPORT_FILE"
        fi
    fi
    
    echo ""
    read -r -p "Reboot now? (y/N) " response
    [[ "$response" =~ ^[Yy] ]] && { sleep 2; reboot; }
}

#───────────────────────────────────────────────────────────────────────────────
# STATUS CHECK
#───────────────────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    echo -e "${BOLD}MEMORY OPTIMIZER v${SCRIPT_VERSION} STATUS${NC}"
    echo ""
    
    detect_ram_and_configure
    
    echo "=== SWAP ==="
    swapon --show
    echo ""
    
    echo "=== ZRAM ==="
    zramctl 2>/dev/null || echo "zram inactive"
    echo ""
    
    echo "=== MEMORY ==="
    free -h
    echo ""
    
    echo "=== KERNEL ==="
    echo "swappiness: $(cat /proc/sys/vm/swappiness)"
    echo "page-cluster: $(cat /proc/sys/vm/page-cluster)"
    echo ""
    
    echo "=== SERVICES ==="
    echo -n "earlyoom: "; systemctl is-active earlyoom 2>/dev/null || echo "inactive"
    echo -n "systemd-oomd: "; systemctl is-active systemd-oomd 2>/dev/null || echo "inactive"
}

#───────────────────────────────────────────────────────────────────────────────
# FIX ZRAM
#───────────────────────────────────────────────────────────────────────────────

fix_zram() {
    log_header "🔧 zram Fix (Safe Mode)"
    
    detect_ram_and_configure
    
    if [[ ! -b /dev/zram0 ]]; then
        modprobe zram 2>/dev/null || {
            log_error "zram module could not be loaded"
            return 1
        }
        sleep 1
    fi
    
    swapoff /dev/zram0 2>/dev/null || true
    
    [[ -f /sys/block/zram0/reset ]] && echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    sleep 0.5
    
    echo "${ZRAM_ALGORITHM}" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo "${ZRAM_SIZE_BYTES}" > /sys/block/zram0/disksize 2>/dev/null || {
        log_error "zram size could not be set"
        return 1
    }
    
    mkswap /dev/zram0 > /dev/null 2>&1 || return 1
    swapon -p ${ZRAM_PRIORITY} /dev/zram0 || return 1
    
    log_success "zram fixed!"
    swapon --show
    zramctl
}

#───────────────────────────────────────────────────────────────────────────────
# DIAGNOSE (NO ROOT)
#───────────────────────────────────────────────────────────────────────────────

run_diagnose() {
    echo ""
    echo -e "${BOLD}MEMORY OPTIMIZER v${SCRIPT_VERSION} - SYSTEM DIAGNOSTICS${NC}"
    echo ""
    
    detect_bootloader_safe
    detect_init_system_safe
    detect_package_manager_safe
    detect_zram_backend_safe
    detect_ram_and_configure
    check_hibernate_status_safe
    
    echo ""
    echo "=== DETECTION SUMMARY ==="
    echo "Bootloader:    $DETECTED_BOOTLOADER ($BOOTLOADER_CONFIDENCE)"
    echo "Init System:   $DETECTED_INIT_SYSTEM"
    echo "Pkg Manager:   $DETECTED_PKG_MANAGER"
    echo "zram Backend:  $DETECTED_ZRAM_BACKEND ($ZRAM_STATUS)"
    echo "Hibernate:     $HIBERNATE_STATUS"
    echo "RAM:           ${RAM_GB}GB → Tier ${RAM_TIER}GB"
    echo ""
    
    if [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo "=== ANOMALIES: $ANOMALY_COUNT ==="
        for anomaly in "${ANOMALIES[@]}"; do
            echo "$anomaly"
            echo "---"
        done
    else
        echo -e "${GREEN}✓ No anomalies detected${NC}"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# HELP
#───────────────────────────────────────────────────────────────────────────────

show_help() {
    echo ""
    echo -e "${BOLD}Memory Optimizer v${SCRIPT_VERSION} - Fail-Safe Edition${NC}"
    echo ""
    echo "Usage: sudo $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  (no params)  Install (safe mode)"
    echo "  --status         Status check"
    echo "  --diagnose       System diagnostics (no root required)"
    echo "  --fix-zram       Fix zram"
    echo "  --help           This help"
    echo ""
    echo "Fail-Safe Features:"
    echo "  • STOPS on unknown, makes NO assumptions"
    echo "  • Generates detailed report for skipped operations"
    echo "  • Report in AI assistant compatible format"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN
#───────────────────────────────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        --status)
            show_status
            ;;
        --diagnose)
            run_diagnose
            ;;
        --fix-zram)
            [[ $EUID -ne 0 ]] && { echo "Root required"; exit 1; }
            fix_zram
            ;;
        --help|-h)
            show_help
            ;;
        "")
            echo ""
            echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC}  ${BOLD}MEMORY OPTIMIZER v${SCRIPT_VERSION}${NC} - Fail-Safe Edition                    ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  Stops on unknown situations | AI-Ready Diagnostic Reports             ${CYAN}║${NC}"
            echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
            
            preflight_checks
            create_backup
            configure_kernel_params_safe
            configure_zram_safe
            configure_swapfile_safe
            configure_user_limits_safe
            disable_kill_mechanisms_safe
            disable_zswap_safe
            print_summary
            ;;
        *)
            echo "Bilinmeyen: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
