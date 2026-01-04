#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#
#  FEDORA HIBERNATE SETUP v4.0 - FAIL-SAFE EDITION
#  ═══════════════════════════════════════════════════════════════════════════
#  
#  ✅ Anomaly Detection - Stops on unknown situations
#  ✅ AI-Ready Reports - Can be sent to AI agents
#  ✅ No Hallucination - Makes no assumptions
#  ✅ Safe Defaults - Skips operation when uncertain
#
#═══════════════════════════════════════════════════════════════════════════════

SCRIPT_VERSION="4.0.0"
SCRIPT_NAME="setup-hibernation-v4"
REPORT_FILE=""

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
# ANOMALY TRACKING
#───────────────────────────────────────────────────────────────────────────────

declare -a ANOMALIES=()
declare -a SKIPPED_OPERATIONS=()
declare -a SUCCESSFUL_OPERATIONS=()

ANOMALY_COUNT=0
CRITICAL_ANOMALY=false

add_anomaly() {
    local severity="$1"
    local component="$2"
    local expected="$3"
    local found="$4"
    local impact="$5"
    local suggestion="$6"
    
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
    
    case "$severity" in
        CRITICAL) log_error "ANOMALY [$component]: $found" ;;
        WARNING)  log_warning "ANOMALY [$component]: $found" ;;
        INFO)     log_info "ANOMALY [$component]: $found" ;;
    esac
}

add_skipped_operation() {
    local operation="$1"
    local reason="$2"
    local dependency="$3"
    
    SKIPPED_OPERATIONS+=("$operation|$reason|$dependency")
    log_warning "ATLANDI: $operation → $reason"
}

add_success() {
    local operation="$1"
    local details="$2"
    
    SUCCESSFUL_OPERATIONS+=("$operation: $details")
    log_success "$operation"
}

#───────────────────────────────────────────────────────────────────────────────
# GLOBAL VARIABLES
#───────────────────────────────────────────────────────────────────────────────

SWAP_FILE="/swapfile"
ACTIVE_KERNEL=$(uname -r)
BACKUP_DIR=""

# Detection results
DETECTED_BOOTLOADER=""
BOOTLOADER_CONFIDENCE=""
BOOTLOADER_DETECTION_METHOD=""
DETECTED_INIT_SYSTEM=""
FILESYSTEM_TYPE=""

# Calculated values
ROOT_UUID=""
RESUME_OFFSET=""
SWAP_SIZE=""

#───────────────────────────────────────────────────────────────────────────────
# SAFE DETECTION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

