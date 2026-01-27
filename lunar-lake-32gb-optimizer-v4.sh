#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#
#   ██╗     ██╗   ██╗███╗   ██╗ █████╗ ██████╗     ██╗      █████╗ ██╗  ██╗███████╗
#   ██║     ██║   ██║████╗  ██║██╔══██╗██╔══██╗    ██║     ██╔══██╗██║ ██╔╝██╔════╝
#   ██║     ██║   ██║██╔██╗ ██║███████║██████╔╝    ██║     ███████║█████╔╝ █████╗  
#   ██║     ██║   ██║██║╚██╗██║██╔══██║██╔══██╗    ██║     ██╔══██║██╔═██╗ ██╔══╝  
#   ███████╗╚██████╔╝██║ ╚████║██║  ██║██║  ██║    ███████╗██║  ██║██║  ██╗███████╗
#   ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝
#
#   LUNAR LAKE 32GB - FEDORA 43 SYSTEM OPTIMIZATION SCRIPT
#   Version: 4.0.0 (Production-Grade, 16GB ZRAM + 8GB Disk Swap Fallback)
#   Date: 2026-01-27
#
#   Target: Intel Lunar Lake (Core Ultra 200V) + 32GB LPDDR5X + Fedora 43
#
#═══════════════════════════════════════════════════════════════════════════════
#
#   CHANGELOG v4.0.0:
#   ─────────────────────────────────────────────────────────────────────────────
#   • NEW: 8GB Disk Swap Fallback (priority 10) - OOM prevention
#   • Three-tier swap architecture: RAM → ZRAM → Disk Swap → OOM Killer
#   • Enhanced monitoring with swap tier detection
#   • Improved verification script with fallback status
#   • Optional --no-disk-swap flag for ZRAM-only configuration
#
#   SWAP ARCHITECTURE v4.0:
#   ─────────────────────────────────────────────────────────────────────────────
#
#   ┌─────────────────────────────────────────────────────────────────────────┐
#   │                         MEMORY HIERARCHY v4.0                           │
#   ├─────────────────────────────────────────────────────────────────────────┤
#   │                                                                         │
#   │   TIER 1: Physical RAM (32GB)                                          │
#   │           └── Primary working memory, Latency: ~100 ns                 │
#   │                        │                                                │
#   │                        ▼ (memory pressure)                              │
#   │                                                                         │
#   │   TIER 2: ZRAM Swap (16GB, priority 100)                               │
#   │           └── Compressed RAM swap, ~1μs latency                        │
#   │           └── With 3:1 compression: ~48GB effective                    │
#   │                        │                                                │
#   │                        ▼ (ZRAM exhausted)                               │
#   │                                                                         │
#   │   TIER 3: Disk Swap (8GB, priority 10) ← NEW in v4.0                   │
#   │           └── NVMe/SSD fallback, ~150μs latency                        │
#   │           └── Emergency buffer, prevents OOM                           │
#   │                        │                                                │
#   │                        ▼ (all swap exhausted)                           │
#   │                                                                         │
#   │   TIER 4: OOM Killer                                                   │
#   │           └── Last resort, kills highest oom_score process             │
#   │                                                                         │
#   └─────────────────────────────────────────────────────────────────────────┘
#
#   EFFECTIVE CAPACITY:
#   ─────────────────────────────────────────────────────────────────────────────
#   Physical RAM:     32 GB
#   ZRAM (3:1):      ~48 GB effective
#   Disk Swap:         8 GB
#   ─────────────────────────────────────────────────────────────────────────────
#   TOTAL:           ~88 GB effective (before OOM)
#
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'\n\t'

#───────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
#───────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_NAME="lunar-lake-optimizer"
readonly SCRIPT_VERSION="4.0.0"
readonly LOG_FILE="/var/log/${SCRIPT_NAME}.log"
readonly BACKUP_DIR="/var/backup/${SCRIPT_NAME}/$(date +%Y%m%d_%H%M%S)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# System requirements
readonly MIN_KERNEL_MAJOR=6
readonly MIN_KERNEL_MINOR=12
readonly MIN_RAM_GB=16
readonly TARGET_RAM_GB=32

# ZRAM Configuration (Tier 2)
readonly ZRAM_FRACTION="ram / 2"
readonly ZRAM_MAX_SIZE=16384
readonly ZRAM_ALGORITHM="zstd"
readonly ZRAM_PRIORITY=100

# Disk Swap Configuration (Tier 3) - NEW in v4.0
readonly DISK_SWAP_SIZE_GB=8
readonly DISK_SWAP_FILE="/swapfile"
readonly DISK_SWAP_PRIORITY=10
readonly DISK_SWAP_MIN_FREE_GB=20

# Sysctl values
declare -A SYSCTL_VALUES=(
    ["vm.swappiness"]=180
    ["vm.watermark_boost_factor"]=0
    ["vm.watermark_scale_factor"]=125
    ["vm.page-cluster"]=0
    ["vm.vfs_cache_pressure"]=50
    ["vm.dirty_ratio"]=10
    ["vm.dirty_background_ratio"]=5
)

# Global flags
ENABLE_DISK_SWAP=true

#───────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}" 2>/dev/null || true
}

log_info() {
    log "INFO" "$1"
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "SUCCESS" "$1"
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    log "WARN" "$1"
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    log "ERROR" "$1"
    echo -e "${RED}[✗]${NC} $1" >&2
}

log_section() {
    local title="$1"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $title${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    log "SECTION" "$title"
}

log_detail() {
    log "DETAIL" "$1"
    echo -e "${MAGENTA}    → $1${NC}"
}

#───────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Bu script root olarak çalıştırılmalı"
        log_error "Kullanım: sudo $0"
        exit 1
    fi
}