detect_bootloader_safe() {
    log_header "Bootloader Detection (Safe Mode)"
    
    DETECTED_BOOTLOADER=""
    BOOTLOADER_CONFIDENCE="NONE"
    BOOTLOADER_DETECTION_METHOD=""
    
    local evidence_grub=0
    local evidence_sdboot=0
    local evidence_uki=0
    local notes=()
    
    # GRUB evidence
    [[ -f /etc/default/grub ]] && { ((evidence_grub++)); notes+=("GRUB: /etc/default/grub"); }
    [[ -d /boot/grub2 ]] && { ((evidence_grub++)); notes+=("GRUB: /boot/grub2"); }
    [[ -f /boot/efi/EFI/fedora/grub.cfg ]] && { ((evidence_grub++)); notes+=("GRUB: grub.cfg"); }
    
    if command -v grubby &>/dev/null; then
        local target=$(readlink -f "$(which grubby)" 2>/dev/null || echo "grubby")
        if [[ "$target" != *"sdubby"* ]]; then
            ((evidence_grub++))
            notes+=("GRUB: grubby (not sdubby)")
        else
            ((evidence_sdboot++))
            notes+=("SD-BOOT: sdubby")
        fi
    fi
    
    # systemd-boot evidence
    [[ -d /boot/loader/entries ]] && { ((evidence_sdboot++)); notes+=("SD-BOOT: /boot/loader/entries"); }
    [[ -d /boot/efi/loader/entries ]] && { ((evidence_sdboot++)); notes+=("SD-BOOT: /boot/efi/loader/entries"); }
    [[ -f /etc/kernel/cmdline ]] && { ((evidence_sdboot++)); notes+=("SD-BOOT: /etc/kernel/cmdline"); }
    
    if command -v bootctl &>/dev/null; then
        if bootctl status 2>/dev/null | head -5 | grep -qi "systemd-boot"; then
            ((evidence_sdboot+=2))
            notes+=("SD-BOOT: bootctl confirms")
        fi
    fi
    
    # UKI evidence
    if [[ -d /boot/efi/EFI/Linux ]] && ls /boot/efi/EFI/Linux/*.efi &>/dev/null 2>&1; then
        ((evidence_uki+=2))
        notes+=("UKI: .efi files present")
    fi
    
    log_info "Evidence: GRUB=$evidence_grub, SD-BOOT=$evidence_sdboot, UKI=$evidence_uki"
    for note in "${notes[@]}"; do
        log_info "  $note"
    done
    
    # Decision
    local max=$evidence_grub winner="grub"
    [[ $evidence_sdboot -gt $max ]] && { max=$evidence_sdboot; winner="systemd-boot"; }
    [[ $evidence_uki -gt $max ]] && { max=$evidence_uki; winner="uki"; }
    
    if [[ $max -eq 0 ]]; then
        BOOTLOADER_CONFIDENCE="NONE"
        add_anomaly "CRITICAL" "bootloader" \
            "Recognizable bootloader" \
            "No bootloader detected" \
            "Kernel resume parametreleri EKLENEMEYECEK" \
            "Manually specify bootloader type: grub2-mkconfig -o /boot/grub2/grub.cfg or edit /etc/kernel/cmdline"
    elif [[ $max -le 1 ]]; then
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_CONFIDENCE="LOW"
        BOOTLOADER_DETECTION_METHOD="Weak ($max point)"
        add_anomaly "WARNING" "bootloader" \
            "Clear bootloader detection" \
            "$winner (weak evidence: $max)" \
            "Kernel param changes risky" \
            "Verify bootloader type"
    elif [[ $max -ge 3 ]]; then
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_CONFIDENCE="HIGH"
        BOOTLOADER_DETECTION_METHOD="Strong ($max points)"
        log_success "Bootloader: $winner (HIGH confidence)"
    else
        DETECTED_BOOTLOADER="$winner"
        BOOTLOADER_CONFIDENCE="MEDIUM"
        BOOTLOADER_DETECTION_METHOD="Moderate ($max points)"
        log_info "Bootloader: $winner (MEDIUM confidence)"
    fi
}

detect_init_system_safe() {
    log_info "Detecting init system..."
    
    DETECTED_INIT_SYSTEM=""
    
    if command -v dracut &>/dev/null; then
        DETECTED_INIT_SYSTEM="dracut"
        log_success "Init: dracut"
    elif command -v update-initramfs &>/dev/null; then
        DETECTED_INIT_SYSTEM="initramfs-tools"
        log_success "Init: initramfs-tools"
    else
        add_anomaly "CRITICAL" "init_system" \
            "dracut or update-initramfs" \
            "No initramfs tool found" \
            "initramfs CANNOT be regenerated, resume module CANNOT be added" \
            "dracut kurun: sudo dnf install dracut"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# /BOOT SPACE CHECK
#───────────────────────────────────────────────────────────────────────────────

BOOT_SEPARATE=false
BOOT_FREE_MB=0

check_boot_space_safe() {
    log_header "/boot Partition Check"
    
    if ! mountpoint -q /boot 2>/dev/null; then
        log_info "/boot not a separate partition"
        BOOT_SEPARATE=false
        return 0
    fi
    
    BOOT_SEPARATE=true
    BOOT_FREE_MB=$(df /boot | tail -1 | awk '{print int($4/1024)}')
    
    log_info "/boot: ${BOOT_FREE_MB}MB free"
    
    if [[ $BOOT_FREE_MB -lt 150 ]]; then
        add_anomaly "CRITICAL" "boot_space" \
            "At least 150MB free space" \
            "${BOOT_FREE_MB}MB free space" \
            "initramfs regeneration may FAIL" \
            "Clean up old kernels: sudo dnf remove $(rpm -qa kernel-core | sort -V | head -n -2 | tr '\n' ' ')"
        return 1
    fi
    
    log_success "/boot has sufficient space"
    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# GPU DRIVER CHECK
#───────────────────────────────────────────────────────────────────────────────

check_gpu_safe() {
    log_header "GPU Driver Check"
    
    log_info "GPU'lar:"
    lspci | grep -iE "vga|3d" | sed 's/^/  /' || echo "  Not detected"
    
    if lsmod | grep -qi "nvidia"; then
        if rpm -qa 2>/dev/null | grep -q "akmod-nvidia"; then
            log_success "NVIDIA: akmod (otomatik rebuild)"
        elif rpm -qa 2>/dev/null | grep -q "kmod-nvidia"; then
            add_anomaly "WARNING" "gpu_driver" \
                "akmod-nvidia (otomatik rebuild)" \
                "kmod-nvidia (static kernel module)" \
                "Driver may not work after kernel update" \
                "switch to akmod: sudo dnf swap kmod-nvidia akmod-nvidia"
        fi
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# DIAGNOSTIC REPORT GENERATOR
#───────────────────────────────────────────────────────────────────────────────

generate_diagnostic_report() {
    local report_dir="/root/hibernate-reports"
    mkdir -p "$report_dir"
    
    REPORT_FILE="$report_dir/diagnostic-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
  HIBERNATE SETUP v${SCRIPT_VERSION} - DIAGNOSTIC REPORT
  Send this report to your AI assistant for custom solutions.
═══════════════════════════════════════════════════════════════════════════════

[SYSTEM SNAPSHOT]
Date: $(date -Iseconds)
Kernel: $(uname -r)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)

[DETECTION RESULTS]
Bootloader: ${DETECTED_BOOTLOADER:-NOT DETECTED}
  Confidence: ${BOOTLOADER_CONFIDENCE:-NONE}
  Method: ${BOOTLOADER_DETECTION_METHOD:-N/A}
Init System: ${DETECTED_INIT_SYSTEM:-NOT DETECTED}
Filesystem: ${FILESYSTEM_TYPE:-NOT DETECTED}

[HIBERNATE CONFIG]
Swapfile: ${SWAP_FILE}
Swap Size: ${SWAP_SIZE:-NOT SET}
Root UUID: ${ROOT_UUID:-NOT SET}
Resume Offset: ${RESUME_OFFSET:-NOT SET}

[ANOMALIES: $ANOMALY_COUNT]
EOF

    for anomaly in "${ANOMALIES[@]}"; do
        echo "$anomaly" >> "$REPORT_FILE"
        echo "---" >> "$REPORT_FILE"
    done
    
    cat >> "$REPORT_FILE" << EOF

[SKIPPED OPERATIONS: ${#SKIPPED_OPERATIONS[@]}]
EOF

    for skipped in "${SKIPPED_OPERATIONS[@]}"; do
        echo "$skipped" >> "$REPORT_FILE"
    done
    
    cat >> "$REPORT_FILE" << EOF

[SUCCESSFUL OPERATIONS: ${#SUCCESSFUL_OPERATIONS[@]}]
EOF

    for success in "${SUCCESSFUL_OPERATIONS[@]}"; do
        echo "✓ $success" >> "$REPORT_FILE"
    done
    
    cat >> "$REPORT_FILE" << 'EOF'

[RAW DATA]
--- /proc/cmdline ---
EOF
    cat /proc/cmdline >> "$REPORT_FILE" 2>/dev/null
    
    cat >> "$REPORT_FILE" << 'EOF'

--- swapon --show ---
EOF
    swapon --show >> "$REPORT_FILE" 2>/dev/null
    
    cat >> "$REPORT_FILE" << 'EOF'

--- Available commands ---
EOF
    for cmd in grubby grub2-mkconfig bootctl kernel-install dracut; do
        echo -n "  $cmd: " >> "$REPORT_FILE"
        command -v "$cmd" >> "$REPORT_FILE" 2>/dev/null || echo "not found" >> "$REPORT_FILE"
    done
    
    cat >> "$REPORT_FILE" << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
[AI PROMPT]
Send this report to your AI assistant as follows:

"I tried to set up hibernate on my Fedora system and anomalies were
detected. Please analyze the report below and:
1. Explain what the anomalies mean
2. How can I manually perform skipped operations
3. Provide system-specific commands

[PASTE REPORT]"
═══════════════════════════════════════════════════════════════════════════════
EOF
}

#───────────────────────────────────────────────────────────────────────────────
# SAFE OPERATIONS
#───────────────────────────────────────────────────────────────────────────────

calculate_swap_size_safe() {
    log_header "Swap Size Calculation"
    
    local ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local ram_gb=$((ram_kb / 1024 / 1024))
    
    local multiplier=1
    [[ $ram_gb -lt 8 ]] && multiplier=2
    [[ $ram_gb -lt 16 ]] && [[ $ram_gb -ge 8 ]] && multiplier=1.5
    
    SWAP_SIZE=$(awk "BEGIN {printf \"%.0fG\", $ram_gb * $multiplier}")
    
    log_info "RAM: ${ram_gb}GB × ${multiplier} = ${SWAP_SIZE}"
    
    read -r -p "Is this size acceptable? (Y/n/custom) " response
    if [[ "$response" =~ ^[Nn] ]] || [[ "$response" == "custom" ]]; then
        read -r -p "New size (e.g. 32G): " SWAP_SIZE
    fi
}

create_swapfile_safe() {
    log_header "Swapfile Creation (Safe Mode)"
    
    FILESYSTEM_TYPE=$(df -T / | tail -1 | awk '{print $2}')
    log_info "Filesystem: $FILESYSTEM_TYPE"
    
    # Check existing
    if [[ -f "$SWAP_FILE" ]]; then
        local existing_gb=$(($(stat -c%s "$SWAP_FILE" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
        local needed_gb=${SWAP_SIZE%G}
        
        if [[ $existing_gb -ge $needed_gb ]]; then
            log_success "Existing swapfile sufficient: ${existing_gb}GB"
            
            if ! swapon --show | grep -q "$SWAP_FILE"; then
                swapon "$SWAP_FILE" 2>/dev/null || {
                    mkswap "$SWAP_FILE" > /dev/null 2>&1
                    swapon "$SWAP_FILE"
                }
            fi
            
            add_success "Swapfile" "Existing used (${existing_gb}GB)"
            return 0
        fi
        
        swapoff "$SWAP_FILE" 2>/dev/null || true
    fi
    
    [[ -f "$SWAP_FILE" ]] && rm -f "$SWAP_FILE"
    
    local swap_gb=${SWAP_SIZE%G}
    
    log_info "Creating swapfile: $SWAP_SIZE"
    
    if [[ "$FILESYSTEM_TYPE" == "btrfs" ]]; then
        if btrfs filesystem mkswapfile --help &>/dev/null 2>&1; then
            btrfs filesystem mkswapfile --size "$SWAP_SIZE" --uuid clear "$SWAP_FILE" || {
                add_anomaly "WARNING" "btrfs_swapfile" \
                    "btrfs mkswapfile successful" \
                    "btrfs mkswapfile failed" \
                    "Swapfile COULD NOT BE CREATED" \
                    "Try legacy method: truncate + chattr +C + fallocate"
                add_skipped_operation "Swapfile creation" "btrfs mkswapfile failed" "btrfs"
                return 1
            }
        else
            # Legacy
            truncate -s 0 "$SWAP_FILE"
            chattr +C "$SWAP_FILE" 2>/dev/null || true
            btrfs property set "$SWAP_FILE" compression none 2>/dev/null || true
            fallocate -l "$SWAP_SIZE" "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1G count=$swap_gb status=progress
            chmod 600 "$SWAP_FILE"
            mkswap "$SWAP_FILE" > /dev/null
        fi
    else
        fallocate -l "$SWAP_SIZE" "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1G count=$swap_gb status=progress
        chmod 600 "$SWAP_FILE"
        mkswap "$SWAP_FILE" > /dev/null
    fi
    
    # fstab
    sed -i "\|$SWAP_FILE|d" /etc/fstab
    echo "$SWAP_FILE none swap sw,pri=10 0 0" >> /etc/fstab
    
    swapon "$SWAP_FILE" || {
        add_anomaly "WARNING" "swapon" "swapon successful" "swapon failed" \
            "Swapfile not active" "Manuel: sudo swapon /swapfile"
    }
    
    add_success "Swapfile" "$SWAP_SIZE created"
}

calculate_resume_offset_safe() {
    log_header "Resume Offset Hesaplama"
    
    ROOT_UUID=$(findmnt -no UUID /)
    
    if [[ -z "$ROOT_UUID" ]]; then
        add_anomaly "CRITICAL" "root_uuid" \
            "Root partition UUID" \
            "UUID could not be detected" \
            "Resume parameter CANNOT BE CREATED" \
            "Find UUID manually with blkid command"
        return 1
    fi
    
    log_info "Root UUID: $ROOT_UUID"
    
    if [[ "$FILESYSTEM_TYPE" == "btrfs" ]]; then
        RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r "$SWAP_FILE" 2>/dev/null)
    else
        RESUME_OFFSET=$(filefrag -v "$SWAP_FILE" 2>/dev/null | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')
    fi
    
    if [[ -z "$RESUME_OFFSET" ]]; then
        add_anomaly "CRITICAL" "resume_offset" \
            "Resume offset value" \
            "Offset could not be calculated" \
            "Hibernate WILL NOT WORK" \
            "btrfs: btrfs inspect-internal map-swapfile -r /swapfile | ext4: filefrag -v /swapfile"
        return 1
    fi
    
    log_success "Resume offset: $RESUME_OFFSET"
    add_success "Resume params" "UUID=$ROOT_UUID offset=$RESUME_OFFSET"
}

configure_kernel_params_safe() {
    log_header "Kernel Parametreleri (Safe Mode)"
    
    local params="resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"
    
    # Check if we can proceed
    if [[ -z "$ROOT_UUID" ]] || [[ -z "$RESUME_OFFSET" ]]; then
        add_skipped_operation "Kernel param ekleme" \
            "UUID or offset could not be calculated" \
            "resume_calculation"
        return 1
    fi
    
    # IDEMPOTENCY: Check if params already exist and are correct
    local current_cmdline=$(cat /proc/cmdline)
    local has_resume=false
    local has_offset=false
    local resume_correct=false
    local offset_correct=false
    
    if echo "$current_cmdline" | grep -q "resume=UUID=$ROOT_UUID"; then
        has_resume=true
        resume_correct=true
    elif echo "$current_cmdline" | grep -q "resume="; then
        has_resume=true
        resume_correct=false
    fi
    
    if echo "$current_cmdline" | grep -q "resume_offset=$RESUME_OFFSET"; then
        has_offset=true
        offset_correct=true
    elif echo "$current_cmdline" | grep -q "resume_offset="; then
        has_offset=true
        offset_correct=false
    fi
    
    if [[ "$resume_correct" == "true" ]] && [[ "$offset_correct" == "true" ]]; then
        log_success "Kernel params already correctly configured"
        log_info "  resume=UUID=$ROOT_UUID"
        log_info "  resume_offset=$RESUME_OFFSET"
        add_success "Kernel params" "Existing config preserved (already correct)"
        return 0
    fi
    
    if [[ "$has_resume" == "true" ]] || [[ "$has_offset" == "true" ]]; then
        log_warning "Existing resume params detected but values differ"
        log_info "  Current: $(echo "$current_cmdline" | grep -oE 'resume[^ ]*' | tr '\n' ' ')"
        log_info "  New:   resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"
    fi
    
    if [[ "$BOOTLOADER_CONFIDENCE" == "NONE" ]]; then
        add_skipped_operation "Kernel param ekleme" \
            "Bootloader could not be detected" \
            "bootloader_detection"
        
        log_warning "Manuel olarak ekleyin:"
        echo "  $params"
        return 1
    fi
    
    if [[ "$BOOTLOADER_CONFIDENCE" == "LOW" ]]; then
        log_warning "Bootloader confidence low, confirmation required"
        echo ""
        echo "Detected bootloader: $DETECTED_BOOTLOADER"
        echo "Eklenecek parametreler: $params"
        echo ""
        read -r -p "Do you want to write to this bootloader? (y/N) " response
        
        if [[ ! "$response" =~ ^[Yy] ]]; then
            add_skipped_operation "Kernel param ekleme" \
                "User declined (LOW confidence)" \
                "user_confirmation"
            
            log_info "Manuel olarak ekleyin: $params"
            return 1
        fi
    fi
    
    # Proceed with bootloader-specific method
    case "$DETECTED_BOOTLOADER" in
        grub)
            configure_grub_params "$params"
            ;;
        systemd-boot)
            configure_sdboot_params "$params"
            ;;
        uki)
            configure_uki_params "$params"
            ;;
        *)
            add_skipped_operation "Kernel param ekleme" \
                "Bilinmeyen bootloader: $DETECTED_BOOTLOADER" \
                "unknown_bootloader"
            
            log_warning "Manuel ekleyin: $params"
            return 1
            ;;
    esac
}

configure_grub_params() {
    local params="$1"
    
    log_info "Configuring GRUB..."
    
    if command -v grubby &>/dev/null; then
        grubby --update-kernel=ALL --remove-args="resume resume_offset" 2>/dev/null || true
        grubby --update-kernel=ALL --args="$params" || {
            add_anomaly "WARNING" "grubby" "grubby successful" "grubby failed" \
                "Kernel params COULD NOT BE ADDED" "Manuel: grubby --update-kernel=ALL --args=\"$params\""
            return 1
        }
        add_success "Kernel params (grubby)" "$params"
    else
        add_skipped_operation "Adding param with grubby" \
            "grubby command not found" \
            "missing_command"
        
        log_warning "Manually edit /etc/default/grub"
        return 1
    fi
}

configure_sdboot_params() {
    local params="$1"
    
    log_info "Configuring systemd-boot..."
    
    mkdir -p /etc/kernel
    
    if [[ -f /etc/kernel/cmdline ]]; then
        sed -i 's/resume=[^ ]*//g' /etc/kernel/cmdline
        sed -i 's/resume_offset=[^ ]*//g' /etc/kernel/cmdline
        local current=$(cat /etc/kernel/cmdline | tr '\n' ' ')
        echo "$current $params" > /etc/kernel/cmdline
    else
        local current=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //')
        echo "$current $params" > /etc/kernel/cmdline
    fi
    
    if command -v kernel-install &>/dev/null; then
        kernel-install add-all 2>/dev/null || true
    fi
    
    add_success "Kernel params (systemd-boot)" "/etc/kernel/cmdline"
}