create_backup_dir() {
    mkdir -p "${BACKUP_DIR}"
    log_info "Backup dizini oluşturuldu: ${BACKUP_DIR}"
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp -p "$file" "${BACKUP_DIR}/$(basename "$file").backup"
        log_info "Backup: $file"
    fi
}

get_kernel_version() { uname -r | cut -d'-' -f1; }
get_kernel_major() { get_kernel_version | cut -d'.' -f1; }
get_kernel_minor() { get_kernel_version | cut -d'.' -f2; }
get_ram_gb() { awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo; }
get_root_free_gb() { df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}'; }
is_lunar_lake() { grep -q "Lunar Lake\|Core Ultra.*2[0-9][0-9]V" /proc/cpuinfo 2>/dev/null; }
is_fedora() { [[ -f /etc/fedora-release ]]; }
get_fedora_version() { grep -oP '\d+' /etc/fedora-release | head -1; }

calculate_expected_zram() {
    local ram_gb
    ram_gb=$(get_ram_gb)
    local expected=$((ram_gb / 2))
    [[ $expected -gt $((ZRAM_MAX_SIZE / 1024)) ]] && expected=$((ZRAM_MAX_SIZE / 1024))
    echo "$expected"
}

#───────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT CHECKS
#───────────────────────────────────────────────────────────────────────────────

preflight_checks() {
    log_section "PRE-FLIGHT CHECKS"
    
    local checks_passed=0
    local checks_total=0
    local warnings=0
    
    # Check 1: Fedora
    ((checks_total++))
    if is_fedora; then
        local fedora_ver
        fedora_ver=$(get_fedora_version)
        log_success "Fedora ${fedora_ver} tespit edildi"
        ((checks_passed++))
    else
        log_error "Bu script Fedora için tasarlandı"
        return 1
    fi
    
    # Check 2: Kernel version
    ((checks_total++))
    local kernel_major kernel_minor
    kernel_major=$(get_kernel_major)
    kernel_minor=$(get_kernel_minor)
    
    if [[ $kernel_major -gt $MIN_KERNEL_MAJOR ]] || \
       [[ $kernel_major -eq $MIN_KERNEL_MAJOR && $kernel_minor -ge $MIN_KERNEL_MINOR ]]; then
        log_success "Kernel $(get_kernel_version) yeterli (min: ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR})"
        ((checks_passed++))
    else
        log_error "Kernel $(get_kernel_version) çok eski (min: ${MIN_KERNEL_MAJOR}.${MIN_KERNEL_MINOR})"
        return 1
    fi
    
    # Check 3: RAM
    ((checks_total++))
    local ram_gb expected_zram
    ram_gb=$(get_ram_gb)
    expected_zram=$(calculate_expected_zram)
    
    if [[ $ram_gb -ge $MIN_RAM_GB ]]; then
        log_success "RAM: ${ram_gb}GB tespit edildi"
        log_detail "Beklenen ZRAM boyutu: ${expected_zram}GB (ram / 2)"
        ((checks_passed++))
        [[ $ram_gb -ne $TARGET_RAM_GB ]] && log_warn "Script 32GB RAM için optimize edildi" && ((warnings++))
    else
        log_error "Yetersiz RAM: ${ram_gb}GB (min: ${MIN_RAM_GB}GB)"
        return 1
    fi
    
    # Check 4: CPU
    ((checks_total++))
    if is_lunar_lake; then
        log_success "Intel Lunar Lake CPU tespit edildi"
        log_detail "LPDDR5X on-package memory avantajı: Ultra-low latency"
    else
        log_warn "Lunar Lake CPU tespit edilemedi - generic Intel/AMD olabilir"
        ((warnings++))
    fi
    ((checks_passed++))
    
    # Check 5: Required packages
    ((checks_total++))
    local missing_packages=()
    for pkg in zram-generator-defaults grubby util-linux; do
        rpm -q "$pkg" &>/dev/null || missing_packages+=("$pkg")
    done
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_success "Gerekli paketler mevcut"
    else
        log_warn "Eksik paketler: ${missing_packages[*]}"
        log_info "Kurulum sırasında yüklenecek"
        ((warnings++))
    fi
    ((checks_passed++))
    
    # Check 6: Xe graphics driver
    ((checks_total++))
    if lsmod | grep -q "^xe "; then
        log_success "Intel Xe graphics driver aktif"
    elif is_lunar_lake; then
        log_warn "Xe graphics driver aktif değil"
        ((warnings++))
    else
        log_info "Xe graphics driver kontrolü atlandı"
    fi
    ((checks_passed++))
    
    # Check 7: ZSWAP status
    ((checks_total++))
    if [[ -f /sys/module/zswap/parameters/enabled ]]; then
        local zswap_enabled
        zswap_enabled=$(cat /sys/module/zswap/parameters/enabled)
        if [[ "$zswap_enabled" == "Y" ]]; then
            log_warn "ZSWAP aktif - ZRAM ile conflict yaratabilir"
            log_info "Script ZSWAP'ı devre dışı bırakacak"
            ((warnings++))
        else
            log_success "ZSWAP zaten devre dışı"
        fi
    else
        log_info "ZSWAP modülü yüklü değil"
    fi
    ((checks_passed++))
    
    # Check 8: Existing ZRAM
    ((checks_total++))
    if [[ -b /dev/zram0 ]]; then
        local current_zram_size
        current_zram_size=$(zramctl -o SIZE -n -b /dev/zram0 2>/dev/null || echo "0")
        current_zram_size=$((current_zram_size / 1024 / 1024 / 1024))
        log_info "Mevcut ZRAM: ${current_zram_size}GB"
        [[ $current_zram_size -lt $expected_zram ]] && log_detail "ZRAM boyutu ${expected_zram}GB'a yükseltilecek"
    else
        log_info "ZRAM henüz yapılandırılmamış"
    fi
    ((checks_passed++))
    
    # Check 9: Disk space for swap (NEW in v4.0)
    ((checks_total++))
    if $ENABLE_DISK_SWAP; then
        local root_free_gb
        root_free_gb=$(get_root_free_gb)
        local required_space=$((DISK_SWAP_SIZE_GB + DISK_SWAP_MIN_FREE_GB))
        
        if [[ ${root_free_gb:-0} -ge $required_space ]]; then
            log_success "Disk alanı yeterli: ${root_free_gb}GB free (min: ${required_space}GB)"
        else
            log_warn "Disk alanı düşük: ${root_free_gb}GB"
            ((warnings++))
        fi
    else
        log_info "Disk swap devre dışı bırakıldı (--no-disk-swap)"
    fi
    ((checks_passed++))
    
    # Check 10: Existing swapfile
    ((checks_total++))
    if [[ -f "$DISK_SWAP_FILE" ]]; then
        local existing_size
        existing_size=$(stat -c%s "$DISK_SWAP_FILE" 2>/dev/null || echo "0")
        existing_size=$((existing_size / 1024 / 1024 / 1024))
        log_info "Mevcut swapfile: ${existing_size}GB"
        [[ $existing_size -ne $DISK_SWAP_SIZE_GB ]] && log_detail "Swapfile ${DISK_SWAP_SIZE_GB}GB olarak yeniden oluşturulacak"
    else
        log_info "Swapfile mevcut değil, oluşturulacak"
    fi
    ((checks_passed++))
    
    # Summary
    echo ""
    echo -e "Pre-flight sonucu: ${GREEN}${checks_passed}/${checks_total}${NC} checks passed"
    [[ $warnings -gt 0 ]] && echo -e "Uyarılar: ${YELLOW}${warnings}${NC}"
    
    [[ $checks_passed -ne $checks_total ]] && log_error "Pre-flight checks başarısız!" && return 1
    return 0
}