configure_uki_params() {
    local params="$1"
    
    log_info "Configuring UKI..."
    
    mkdir -p /etc/kernel
    
    if [[ -f /etc/kernel/cmdline ]]; then
        sed -i 's/resume=[^ ]*//g' /etc/kernel/cmdline
        sed -i 's/resume_offset=[^ ]*//g' /etc/kernel/cmdline
        local current=$(cat /etc/kernel/cmdline | tr '\n' ' ')
        echo "$current $params" > /etc/kernel/cmdline
    else
        local current=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //')
        echo "$current $params" > /etc/kernel/cmdline
    fi
    
    if command -v kernel-install &>/dev/null; then
        kernel-install add-all 2>/dev/null || true
    fi
    
    add_success "Kernel params (UKI)" "/etc/kernel/cmdline"
    log_warning "UKI rebuild may be required"
}

configure_initramfs_safe() {
    log_header "initramfs Configuration (Safe Mode)"
    
    if [[ -z "$DETECTED_INIT_SYSTEM" ]]; then
        add_skipped_operation "initramfs configuration" \
            "Init system could not be detected" \
            "init_system_detection"
        return 1
    fi
    
    # /boot space check
    if [[ "$BOOT_SEPARATE" == "true" ]] && [[ $BOOT_FREE_MB -lt 150 ]]; then
        add_skipped_operation "initramfs rebuild" \
            "Insufficient space in /boot (${BOOT_FREE_MB}MB < 150MB)" \
            "boot_space"
        return 1
    fi
    
    case "$DETECTED_INIT_SYSTEM" in
        dracut)
            # IDEMPOTENCY: Check if resume module already exists
            local resume_module_exists=false
            if lsinitrd "/boot/initramfs-${ACTIVE_KERNEL}.img" 2>/dev/null | grep -q "resume"; then
                resume_module_exists=true
            fi
            
            # Check if dracut config already exists with correct content
            local dracut_config_ok=false
            if [[ -f /etc/dracut.conf.d/99-hibernate.conf ]]; then
                if grep -q 'add_dracutmodules.*resume' /etc/dracut.conf.d/99-hibernate.conf 2>/dev/null; then
                    dracut_config_ok=true
                fi
            fi
            
            # If everything is already configured, skip rebuild
            if [[ "$resume_module_exists" == "true" ]] && [[ "$dracut_config_ok" == "true" ]]; then
                log_success "initramfs already contains resume module (rebuild skipped)"
                add_success "initramfs (dracut)" "Existing config preserved (resume module present)"
                return 0
            fi
            
            # Write/update config
            mkdir -p /etc/dracut.conf.d
            echo 'add_dracutmodules+=" resume "' > /etc/dracut.conf.d/99-hibernate.conf
            
            # If module exists but config was missing, just update config
            if [[ "$resume_module_exists" == "true" ]]; then
                log_success "Resume module present, only config updated"
                add_success "initramfs (dracut)" "Config updated (rebuild not needed)"
                return 0
            fi
            
            log_info "Regenerating initramfs (only: $ACTIVE_KERNEL)..."
            log_warning "This may take a few minutes..."
            
            dracut --force --kver "$ACTIVE_KERNEL" || {
                add_anomaly "WARNING" "dracut" \
                    "dracut successful" \
                    "dracut failed" \
                    "Resume module COULD NOT BE ADDED" \
                    "Manuel: sudo dracut --force --kver $(uname -r)"
                return 1
            }
            
            # Verify
            if lsinitrd "/boot/initramfs-${ACTIVE_KERNEL}.img" 2>/dev/null | grep -q "resume"; then
                add_success "initramfs (dracut)" "resume module added"
            else
                add_anomaly "WARNING" "resume_module" \
                    "Resume module present" \
                    "Resume module not found" \
                    "Hibernate WILL NOT WORK" \
                    "Check with lsinitrd"
            fi
            ;;
            
        initramfs-tools)
            echo "RESUME=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET" > /etc/initramfs-tools/conf.d/resume
            update-initramfs -u -k "$(uname -r)" || {
                add_anomaly "WARNING" "update-initramfs" \
                    "update-initramfs successful" "update-initramfs failed" \
                    "Resume module COULD NOT BE ADDED" "Manuel: sudo update-initramfs -u"
                return 1
            }
            add_success "initramfs (update-initramfs)" "resume module added"
            ;;
    esac
}

configure_systemd_safe() {
    log_header "systemd/polkit Configuration"
    
    mkdir -p /etc/polkit-1/rules.d
    
    cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit") {
        return polkit.Result.YES;
    }
});
EOF
    
    systemctl daemon-reload 2>/dev/null || true
    
    add_success "polkit" "hibernate izinleri eklendi"
}

create_helper_scripts_safe() {
    log_header "Helper Scripts"
    
    cat > /usr/local/bin/hibernate-test << 'EOF'
#!/bin/bash
echo "=== HIBERNATE CHECK ==="
echo ""
echo "[Kernel params]"
cat /proc/cmdline | tr ' ' '\n' | grep -E "resume" || echo "  YOK!"
echo ""
echo "[Swap]"
swapon --show
echo ""
echo "[Resume module]"
sudo lsinitrd /boot/initramfs-$(uname -r).img 2>/dev/null | grep -q "resume" && echo "  ✓ Present" || echo "  ✗ MISSING"
echo ""
echo "Test: sudo systemctl hibernate"
EOF
    chmod +x /usr/local/bin/hibernate-test
    
    add_success "Helper scripts" "hibernate-test created"
}

#───────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT & BACKUP
#───────────────────────────────────────────────────────────────────────────────

preflight_checks() {
    log_header "Pre-flight Checks (Safe Mode)"
    
    [[ $EUID -ne 0 ]] && { log_error "Root required: sudo $0"; exit 1; }
    
    # IDEMPOTENCY: Check if hibernate is already configured
    local already_configured=false
    local configured_components=()
    
    # Check kernel params
    if grep -q "resume=" /proc/cmdline 2>/dev/null; then
        configured_components+=("kernel-resume-param")
        already_configured=true
    fi
    
    # Check dracut config
    if [[ -f /etc/dracut.conf.d/99-hibernate.conf ]]; then
        configured_components+=("dracut-config")
        already_configured=true
    fi
    
    # Check polkit
    if [[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]]; then
        configured_components+=("polkit-rules")
        already_configured=true
    fi
    
    # Check swapfile
    if [[ -f /swapfile ]]; then
        local swap_gb=$(($(stat -c%s /swapfile 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
        configured_components+=("swapfile-${swap_gb}GB")
        already_configured=true
    fi
    
    if [[ "$already_configured" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}⚠️  EXISTING HIBERNATE INSTALLATION DETECTED${NC}                          ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}║${NC}  Installed components:                                                  ${YELLOW}║${NC}"
        for comp in "${configured_components[@]}"; do
            echo -e "${YELLOW}║${NC}    • $comp                                            ${YELLOW}║${NC}"
        done
        echo -e "${YELLOW}║${NC}                                                                       ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Script will check existing settings and update if necessary.   ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  Already correctly configured components will be skipped.                   ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
    
    detect_bootloader_safe
    detect_init_system_safe
    check_boot_space_safe
    check_gpu_safe
    
    echo ""
    echo -e "${BOLD}Detection Summary:${NC}"
    echo "  Bootloader:  $DETECTED_BOOTLOADER ($BOOTLOADER_CONFIDENCE)"
    echo "  Init:        $DETECTED_INIT_SYSTEM"
    echo "  /boot:       $(if $BOOT_SEPARATE; then echo "separate (${BOOT_FREE_MB}MB free)"; else echo "not separate"; fi)"
    echo ""
    
    if [[ "$CRITICAL_ANOMALY" == "true" ]]; then
        echo -e "${RED}⛔ CRITICAL ANOMALY - Some operations will be SKIPPED${NC}"
        echo ""
        read -r -p "Continue in safe mode? (y/N) " response
        [[ ! "$response" =~ ^[Yy] ]] && exit 1
    else
        read -r -p "Continue? (Y/n) " response
        [[ "$response" =~ ^[Nn] ]] && exit 0
    fi
}

create_backup() {
    log_header "Backup"
    
    BACKUP_DIR="/root/hibernate-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    cp /etc/fstab "$BACKUP_DIR/"
    [[ -f /etc/default/grub ]] && cp /etc/default/grub "$BACKUP_DIR/"
    [[ -f /etc/kernel/cmdline ]] && cp /etc/kernel/cmdline "$BACKUP_DIR/"
    [[ -d /etc/dracut.conf.d ]] && cp -r /etc/dracut.conf.d "$BACKUP_DIR/"
    
    log_success "Backup: $BACKUP_DIR"
}

#───────────────────────────────────────────────────────────────────────────────
# SUMMARY
#───────────────────────────────────────────────────────────────────────────────

print_summary() {
    generate_diagnostic_report
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     ${BOLD}HIBERNATE v${SCRIPT_VERSION} - RESULT REPORT${NC}${CYAN}                              ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    
    echo -e "${CYAN}║${NC}  ${GREEN}Successful: ${#SUCCESSFUL_OPERATIONS[@]}${NC}                                                  ${CYAN}║${NC}"
    for op in "${SUCCESSFUL_OPERATIONS[@]}"; do
        echo -e "${CYAN}║${NC}    ${GREEN}✓${NC} $op              ${CYAN}║${NC}"
    done
    
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]]; then
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}Skipped: ${#SKIPPED_OPERATIONS[@]}${NC}                                                    ${CYAN}║${NC}"
    fi
    
    if [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo -e "${CYAN}║${NC}  ${RED}Anomaliler: $ANOMALY_COUNT${NC}                                                  ${CYAN}║${NC}"
    fi
    
    echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]] || [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo -e "${CYAN}║${NC}  ${BOLD}📋 DETAILED REPORT:${NC}                                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  $REPORT_FILE${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Send this report to your AI assistant!                                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                       ${CYAN}║${NC}"
    fi
    
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}⚠️  REBOOT REQUIRED${NC}                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Then: hibernate-test                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ ${#SKIPPED_OPERATIONS[@]} -gt 0 ]] || [[ $ANOMALY_COUNT -gt 0 ]]; then
        read -r -p "View report? (y/N) " response
        [[ "$response" =~ ^[Yy] ]] && cat "$REPORT_FILE"
    fi
    
    echo ""
    read -r -p "Reboot? (y/N) " response
    [[ "$response" =~ ^[Yy] ]] && { sleep 2; reboot; }
}

#───────────────────────────────────────────────────────────────────────────────
# STATUS & DIAGNOSE
#───────────────────────────────────────────────────────────────────────────────

show_status() {
    echo ""
    echo -e "${BOLD}HIBERNATE v${SCRIPT_VERSION} STATUS${NC}"
    echo ""
    
    echo "=== KERNEL PARAMS ==="
    cat /proc/cmdline | tr ' ' '\n' | grep -E "resume" || echo "resume param YOK!"
    echo ""
    
    echo "=== SWAP ==="
    swapon --show
    echo ""
    
    echo "=== /sys/power ==="
    echo -n "state: "; cat /sys/power/state 2>/dev/null || echo "N/A"
    echo -n "disk:  "; cat /sys/power/disk 2>/dev/null || echo "N/A"
    echo ""
    
    if grep -q "resume=" /proc/cmdline && grep -q "disk" /sys/power/state 2>/dev/null; then
        echo -e "${GREEN}✓ Hibernate ready${NC}"
    else
        echo -e "${YELLOW}⚠ Hibernate not fully configured${NC}"
    fi
}

run_diagnose() {
    echo ""
    echo -e "${BOLD}HIBERNATE v${SCRIPT_VERSION} - TANILAMA${NC}"
    echo ""
    
    detect_bootloader_safe
    detect_init_system_safe
    check_boot_space_safe
    
    echo ""
    echo "=== SUMMARY ==="
    echo "Bootloader: $DETECTED_BOOTLOADER ($BOOTLOADER_CONFIDENCE)"
    echo "Init: $DETECTED_INIT_SYSTEM"
    echo "/boot: $(if $BOOT_SEPARATE; then echo "${BOOT_FREE_MB}MB free"; else echo "not separate"; fi)"
    echo ""
    
    if [[ $ANOMALY_COUNT -gt 0 ]]; then
        echo "=== ANOMALIES: $ANOMALY_COUNT ==="
        for anomaly in "${ANOMALIES[@]}"; do
            echo "$anomaly"
        done
    else
        echo -e "${GREEN}✓ No anomalies${NC}"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# HELP & MAIN
#───────────────────────────────────────────────────────────────────────────────

show_help() {
    echo ""
    echo -e "${BOLD}Hibernate Setup v${SCRIPT_VERSION} - Fail-Safe Edition${NC}"
    echo ""
    echo "Usage: sudo $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  (no parameter)  Install"
    echo "  --status         Status"
    echo "  --diagnose       Diagnostics (root not required)"
    echo "  --help           Help"
    echo ""
}

main() {
    case "${1:-}" in
        --status)   show_status ;;
        --diagnose) run_diagnose ;;
        --help|-h)  show_help ;;
        "")
            echo ""
            echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║${NC}  ${BOLD}HIBERNATE SETUP v${SCRIPT_VERSION}${NC} - Fail-Safe Edition                     ${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  Stops on unknown situations | AI-Ready Diagnostic Reports             ${CYAN}║${NC}"
            echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
            
            preflight_checks
            create_backup
            calculate_swap_size_safe
            create_swapfile_safe
            calculate_resume_offset_safe
            configure_kernel_params_safe
            configure_initramfs_safe
            configure_systemd_safe
            create_helper_scripts_safe
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