#───────────────────────────────────────────────────────────────────────────────
# INSTALLATION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

install_packages() {
    log_section "PAKET KURULUMU"
    
    local packages=("zram-generator-defaults" "grubby" "util-linux")
    local to_install=()
    
    for pkg in "${packages[@]}"; do
        rpm -q "$pkg" &>/dev/null || to_install+=("$pkg")
    done
    
    if [[ ${#to_install[@]} -gt 0 ]]; then
        log_info "Paketler kuruluyor: ${to_install[*]}"
        dnf install -y "${to_install[@]}"
        log_success "Paketler kuruldu"
    else
        log_success "Tüm paketler zaten kurulu"
    fi
}

configure_zram() {
    log_section "ZRAM YAPILANDIRMASI (Tier 2: 16GB)"
    
    local zram_conf="/etc/systemd/zram-generator.conf"
    local ram_gb expected_zram
    ram_gb=$(get_ram_gb)
    expected_zram=$(calculate_expected_zram)
    
    backup_file "$zram_conf"
    
    log_info "ZRAM konfigürasyonu oluşturuluyor..."
    log_detail "RAM: ${ram_gb}GB"
    log_detail "ZRAM boyutu: ${expected_zram}GB (ram / 2)"
    log_detail "Compression: ${ZRAM_ALGORITHM}"
    log_detail "Priority: ${ZRAM_PRIORITY} (highest)"
    
    cat > "$zram_conf" << EOF
#═══════════════════════════════════════════════════════════════════════════════
# Lunar Lake 32GB ZRAM Optimization - v4.0.0
# Generated by ${SCRIPT_NAME} v${SCRIPT_VERSION}
# Date: $(date -Iseconds)
#═══════════════════════════════════════════════════════════════════════════════
#
# THREE-TIER SWAP ARCHITECTURE (v4.0):
#   Tier 1: Physical RAM (32GB)           - Primary
#   Tier 2: ZRAM (16GB, priority 100)     - Fast compressed swap  ← THIS FILE
#   Tier 3: Disk Swap (8GB, priority 10)  - Emergency fallback
#   Tier 4: OOM Killer                    - Last resort
#
#═══════════════════════════════════════════════════════════════════════════════

[zram0]
zram-size = ${ZRAM_FRACTION}
max-zram-size = ${ZRAM_MAX_SIZE}
compression-algorithm = ${ZRAM_ALGORITHM}
swap-priority = ${ZRAM_PRIORITY}
fs-type = swap
EOF
    
    log_success "ZRAM konfigürasyonu oluşturuldu: $zram_conf"
    
    echo ""
    echo -e "  ┌────────────────────────────────────────────┐"
    echo -e "  │ ZRAM Konfigürasyonu (Tier 2)               │"
    echo -e "  ├────────────────────────────────────────────┤"
    echo -e "  │ Boyut:      ${GREEN}${expected_zram}GB${NC} (ram / 2)              │"
    echo -e "  │ Max:        ${ZRAM_MAX_SIZE}MB                        │"
    echo -e "  │ Algorithm:  ${ZRAM_ALGORITHM}                          │"
    echo -e "  │ Priority:   ${GREEN}${ZRAM_PRIORITY}${NC} (highest)                 │"
    echo -e "  └────────────────────────────────────────────┘"
    echo ""
}

configure_disk_swap() {
    log_section "DISK SWAP YAPILANDIRMASI (Tier 3: ${DISK_SWAP_SIZE_GB}GB)"
    
    if ! $ENABLE_DISK_SWAP; then
        log_info "Disk swap devre dışı bırakıldı (--no-disk-swap)"
        log_info "Sadece ZRAM kullanılacak"
        
        if [[ -f "$DISK_SWAP_FILE" ]]; then
            log_info "Mevcut swapfile kaldırılıyor..."
            swapoff "$DISK_SWAP_FILE" 2>/dev/null || true
            rm -f "$DISK_SWAP_FILE"
            sed -i "\|$DISK_SWAP_FILE|d" /etc/fstab 2>/dev/null || true
            log_success "Swapfile kaldırıldı"
        fi
        return 0
    fi
    
    log_info "Disk swap fallback oluşturuluyor..."
    log_detail "Boyut: ${DISK_SWAP_SIZE_GB}GB"
    log_detail "Konum: ${DISK_SWAP_FILE}"
    log_detail "Priority: ${DISK_SWAP_PRIORITY} (lower than ZRAM)"
    
    # Check disk space
    local root_free_gb
    root_free_gb=$(get_root_free_gb)
    local required_space=$((DISK_SWAP_SIZE_GB + DISK_SWAP_MIN_FREE_GB))
    
    if [[ ${root_free_gb:-0} -lt $required_space ]]; then
        log_warn "Yetersiz disk alanı: ${root_free_gb}GB (min: ${required_space}GB)"
        log_warn "Disk swap oluşturulmadı, sadece ZRAM kullanılacak"
        return 0
    fi
    
    backup_file /etc/fstab
    
    # Check if swapfile already exists with correct size
    if [[ -f "$DISK_SWAP_FILE" ]]; then
        local existing_size
        existing_size=$(stat -c%s "$DISK_SWAP_FILE" 2>/dev/null || echo "0")
        existing_size=$((existing_size / 1024 / 1024 / 1024))
        
        if [[ $existing_size -eq $DISK_SWAP_SIZE_GB ]]; then
            log_info "Swapfile zaten doğru boyutta: ${existing_size}GB"
            
            if swapon --show | grep -q "$DISK_SWAP_FILE"; then
                local current_priority
                current_priority=$(swapon --show=PRIO --noheadings "$DISK_SWAP_FILE" 2>/dev/null || echo "?")
                log_info "Swapfile aktif, priority: ${current_priority}"
                
                if [[ "$current_priority" != "$DISK_SWAP_PRIORITY" ]]; then
                    log_info "Priority güncelleniyor: ${current_priority} → ${DISK_SWAP_PRIORITY}"
                    swapoff "$DISK_SWAP_FILE"
                    swapon --priority="$DISK_SWAP_PRIORITY" "$DISK_SWAP_FILE"
                fi
            else
                swapon --priority="$DISK_SWAP_PRIORITY" "$DISK_SWAP_FILE"
            fi
        else
            log_info "Swapfile yeniden boyutlandırılıyor: ${existing_size}GB → ${DISK_SWAP_SIZE_GB}GB"
            swapoff "$DISK_SWAP_FILE" 2>/dev/null || true
            rm -f "$DISK_SWAP_FILE"
            _create_swapfile
        fi
    else
        log_info "Yeni swapfile oluşturuluyor..."
        _create_swapfile
    fi
    
    # Update fstab
    sed -i "\|$DISK_SWAP_FILE|d" /etc/fstab 2>/dev/null || true
    echo "${DISK_SWAP_FILE} none swap sw,pri=${DISK_SWAP_PRIORITY} 0 0" >> /etc/fstab
    log_detail "fstab güncellendi"
    
    log_success "Disk swap konfigürasyonu tamamlandı"
    
    echo ""
    echo -e "  ┌────────────────────────────────────────────┐"
    echo -e "  │ Disk Swap Konfigürasyonu (Tier 3)          │"
    echo -e "  ├────────────────────────────────────────────┤"
    echo -e "  │ Boyut:      ${GREEN}${DISK_SWAP_SIZE_GB}GB${NC}                          │"
    echo -e "  │ Dosya:      ${DISK_SWAP_FILE}                      │"
    echo -e "  │ Priority:   ${YELLOW}${DISK_SWAP_PRIORITY}${NC} (fallback only)           │"
    echo -e "  └────────────────────────────────────────────┘"
    echo ""
}

_create_swapfile() {
    log_detail "Swapfile oluşturuluyor (${DISK_SWAP_SIZE_GB}GB)..."
    
    if fallocate -l "${DISK_SWAP_SIZE_GB}G" "$DISK_SWAP_FILE" 2>/dev/null; then
        log_detail "fallocate ile oluşturuldu"
    else
        log_detail "dd ile oluşturuluyor (daha yavaş)..."
        dd if=/dev/zero of="$DISK_SWAP_FILE" bs=1G count="$DISK_SWAP_SIZE_GB" status=progress
    fi
    
    chmod 600 "$DISK_SWAP_FILE"
    log_detail "İzinler ayarlandı: 600 (root only)"
    
    mkswap "$DISK_SWAP_FILE"
    log_detail "Swap formatlandı"
    
    swapon --priority="$DISK_SWAP_PRIORITY" "$DISK_SWAP_FILE"
    log_detail "Swap aktifleştirildi (priority: ${DISK_SWAP_PRIORITY})"
}

configure_sysctl() {
    log_section "SYSCTL YAPILANDIRMASI"
    
    local sysctl_conf="/etc/sysctl.d/99-zram-lunar-lake.conf"
    
    backup_file "$sysctl_conf"
    backup_file "/etc/sysctl.d/99-sysctl.conf"
    backup_file "/etc/sysctl.d/99-zram.conf"
    
    for old_conf in "/etc/sysctl.d/99-sysctl.conf" "/etc/sysctl.d/99-zram.conf"; do
        [[ -f "$old_conf" ]] && log_warn "Eski konfigürasyon kaldırılıyor: $old_conf" && rm -f "$old_conf"
    done
    
    log_info "Sysctl konfigürasyonu oluşturuluyor..."
    
    cat > "$sysctl_conf" << 'EOF'
#═══════════════════════════════════════════════════════════════════════════════
# Lunar Lake 32GB - ZRAM + Disk Swap Optimized Sysctl Configuration v4.0.0
#═══════════════════════════════════════════════════════════════════════════════

# ZRAM OPTIMIZATION
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0

# 32GB RAM OPTIMIZATION
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
    
    log_success "Sysctl konfigürasyonu oluşturuldu: $sysctl_conf"
    
    log_info "Sysctl ayarları uygulanıyor..."
    sysctl -p "$sysctl_conf"
    
    log_info "Uygulanan değerler:"
    for key in "${!SYSCTL_VALUES[@]}"; do
        local current expected
        current=$(sysctl -n "$key" 2>/dev/null || echo "N/A")
        expected="${SYSCTL_VALUES[$key]}"
        if [[ "$current" == "$expected" ]]; then
            echo -e "  ${GREEN}✓${NC} $key = $current"
        else
            echo -e "  ${RED}✗${NC} $key = $current (expected: $expected)"
        fi
    done
    
    log_success "Sysctl ayarları uygulandı"
}

disable_zswap() {
    log_section "ZSWAP DEVRE DIŞI BIRAKMA"
    
    log_info "ZSWAP ve ZRAM neden birlikte çalışmaz:"
    log_detail "ZSWAP: Disk swap önünde bir cache katmanı"
    log_detail "ZRAM: RAM'de bir swap cihazı"
    log_detail "ZSWAP aktifken, ZRAM'a yazılacak pages intercept edilir"
    
    if grep -q "zswap.enabled=0" /proc/cmdline; then
        log_success "ZSWAP zaten kernel parametresiyle devre dışı"
        return 0
    fi
    
    log_info "ZSWAP devre dışı bırakılıyor..."
    grubby --update-kernel=ALL --args="zswap.enabled=0"
    
    log_success "ZSWAP kernel parametresi eklendi"
    log_warn "Tam etki için REBOOT gerekli"
    
    [[ -f /sys/module/zswap/parameters/enabled ]] && echo N > /sys/module/zswap/parameters/enabled 2>/dev/null || true
}

#───────────────────────────────────────────────────────────────────────────────
# VERIFICATION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

verify_installation() {
    log_section "KURULUM DOĞRULAMA"
    
    local passed=0 failed=0
    
    echo -n "  ZRAM konfigürasyonu: "
    [[ -f /etc/systemd/zram-generator.conf ]] && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    echo -n "  Sysctl konfigürasyonu: "
    [[ -f /etc/sysctl.d/99-zram-lunar-lake.conf ]] && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    echo -n "  ZSWAP kernel parametresi: "
    grubby --info=ALL | grep -q "zswap.enabled=0" && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    echo -n "  Sysctl değerleri: "
    local sysctl_ok=true
    for key in "${!SYSCTL_VALUES[@]}"; do
        local current expected
        current=$(sysctl -n "$key" 2>/dev/null || echo "")
        expected="${SYSCTL_VALUES[$key]}"
        [[ "$current" != "$expected" ]] && sysctl_ok=false && break
    done
    $sysctl_ok && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    echo -n "  ZRAM ram/2 konfigürasyonu: "
    grep -q "ram / 2" /etc/systemd/zram-generator.conf 2>/dev/null && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    echo -n "  Max ZRAM size (16GB): "
    grep -q "max-zram-size = 16384" /etc/systemd/zram-generator.conf 2>/dev/null && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    
    if $ENABLE_DISK_SWAP; then
        echo -n "  Disk swap (${DISK_SWAP_SIZE_GB}GB): "
        [[ -f "$DISK_SWAP_FILE" ]] && swapon --show | grep -q "$DISK_SWAP_FILE" && echo -e "${GREEN}OK${NC}" && ((passed++)) || echo -e "${YELLOW}WARN${NC} (will work after reboot)"
        
        echo -n "  Disk swap fstab entry: "
        grep -q "$DISK_SWAP_FILE" /etc/fstab && echo -e "${GREEN}OK${NC}" && ((passed++)) || { echo -e "${RED}FAIL${NC}"; ((failed++)); }
    fi
    
    echo ""
    echo -e "Doğrulama sonucu: ${GREEN}${passed}${NC} passed, ${RED}${failed}${NC} failed"
    
    [[ $failed -gt 0 ]] && log_error "Bazı doğrulama testleri başarısız!" && return 1
    return 0
}

show_post_reboot_status() {
    log_section "REBOOT SONRASI BEKLENEN DURUM"
    
    local expected_zram
    expected_zram=$(calculate_expected_zram)
    
    cat << EOF

Reboot sonrası beklenen değerler:

┌──────────────────────────────────────────────────────────────────┐
│ SWAP HIERARCHY v4.0 (Priority Order)                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   [1] ZRAM      → 16GB  → Priority 100 (PRIMARY)                │
│   [2] Disk Swap →  8GB  → Priority  10 (FALLBACK)               │
│                                                                  │
│   Kernel önce yüksek priority'li swap kullanır.                 │
│   Disk swap SADECE ZRAM dolduktan sonra devreye girer.          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ SWAP STATUS                                                      │
├──────────────────────────────────────────────────────────────────┤
│ Komut: swapon --show                                             │
│                                                                  │
│ NAME       TYPE      SIZE USED PRIO                              │
│ /dev/zram0 partition ${expected_zram}G   0B  100   ← ZRAM (primary)     │
│ /swapfile  file       8G   0B   10   ← Disk (fallback)          │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ SYSCTL VALUES                                                    │
├──────────────────────────────────────────────────────────────────┤
│ vm.swappiness = 180                                              │
│ vm.page-cluster = 0                                              │
│ vm.vfs_cache_pressure = 50                                       │
└──────────────────────────────────────────────────────────────────┘

Doğrulama scripti: sudo lunar-lake-verify.sh

EOF
}

create_verification_script() {
    log_section "DOĞRULAMA SCRİPTİ OLUŞTURMA"
    
    local verify_script="/usr/local/bin/lunar-lake-verify.sh"
    
    cat > "$verify_script" << 'VERIFY_EOF'
#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# Lunar Lake 32GB System Verification Script v4.0.0
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
passed=0; failed=0; warnings=0

check() {
    local name="$1" expected="$2" actual="$3"
    printf "  %-35s" "$name:"
    [[ "$actual" == "$expected" ]] && { echo -e "${GREEN}✓ $actual${NC}"; ((passed++)); } || { echo -e "${RED}✗ $actual (expected: $expected)${NC}"; ((failed++)); }
}

check_ge() {
    local name="$1" minimum="$2" actual="$3"
    printf "  %-35s" "$name:"
    [[ "$actual" -ge "$minimum" ]] && { echo -e "${GREEN}✓ $actual (min: $minimum)${NC}"; ((passed++)); } || { echo -e "${RED}✗ $actual (min: $minimum)${NC}"; ((failed++)); }
}

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  LUNAR LAKE 32GB SYSTEM VERIFICATION v4.0.0${NC}"
echo -e "${BLUE}  Three-Tier Swap: ZRAM (16GB) + Disk (8GB)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

echo ""
echo -e "${BLUE}[1] KERNEL${NC}"
kernel_minor=$(uname -r | cut -d'-' -f1 | cut -d'.' -f2)
check_ge "Kernel version (min 6.12)" "12" "$kernel_minor"

echo ""
echo -e "${BLUE}[2] MEMORY${NC}"
ram_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
check_ge "RAM (min 16GB)" "16" "$ram_gb"

echo ""
echo -e "${BLUE}[3] ZRAM STATUS (Tier 2 - Primary)${NC}"
if [[ -b /dev/zram0 ]]; then
    zram_size_gb=$(zramctl -o SIZE -n -b /dev/zram0 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
    expected_zram=$((ram_gb / 2)); [[ $expected_zram -gt 16 ]] && expected_zram=16
    check_ge "ZRAM size (expected ${expected_zram}GB)" "$expected_zram" "$zram_size_gb"
    
    zram_algo=$(zramctl -o ALGORITHM -n /dev/zram0 2>/dev/null || echo "unknown")
    check "ZRAM algorithm" "zstd" "$zram_algo"
    
    zram_prio=$(swapon --show=PRIO --noheadings /dev/zram0 2>/dev/null || echo "?")
    check "ZRAM priority" "100" "$zram_prio"
    
    if [[ -f /sys/block/zram0/mm_stat ]]; then
        read -r orig compr mem_used rest < /sys/block/zram0/mm_stat
        if [[ "$compr" -gt 0 ]]; then
            ratio=$(awk "BEGIN {printf \"%.2f\", $orig / $compr}")
            used_mb=$(awk "BEGIN {printf \"%.0f\", $mem_used / 1048576}")
            echo -e "  Compression ratio:                ${CYAN}${ratio}:1${NC}"
            echo -e "  Actual RAM used:                  ${CYAN}${used_mb} MB${NC}"
        fi
    fi
else
    echo -e "  ZRAM device:                      ${RED}✗ Not found${NC}"; ((failed++))
fi

echo ""
echo -e "${BLUE}[4] DISK SWAP STATUS (Tier 3 - Fallback)${NC}"
if [[ -f /swapfile ]]; then
    swap_size=$(($(stat -c%s /swapfile 2>/dev/null || echo "0") / 1024 / 1024 / 1024))
    check "Disk swap size" "8" "$swap_size"
    
    if swapon --show | grep -q "/swapfile"; then
        disk_prio=$(swapon --show=PRIO --noheadings /swapfile 2>/dev/null || echo "?")
        check "Disk swap priority" "10" "$disk_prio"
        
        disk_used=$(swapon --show=USED --noheadings /swapfile 2>/dev/null || echo "0B")
        echo -e "  Disk swap used:                   ${CYAN}${disk_used}${NC}"
        [[ "$disk_used" != "0B" ]] && [[ "$disk_used" != "0" ]] && echo -e "  ${YELLOW}! Disk swap in use - memory pressure high${NC}" || echo -e "  ${GREEN}✓ Disk swap idle (normal operation)${NC}"
    else
        echo -e "  Disk swap active:                 ${YELLOW}! Not active${NC}"; ((warnings++))
    fi
else
    echo -e "  Disk swap file:                   ${YELLOW}! Not found (ZRAM only mode)${NC}"; ((warnings++))
fi

echo ""
echo -e "${BLUE}[5] SWAP HIERARCHY SUMMARY${NC}"
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │ Tier │ Device      │ Size   │ Priority │ Status        │"
echo "  ├──────┼─────────────┼────────┼──────────┼───────────────┤"
[[ -b /dev/zram0 ]] && swapon --show | grep -q "zram0" && echo -e "  │  2   │ ZRAM        │ ${zram_size_gb:-?}GB    │ ${zram_prio:-?}       │ ${GREEN}Active${NC}        │" || echo -e "  │  2   │ ZRAM        │ ?      │ ?        │ ${RED}Missing${NC}       │"
[[ -f /swapfile ]] && swapon --show | grep -q "/swapfile" && echo -e "  │  3   │ Disk Swap   │ ${swap_size:-?}GB    │ ${disk_prio:-?}        │ ${GREEN}Standby${NC}       │" || echo -e "  │  3   │ Disk Swap   │ ?      │ ?        │ ${YELLOW}Disabled${NC}      │"
echo "  └─────────────────────────────────────────────────────────┘"

echo ""
echo -e "${BLUE}[6] ZSWAP STATUS${NC}"
[[ -f /sys/module/zswap/parameters/enabled ]] && check "ZSWAP disabled" "N" "$(cat /sys/module/zswap/parameters/enabled)" || { echo -e "  ZSWAP module:                     ${GREEN}✓ Not loaded${NC}"; ((passed++)); }

echo ""
echo -e "${BLUE}[7] SYSCTL VALUES${NC}"
check "vm.swappiness" "180" "$(sysctl -n vm.swappiness)"
check "vm.page-cluster" "0" "$(sysctl -n vm.page-cluster)"
check "vm.vfs_cache_pressure" "50" "$(sysctl -n vm.vfs_cache_pressure)"

echo ""
echo -e "${BLUE}[8] MEMORY PRESSURE (PSI)${NC}"
if [[ -f /proc/pressure/memory ]]; then
    psi_some=$(awk '/some/ {print $2}' /proc/pressure/memory | cut -d'=' -f2)
    psi_full=$(awk '/full/ {print $2}' /proc/pressure/memory | cut -d'=' -f2)
    echo -e "  PSI some avg10:                   ${CYAN}${psi_some}%${NC}"
    echo -e "  PSI full avg10:                   ${CYAN}${psi_full}%${NC}"
    psi_some_val=$(echo "$psi_some" | cut -d'.' -f1)
    [[ "${psi_some_val:-0}" -lt 5 ]] && echo -e "  ${GREEN}✓ Memory pressure: Low (healthy)${NC}" || [[ "${psi_some_val:-0}" -lt 25 ]] && echo -e "  ${YELLOW}! Memory pressure: Moderate${NC}" || echo -e "  ${RED}✗ Memory pressure: High${NC}"
fi

echo ""
echo -e "${BLUE}[9] CPU (Lunar Lake)${NC}"
grep -q "Lunar Lake\|Core Ultra.*2[0-9][0-9]V" /proc/cpuinfo 2>/dev/null && { echo -e "  CPU architecture:                 ${GREEN}✓ Lunar Lake detected${NC}"; ((passed++)); } || { echo -e "  CPU architecture:                 ${YELLOW}! Lunar Lake not detected${NC}"; ((warnings++)); }

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}, ${YELLOW}$warnings warnings${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

echo ""
echo -e "${CYAN}EFFECTIVE SWAP CAPACITY:${NC}"
echo "  Physical RAM:     ${ram_gb}GB"
[[ -b /dev/zram0 ]] && echo "  ZRAM (~3:1):     ~$((zram_size_gb * 3))GB effective"
[[ -f /swapfile ]] && echo "  Disk Swap:        ${swap_size:-0}GB"
echo "  ─────────────────────────"
total_effective=$((ram_gb + (${zram_size_gb:-0} * 3) + ${swap_size:-0}))
echo -e "  ${GREEN}TOTAL:             ~${total_effective}GB before OOM${NC}"

[[ $failed -gt 0 ]] && echo -e "\n${RED}Some checks failed!${NC}" && exit 1
[[ $warnings -gt 0 ]] && echo -e "\n${YELLOW}Some warnings detected.${NC}"
echo -e "\n${GREEN}System optimization verified successfully!${NC}"
VERIFY_EOF

    chmod +x "$verify_script"
    log_success "Doğrulama scripti oluşturuldu: $verify_script"
}

#───────────────────────────────────────────────────────────────────────────────
# ROLLBACK FUNCTION
#───────────────────────────────────────────────────────────────────────────────

rollback() {
    local backup_path="$1"
    
    log_section "ROLLBACK"
    
    [[ ! -d "$backup_path" ]] && log_error "Backup dizini bulunamadı: $backup_path" && exit 1
    
    log_info "Backup'tan geri yükleniyor: $backup_path"
    
    for backup_file in "$backup_path"/*.backup; do
        [[ -f "$backup_file" ]] || continue
        local original_name
        original_name=$(basename "$backup_file" .backup)
        
        case "$original_name" in
            "zram-generator.conf") cp "$backup_file" "/etc/systemd/$original_name"; log_info "Restored: /etc/systemd/$original_name" ;;
            "fstab") cp "$backup_file" "/etc/$original_name"; log_info "Restored: /etc/$original_name" ;;
            "99-zram-lunar-lake.conf"|"99-sysctl.conf"|"99-zram.conf") cp "$backup_file" "/etc/sysctl.d/$original_name"; log_info "Restored: /etc/sysctl.d/$original_name" ;;
            *) log_warn "Bilinmeyen backup dosyası: $original_name" ;;
        esac
    done
    
    grubby --update-kernel=ALL --remove-args="zswap.enabled=0" 2>/dev/null || true
    rm -f /etc/sysctl.d/99-zram-lunar-lake.conf
    
    read -p "Swapfile'ı da kaldırmak ister misiniz? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        swapoff "$DISK_SWAP_FILE" 2>/dev/null || true
        rm -f "$DISK_SWAP_FILE"
        sed -i "\|$DISK_SWAP_FILE|d" /etc/fstab 2>/dev/null || true
        log_info "Swapfile kaldırıldı"
    fi
    
    sysctl --system
    
    log_success "Rollback tamamlandı"
    log_warn "Tam geri dönüş için REBOOT gerekli"
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN FUNCTION
#───────────────────────────────────────────────────────────────────────────────

print_banner() {
    cat << 'EOF'

    ╦  ╦ ╦╔╗╔╔═╗╦═╗  ╦  ╔═╗╦╔═╔═╗
    ║  ║ ║║║║╠═╣╠╦╝  ║  ╠═╣╠╩╗║╣ 
    ╩═╝╚═╝╝╚╝╩ ╩╩╚═  ╩═╝╩ ╩╩ ╩╚═╝
    
    32GB SYSTEM OPTIMIZER v4.0.0
    Fedora 43 | ZRAM 16GB + Disk Swap 8GB | Production-Grade
    
    ┌─────────────────────────────────────────────────────────┐
    │  NEW in v4.0: Three-Tier Swap Architecture             │
    │                                                         │
    │  Tier 1: RAM (32GB)         - Primary                  │
    │  Tier 2: ZRAM (16GB, p=100) - Fast compressed swap     │
    │  Tier 3: Disk (8GB, p=10)   - Emergency fallback       │
    │                                                         │
    │  → OOM prevention with minimal disk I/O                │
    └─────────────────────────────────────────────────────────┘

EOF
}

print_usage() {
    cat << EOF
Kullanım: $0 [OPTIONS]

OPTIONS:
    --install        Tam kurulum yap (default)
    --verify         Sadece doğrulama yap
    --rollback DIR   Belirtilen backup'tan geri dön
    --no-disk-swap   Disk swap olmadan sadece ZRAM kur
    --dry-run        Değişiklik yapmadan göster
    --help           Bu yardım mesajını göster

Örnekler:
    sudo $0                              # Tam kurulum (ZRAM + Disk Swap)
    sudo $0 --no-disk-swap               # Sadece ZRAM (v3.0 uyumlu)
    sudo $0 --verify                     # Sadece kontrol
    sudo $0 --rollback /var/backup/lunar-lake-optimizer/20260127_123456

SWAP ARCHITECTURE (v4.0.0):
    Tier 2: ZRAM      → 16GB → Priority 100 (PRIMARY)
    Tier 3: Disk Swap →  8GB → Priority  10 (FALLBACK)

EOF
}

main() {
    local action="install"
    local rollback_dir=""
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install) action="install"; shift ;;
            --verify) action="verify"; shift ;;
            --rollback) action="rollback"; rollback_dir="$2"; shift 2 ;;
            --no-disk-swap) ENABLE_DISK_SWAP=false; shift ;;
            --dry-run) dry_run=true; shift ;;
            --help|-h) print_usage; exit 0 ;;
            *) log_error "Bilinmeyen parametre: $1"; print_usage; exit 1 ;;
        esac
    done
    
    print_banner
    
    [[ "$action" != "verify" ]] && check_root
    
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_info "Script başlatıldı: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Action: $action"
    log_info "Disk swap: $( $ENABLE_DISK_SWAP && echo "enabled" || echo "disabled" )"
    
    case "$action" in
        install)
            $dry_run && log_info "DRY-RUN modu - değişiklik yapılmayacak"
            
            preflight_checks || { log_error "Pre-flight checks başarısız, çıkılıyor"; exit 1; }
            
            local expected_zram
            expected_zram=$(calculate_expected_zram)
            
            echo ""
            echo -e "${YELLOW}Bu script sisteminizi optimize edecek:${NC}"
            echo ""
            echo "  ┌────────────────────────────────────────────────────────────┐"
            echo "  │ Yapılacak Değişiklikler (v4.0)                             │"
            echo "  ├────────────────────────────────────────────────────────────┤"
            echo "  │ • ZRAM kurulumu: ${expected_zram}GB (ram / 2, priority 100)         │"
            echo "  │ • Compression: zstd (best ratio)                           │"
            $ENABLE_DISK_SWAP && echo "  │ • Disk swap fallback: ${DISK_SWAP_SIZE_GB}GB (priority 10)              │" || echo "  │ • Disk swap: DEVRE DIŞI (--no-disk-swap)                   │"
            echo "  │ • Sysctl optimizasyonları (ZRAM için)                      │"
            echo "  │ • ZSWAP devre dışı bırakma                                 │"
            echo "  └────────────────────────────────────────────────────────────┘"
            echo ""
            
            if $ENABLE_DISK_SWAP; then
                echo "  ┌────────────────────────────────────────────────────────────┐"
                echo "  │ SWAP HIERARCHY                                             │"
                echo "  ├────────────────────────────────────────────────────────────┤"
                echo "  │   RAM full → ZRAM (fast) → Disk (slow) → OOM Killer       │"
                echo "  │   Normal kullanımda disk swap KULLANILMAZ.                 │"
                echo "  └────────────────────────────────────────────────────────────┘"
                echo ""
            fi
            
            if ! $dry_run; then
                read -p "Devam etmek istiyor musunuz? (y/N) " -n 1 -r
                echo
                [[ ! $REPLY =~ ^[Yy]$ ]] && log_info "Kullanıcı iptal etti" && exit 0
                
                create_backup_dir
                install_packages
                configure_zram
                configure_disk_swap
                configure_sysctl
                disable_zswap
                create_verification_script
                verify_installation
                show_post_reboot_status
                
                log_section "TAMAMLANDI"
                log_success "Optimizasyon tamamlandı!"
                log_warn "Değişikliklerin tam etkisi için REBOOT gerekli"
                echo ""
                echo -e "Backup konumu: ${CYAN}${BACKUP_DIR}${NC}"
                echo -e "Log dosyası: ${CYAN}${LOG_FILE}${NC}"
                echo ""
                
                read -p "Şimdi reboot yapmak ister misiniz? (y/N) " -n 1 -r
                echo
                [[ $REPLY =~ ^[Yy]$ ]] && log_info "Sistem yeniden başlatılıyor..." && reboot
            else
                log_info "DRY-RUN tamamlandı, değişiklik yapılmadı"
            fi
            ;;
            
        verify)
            [[ -x /usr/local/bin/lunar-lake-verify.sh ]] && /usr/local/bin/lunar-lake-verify.sh || { log_error "Doğrulama scripti bulunamadı"; log_info "Önce --install ile kurulum yapın"; exit 1; }
            ;;
            
        rollback)
            [[ -z "$rollback_dir" ]] && { log_error "Rollback için backup dizini belirtilmeli"; echo ""; echo "Mevcut backup'lar:"; ls -la /var/backup/${SCRIPT_NAME}/ 2>/dev/null || echo "  (bulunamadı)"; exit 1; }
            rollback "$rollback_dir"
            ;;
    esac
}

main "$@"
