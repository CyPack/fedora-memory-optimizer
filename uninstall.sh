#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# FEDORA MEMORY OPTIMIZER v4.0 - UNINSTALLER & RESTORE
#═══════════════════════════════════════════════════════════════════════════════
#
# USAGE:
#   sudo ./uninstall.sh              # Uninstall (saves to backup)
#   sudo ./uninstall.sh --restore    # Restore from existing backups
#   sudo ./uninstall.sh --list       # List backups
#   sudo ./uninstall.sh --status     # Show installed components
#
# BACKUP LOCATIONS:
#   /root/memory-backup-*            # memory-optimizer backups
#   /root/hibernate-backup-*         # hibernate backups
#   /root/memory-optimizer-uninstall-backup-*  # uninstall backups
#
#═══════════════════════════════════════════════════════════════════════════════

set -o pipefail

SCRIPT_VERSION="4.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }
log_header()  { echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n${BOLD}$1${NC}\n"; }

#───────────────────────────────────────────────────────────────────────────────
# USAGE
#───────────────────────────────────────────────────────────────────────────────

show_usage() {
    echo ""
    echo -e "${BOLD}Fedora Memory Optimizer v${SCRIPT_VERSION} - Uninstaller${NC}"
    echo ""
    echo "Usage:"
    echo "  sudo $0              # Uninstall (interactive)"
    echo "  sudo $0 --restore    # Restore from backup"
    echo "  sudo $0 --list       # List backups"
    echo "  sudo $0 --status     # Show installed components"
    echo "  sudo $0 --help       # Show this help"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

detect_installed_components() {
    local count=0
    
    [[ -f /etc/sysctl.d/99-memory-optimizer.conf ]] && ((count++))
    [[ -f /etc/systemd/zram-generator.conf ]] && ((count++))
    [[ -f /etc/systemd/system/user-.slice.d/50-memory-limit.conf ]] && ((count++))
    [[ -f /etc/systemd/oomd.conf.d/99-passive-nokill.conf ]] && ((count++))
    [[ -f /swapfile ]] && ((count++))
    [[ -f /etc/dracut.conf.d/99-hibernate.conf ]] && ((count++))
    [[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]] && ((count++))
    
    echo $count
}

show_status() {
    echo ""
    echo -e "${BOLD}Installed Components:${NC}"
    echo ""
    
    local found=0
    
    if [[ -f /etc/sysctl.d/99-memory-optimizer.conf ]]; then
        echo -e "  ${GREEN}✓${NC} Kernel params: /etc/sysctl.d/99-memory-optimizer.conf"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} Kernel params: not installed"
    fi
    
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        local zram_size=$(grep -oP 'zram-size\s*=\s*\K[^\s]+' /etc/systemd/zram-generator.conf 2>/dev/null || echo "?")
        echo -e "  ${GREEN}✓${NC} zram config: $zram_size"
    else
        echo -e "  ${RED}✗${NC} zram config: not installed"
    fi
    
    if [[ -f /etc/systemd/system/user-.slice.d/50-memory-limit.conf ]]; then
        local mem_high=$(grep -oP 'MemoryHigh=\K[^\s]+' /etc/systemd/system/user-.slice.d/50-memory-limit.conf 2>/dev/null || echo "?")
        echo -e "  ${GREEN}✓${NC} User limits: MemoryHigh=$mem_high"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} User limits: not installed"
    fi
    
    if [[ -f /etc/systemd/oomd.conf.d/99-passive-nokill.conf ]]; then
        echo -e "  ${GREEN}✓${NC} oomd config: passive mode"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} oomd config: not installed"
    fi
    
    if [[ -f /swapfile ]]; then
        local swap_gb=$(($(stat -c%s /swapfile 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
        echo -e "  ${GREEN}✓${NC} Swapfile: ${swap_gb}GB"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} Swapfile: none"
    fi
    
    echo ""
    echo -e "${BOLD}Hibernate Components:${NC}"
    echo ""
    
    if [[ -f /etc/dracut.conf.d/99-hibernate.conf ]]; then
        echo -e "  ${GREEN}✓${NC} dracut config: /etc/dracut.conf.d/99-hibernate.conf"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} dracut config: not installed"
    fi
    
    if [[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]]; then
        echo -e "  ${GREEN}✓${NC} polkit rules: hibernate permissions"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} polkit rules: not installed"
    fi
    
    if grep -q "resume=" /proc/cmdline 2>/dev/null; then
        local resume_params=$(cat /proc/cmdline | tr ' ' '\n' | grep "resume" | tr '\n' ' ')
        echo -e "  ${GREEN}✓${NC} Kernel resume: $resume_params"
        ((found++))
    else
        echo -e "  ${RED}✗${NC} Kernel resume: not configured"
    fi
    
    echo ""
    echo "Total installed components: $found"
    echo ""
}

list_backups() {
    echo ""
    echo -e "${BOLD}Available Backups:${NC}"
    echo ""
    
    local backup_count=0
    
    # Memory optimizer backups
    if ls -d /root/memory-backup-* 2>/dev/null | head -1 > /dev/null; then
        echo -e "${CYAN}Memory Optimizer Backups:${NC}"
        for dir in $(ls -dt /root/memory-backup-* 2>/dev/null | head -10); do
            local file_count=$(ls -1 "$dir" 2>/dev/null | wc -l)
            echo "  [$((++backup_count))] $dir ($file_count files)"
        done
        echo ""
    fi
    
    # Hibernate backups
    if ls -d /root/hibernate-backup-* 2>/dev/null | head -1 > /dev/null; then
        echo -e "${CYAN}Hibernate Backups:${NC}"
        for dir in $(ls -dt /root/hibernate-backup-* 2>/dev/null | head -10); do
            local file_count=$(ls -1 "$dir" 2>/dev/null | wc -l)
            echo "  [$((++backup_count))] $dir ($file_count files)"
        done
        echo ""
    fi
    
    # Uninstall backups
    if ls -d /root/memory-optimizer-uninstall-backup-* 2>/dev/null | head -1 > /dev/null; then
        echo -e "${CYAN}Uninstall Backups:${NC}"
        for dir in $(ls -dt /root/memory-optimizer-uninstall-backup-* 2>/dev/null | head -10); do
            local file_count=$(ls -1 "$dir" 2>/dev/null | wc -l)
            echo "  [$((++backup_count))] $dir ($file_count files)"
        done
        echo ""
    fi
    
    if [[ $backup_count -eq 0 ]]; then
        log_warning "No backups found."
        echo ""
        echo "Backups are searched in these locations:"
        echo "  /root/memory-backup-*"
        echo "  /root/hibernate-backup-*"
        echo "  /root/memory-optimizer-uninstall-backup-*"
    fi
    
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# RESTORE FUNCTION
#───────────────────────────────────────────────────────────────────────────────

do_restore() {
    log_header "RESTORE - Restore from Backup"
    
    # List all backups
    local backups=()
    local i=0
    
    for dir in $(ls -dt /root/memory-backup-* /root/hibernate-backup-* /root/memory-optimizer-uninstall-backup-* 2>/dev/null); do
        backups+=("$dir")
        local file_count=$(ls -1 "$dir" 2>/dev/null | wc -l)
        local files=$(ls -1 "$dir" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        echo "  [$((++i))] $dir"
        echo "      Files: $files"
        echo ""
    done
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "No backups found."
        echo ""
        echo "Run memory-optimizer or hibernate script first to create a backup."
        exit 1
    fi
    
    echo ""
    read -r -p "Which backup do you want to restore? (1-$i or 'cancel'): " choice
    
    if [[ "$choice" == "cancel" ]] || [[ -z "$choice" ]]; then
        log_info "Cancelled."
        exit 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt $i ]]; then
        log_error "Invalid choice: $choice"
        exit 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    
    echo ""
    echo -e "${BOLD}Selected backup:${NC} $selected_backup"
    echo ""
    echo -e "${BOLD}Contents:${NC}"
    ls -la "$selected_backup/"
    echo ""
    
    read -r -p "Restore these files? (y/N) " confirm
    
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        log_info "Cancelled."
        exit 0
    fi
    
    echo ""
    log_info "Restoring..."
    
    local restored=0
    
    # Restore each file with IDEMPOTENCY check
    if [[ -f "$selected_backup/99-memory-optimizer.conf" ]]; then
        if [[ -f /etc/sysctl.d/99-memory-optimizer.conf ]]; then
            if diff -q "$selected_backup/99-memory-optimizer.conf" /etc/sysctl.d/99-memory-optimizer.conf > /dev/null 2>&1; then
                log_info "Kernel params: already same (skipped)"
            else
                cp "$selected_backup/99-memory-optimizer.conf" /etc/sysctl.d/
                log_success "Kernel params: restored"
                ((restored++))
            fi
        else
            cp "$selected_backup/99-memory-optimizer.conf" /etc/sysctl.d/
            log_success "Kernel params: restored"
            ((restored++))
        fi
    fi
    
    if [[ -f "$selected_backup/zram-generator.conf" ]]; then
        if [[ -f /etc/systemd/zram-generator.conf ]]; then
            if diff -q "$selected_backup/zram-generator.conf" /etc/systemd/zram-generator.conf > /dev/null 2>&1; then
                log_info "zram config: already same (skipped)"
            else
                cp "$selected_backup/zram-generator.conf" /etc/systemd/
                log_success "zram config: restored"
                ((restored++))
            fi
        else
            cp "$selected_backup/zram-generator.conf" /etc/systemd/
            log_success "zram config: restored"
            ((restored++))
        fi
    fi
    
    if [[ -f "$selected_backup/50-memory-limit.conf" ]]; then
        mkdir -p /etc/systemd/system/user-.slice.d
        if [[ -f /etc/systemd/system/user-.slice.d/50-memory-limit.conf ]]; then
            if diff -q "$selected_backup/50-memory-limit.conf" /etc/systemd/system/user-.slice.d/50-memory-limit.conf > /dev/null 2>&1; then
                log_info "User limits: already same (skipped)"
            else
                cp "$selected_backup/50-memory-limit.conf" /etc/systemd/system/user-.slice.d/
                log_success "User limits: restored"
                ((restored++))
            fi
        else
            cp "$selected_backup/50-memory-limit.conf" /etc/systemd/system/user-.slice.d/
            log_success "User limits: restored"
            ((restored++))
        fi
    fi
    
    if [[ -f "$selected_backup/99-passive-nokill.conf" ]]; then
        mkdir -p /etc/systemd/oomd.conf.d
        if [[ -f /etc/systemd/oomd.conf.d/99-passive-nokill.conf ]]; then
            if diff -q "$selected_backup/99-passive-nokill.conf" /etc/systemd/oomd.conf.d/99-passive-nokill.conf > /dev/null 2>&1; then
                log_info "oomd config: already same (skipped)"
            else
                cp "$selected_backup/99-passive-nokill.conf" /etc/systemd/oomd.conf.d/
                log_success "oomd config: restored"
                ((restored++))
            fi
        else
            cp "$selected_backup/99-passive-nokill.conf" /etc/systemd/oomd.conf.d/
            log_success "oomd config: restored"
            ((restored++))
        fi
    fi
    
    if [[ -f "$selected_backup/fstab" ]]; then
        echo ""
        log_warning "fstab backup found."
        echo "  Restoring this file is risky."
        echo "  Manual comparison recommended:"
        echo "    diff $selected_backup/fstab /etc/fstab"
        echo ""
        read -r -p "Restore fstab? (y/N) " fstab_confirm
        if [[ "$fstab_confirm" =~ ^[Yy] ]]; then
            cp /etc/fstab /etc/fstab.backup-before-restore
            cp "$selected_backup/fstab" /etc/fstab
            log_success "fstab: restored (previous: /etc/fstab.backup-before-restore)"
            ((restored++))
        fi
    fi
    
    # Hibernate files
    if [[ -f "$selected_backup/99-hibernate.conf" ]]; then
        mkdir -p /etc/dracut.conf.d
        cp "$selected_backup/99-hibernate.conf" /etc/dracut.conf.d/
        log_success "dracut hibernate config: restored"
        ((restored++))
    fi
    
    if [[ -f "$selected_backup/10-enable-hibernate.rules" ]]; then
        mkdir -p /etc/polkit-1/rules.d
        cp "$selected_backup/10-enable-hibernate.rules" /etc/polkit-1/rules.d/
        log_success "polkit rules: restored"
        ((restored++))
    fi
    
    if [[ -f "$selected_backup/grub" ]]; then
        echo ""
        log_warning "GRUB config backup found."
        echo "  Restoring this file is risky."
        read -r -p "Restore GRUB config? (y/N) " grub_confirm
        if [[ "$grub_confirm" =~ ^[Yy] ]]; then
            cp /etc/default/grub /etc/default/grub.backup-before-restore 2>/dev/null || true
            cp "$selected_backup/grub" /etc/default/grub
            log_success "GRUB config: restored"
            log_warning "Regenerate GRUB: sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
            ((restored++))
        fi
    fi
    
    if [[ -f "$selected_backup/cmdline" ]]; then
        echo ""
        log_warning "kernel cmdline backup found."
        read -r -p "Restore kernel cmdline? (y/N) " cmdline_confirm
        if [[ "$cmdline_confirm" =~ ^[Yy] ]]; then
            cp /etc/kernel/cmdline /etc/kernel/cmdline.backup-before-restore 2>/dev/null || true
            cp "$selected_backup/cmdline" /etc/kernel/cmdline
            log_success "kernel cmdline: restored"
            log_warning "Run kernel-install: sudo kernel-install add-all"
            ((restored++))
        fi
    fi
    
    # Reload
    echo ""
    log_info "Reloading system settings..."
    sysctl --system > /dev/null 2>&1 || true
    systemctl daemon-reload 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}     ${BOLD}RESTORE COMPLETE${NC}                                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Restored file: $restored"
    echo ""
    echo "  ⚠️  Reboot recommended: sudo reboot"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# UNINSTALL FUNCTION
#───────────────────────────────────────────────────────────────────────────────

check_existing_backups() {
    # Check if any previous backups exist
    local backup_count=0
    
    for dir in /root/memory-backup-* /root/hibernate-backup-* /root/memory-optimizer-uninstall-backup-* 2>/dev/null; do
        [[ -d "$dir" ]] && ((backup_count++))
    done
    
    echo $backup_count
}

show_no_backup_warning() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}⛔ WARNING: NO BACKUPS FOUND!${NC}                                   ${RED}║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  Searched for backups in the following directories:                                 ${RED}║${NC}"
    echo -e "${RED}║${NC}    • /root/memory-backup-*                                           ${RED}║${NC}"
    echo -e "${RED}║${NC}    • /root/hibernate-backup-*                                        ${RED}║${NC}"
    echo -e "${RED}║${NC}    • /root/memory-optimizer-uninstall-backup-*                       ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${BOLD}RISKS OF DELETING WITHOUT BACKUP:${NC}                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  1. ${YELLOW}IRREVERSIBLE${NC} - Files will be permanently deleted                ${RED}║${NC}"
    echo -e "${RED}║${NC}     Restore with --restore WILL NOT BE POSSIBLE                      ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  2. ${YELLOW}MANUAL INSTALLATION MAY BE REQUIRED${NC}                                      ${RED}║${NC}"
    echo -e "${RED}║${NC}     You will need to run the script again                          ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  3. ${YELLOW}RETURN TO SYSTEM DEFAULTS${NC}                                   ${RED}║${NC}"
    echo -e "${RED}║${NC}     • swappiness → 60 (default)                                      ${RED}║${NC}"
    echo -e "${RED}║${NC}     • zram → disabled                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}     • oomd → default (agresif kill)                                  ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  4. ${YELLOW}HIBERNATE BREAKAGE${NC}                                             ${RED}║${NC}"
    echo -e "${RED}║${NC}     Hibernate will not work if swapfile is deleted                        ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_backup_creation_failed_warning() {
    local backup_dir="$1"
    local error_msg="$2"
    
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}⛔ BACKUP CREATION FAILED!${NC}                                            ${RED}║${NC}"
    echo -e "${RED}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  Target directory: $backup_dir                     ${RED}║${NC}"
    echo -e "${RED}║${NC}  Error: $error_msg                                                    ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${BOLD}OLASI NEDENLER:${NC}                                                     ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Disk dolu                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}    • No write permission to /root directory                                   ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Filesystem read-only                                         ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${BOLD}RISKS OF CONTINUING WITHOUT BACKUP:${NC}                                      ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Deleted files CANNOT BE RECOVERED                                  ${RED}║${NC}"
    echo -e "${RED}║${NC}    • --restore will not work                                              ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Manual installation may be required                                      ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                       ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

do_uninstall() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}FEDORA MEMORY OPTIMIZER v${SCRIPT_VERSION} - UNINSTALLER${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show status first
    show_status
    
    local components=$(detect_installed_components)
    
    if [[ $components -eq 0 ]]; then
        log_info "Memory optimizer not installed or already removed."
        exit 0
    fi
    
    # Check for existing backups
    local existing_backups=$(check_existing_backups)
    local no_previous_backup=false
    
    if [[ $existing_backups -eq 0 ]]; then
        no_previous_backup=true
        show_no_backup_warning
        
        echo -e "${YELLOW}A new backup will be created now, but no backup has been taken before.${NC}"
        echo ""
        read -r -p "Are you sure you want to delete these files without backup? (type yes): " confirm_no_backup
        
        if [[ "$confirm_no_backup" != "yes" ]]; then
            log_info "Cancelled. Run the script first to create a backup:"
            echo "    sudo ./memory-optimizer-v4.sh"
            echo ""
            echo "This operation backs up existing configs and you can revert anytime."
            exit 0
        fi
        
        echo ""
        log_warning "User confirmed: continuing without backup"
    else
        echo -e "${GREEN}✓ Existing backup count: $existing_backups${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}This operation will remove the above components.${NC}"
    if [[ "$no_previous_backup" != "true" ]]; then
        echo -e "${YELLOW}Backup will be taken, then you can restore with --restore.${NC}"
    fi
    echo ""
    read -r -p "Continue? (y/N) " response
    
    if [[ ! "$response" =~ ^[Yy] ]]; then
        log_info "Cancelled."
        exit 0
    fi
    
    echo ""
    
    # Create backup
    local BACKUP_DIR="/root/memory-optimizer-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_created=false
    
    # Try to create backup directory
    if mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        # Test if we can write to it
        if touch "$BACKUP_DIR/.test" 2>/dev/null && rm -f "$BACKUP_DIR/.test" 2>/dev/null; then
            backup_created=true
            log_success "Backup directory created: $BACKUP_DIR"
        else
            rmdir "$BACKUP_DIR" 2>/dev/null || true
            show_backup_creation_failed_warning "$BACKUP_DIR" "Cannot write to directory"
        fi
    else
        show_backup_creation_failed_warning "$BACKUP_DIR" "Cannot create directory"
    fi
    
    # If backup creation failed, ask for confirmation
    if [[ "$backup_created" != "true" ]]; then
        echo -e "${RED}⛔ BACKUP CREATION FAILED!${NC}"
        echo ""
        echo "Possible solutions:"
        echo "  1. Check disk space: df -h /root"
        echo "  2. Backup to a different directory: BACKUP_DIR=/tmp/backup ./uninstall.sh"
        echo "  3. Fix disk issues"
        echo ""
        read -r -p "Do you want to continue WITHOUT BACKUP? (type yes): " force_no_backup
        
        if [[ "$force_no_backup" != "yes" ]]; then
            log_info "Cancelled. Try again after resolving backup issue."
            exit 1
        fi
        
        echo ""
        log_error "⚠️  CONTINUING WITHOUT BACKUP - NO WAY BACK!"
        echo ""
    fi
    
    local removed=0
    local backup_failed_files=()
    
    # Helper function to safely remove with backup
    safe_remove() {
        local file="$1"
        local name="$2"
        
        if [[ ! -f "$file" ]]; then
            return 0
        fi
        
        if [[ "$backup_created" == "true" ]]; then
            if cp "$file" "$BACKUP_DIR/" 2>/dev/null; then
                rm -f "$file"
                log_success "$name: removed → saved to backup"
                ((removed++))
            else
                backup_failed_files+=("$file")
                log_error "$name: backup FAILED!"
                echo ""
                read -r -p "  $file backup failed. Delete anyway? (y/N) " force_delete
                if [[ "$force_delete" =~ ^[Yy] ]]; then
                    rm -f "$file"
                    log_warning "$name: deleted WITHOUT backup!"
                    ((removed++))
                else
                    log_info "$name: PRESERVED (backup failed)"
                fi
            fi
        else
            # No backup available - already warned user
            rm -f "$file"
            log_warning "$name: deleted (NO BACKUP!)"
            ((removed++))
        fi
    }
    
    # 1. Kernel params
    safe_remove "/etc/sysctl.d/99-memory-optimizer.conf" "Kernel params"
    
    # 2. zram config
    if [[ -f /etc/systemd/zram-generator.conf ]]; then
        safe_remove "/etc/systemd/zram-generator.conf" "zram config"
        
        # Stop zram
        if [[ -b /dev/zram0 ]]; then
            swapoff /dev/zram0 2>/dev/null || true
            log_info "zram swap: disabled"
        fi
    fi
    
    # 3. User limits
    if [[ -f /etc/systemd/system/user-.slice.d/50-memory-limit.conf ]]; then
        safe_remove "/etc/systemd/system/user-.slice.d/50-memory-limit.conf" "User limits"
        rmdir /etc/systemd/system/user-.slice.d 2>/dev/null || true
    fi
    
    # 4. oomd config
    if [[ -f /etc/systemd/oomd.conf.d/99-passive-nokill.conf ]]; then
        safe_remove "/etc/systemd/oomd.conf.d/99-passive-nokill.conf" "oomd config"
        rmdir /etc/systemd/oomd.conf.d 2>/dev/null || true
    fi
    
    # 5. Swapfile (ask user)
    if [[ -f /swapfile ]]; then
        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}SWAPFILE DETECTED${NC}                                                ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        
        local swap_gb=$(($(stat -c%s /swapfile 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
        echo -e "${YELLOW}║${NC}  Size: ${swap_gb}GB                                                        ${YELLOW}║${NC}"
        
        # Check if hibernate is configured
        local hibernate_configured=false
        if grep -q "resume=" /proc/cmdline 2>/dev/null; then
            hibernate_configured=true
            echo -e "${YELLOW}║${NC}  ${RED}⛔ WARNING: Hibernate kernel params active!${NC}                            ${YELLOW}║${NC}"
            echo -e "${YELLOW}║${NC}  ${RED}   If swapfile is deleted, hibernate WILL NOT WORK.${NC}                          ${YELLOW}║${NC}"
        fi
        
        # Warn if no backup
        if [[ "$backup_created" != "true" ]]; then
            echo -e "${YELLOW}║${NC}  ${RED}⛔ NO BACKUP: fstab cannot be restored!${NC}                               ${YELLOW}║${NC}"
        fi
        
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -r -p "Delete swapfile? (y/N) " swap_response
        
        if [[ "$swap_response" =~ ^[Yy] ]]; then
            # Extra confirmation for hibernate
            if [[ "$hibernate_configured" == "true" ]]; then
                echo ""
                echo -e "${RED}⛔ Hibernate bozulacak!${NC}"
                read -r -p "Are you sure? (type yes): " confirm
                if [[ "$confirm" != "yes" ]]; then
                    log_warning "Swapfile KORUNDU"
                else
                    # Backup fstab if possible
                    if [[ "$backup_created" == "true" ]]; then
                        cp /etc/fstab "$BACKUP_DIR/" 2>/dev/null || true
                    fi
                    swapoff /swapfile 2>/dev/null || true
                    rm -f /swapfile
                    sed -i '\|/swapfile|d' /etc/fstab
                    if [[ "$backup_created" == "true" ]]; then
                        log_success "Swapfile: deleted (fstab in backup)"
                    else
                        log_warning "Swapfile: deleted (NO BACKUP!)"
                    fi
                    ((removed++))
                fi
            else
                # No hibernate - still backup fstab if possible
                if [[ "$backup_created" == "true" ]]; then
                    cp /etc/fstab "$BACKUP_DIR/" 2>/dev/null || true
                fi
                swapoff /swapfile 2>/dev/null || true
                rm -f /swapfile
                sed -i '\|/swapfile|d' /etc/fstab
                if [[ "$backup_created" == "true" ]]; then
                    log_success "Swapfile: deleted (fstab in backup)"
                else
                    log_warning "Swapfile: deleted (NO BACKUP!)"
                fi
                ((removed++))
            fi
        else
            log_warning "Swapfile KORUNDU"
        fi
    fi
    
    # Reload
    echo ""
    log_info "Reloading system settings..."
    sysctl --system > /dev/null 2>&1 || true
    systemctl daemon-reload 2>/dev/null || true
    
    # Summary - different based on backup status
    echo ""
    if [[ "$backup_created" == "true" ]]; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}     ${BOLD}REMOVAL COMPLETE${NC}                                              ${GREEN}║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "  📁 Backup: $BACKUP_DIR"
        echo "  🗑️  Removed: $removed files"
        echo ""
        echo "  ${BOLD}To restore:${NC}"
        echo "    sudo ./uninstall.sh --restore"
    else
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}     ${BOLD}REMOVAL COMPLETE (BACKUP YOK!)${NC}                                ${YELLOW}║${NC}"
        echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}║${NC}  ${RED}⚠️  Deleted files CANNOT BE RECOVERED!${NC}                                  ${YELLOW}║${NC}"
        echo -e "${YELLOW}║${NC}  ${RED}⚠️  --restore cannot be used!${NC}                                          ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "  🗑️  Removed: $removed files"
        echo ""
        echo "  ${BOLD}To reinstall:${NC}"
        echo "    sudo ./memory-optimizer-v4.sh"
    fi
    echo ""
    echo "  ${BOLD}Next steps:${NC}"
    echo "    1. Restart the system: sudo reboot"
    echo "    2. If you also want to remove zram-generator package:"
    echo "       sudo dnf remove zram-generator"
    echo ""
    
    # Optional: Remove hibernate config
    if [[ -f /etc/dracut.conf.d/99-hibernate.conf ]] || [[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]]; then
        echo ""
        echo -e "${YELLOW}Hibernate configuration also detected.${NC}"
        if [[ "$backup_created" != "true" ]]; then
            echo -e "${RED}⚠️  NO Backup - hibernate config cannot be restored if deleted!${NC}"
        fi
        echo ""
        read -r -p "Remove hibernate config too? (y/N) " hibernate_response
        
        if [[ "$hibernate_response" =~ ^[Yy] ]]; then
            [[ -f /etc/dracut.conf.d/99-hibernate.conf ]] && {
                if [[ "$backup_created" == "true" ]]; then
                    cp /etc/dracut.conf.d/99-hibernate.conf "$BACKUP_DIR/" 2>/dev/null || true
                    rm -f /etc/dracut.conf.d/99-hibernate.conf
                    log_success "dracut hibernate config: removed → in backup"
                else
                    rm -f /etc/dracut.conf.d/99-hibernate.conf
                    log_warning "dracut hibernate config: removed (NO BACKUP!)"
                fi
            }
            
            [[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]] && {
                if [[ "$backup_created" == "true" ]]; then
                    cp /etc/polkit-1/rules.d/10-enable-hibernate.rules "$BACKUP_DIR/" 2>/dev/null || true
                    rm -f /etc/polkit-1/rules.d/10-enable-hibernate.rules
                    log_success "polkit hibernate rules: removed → in backup"
                else
                    rm -f /etc/polkit-1/rules.d/10-enable-hibernate.rules
                    log_warning "polkit hibernate rules: removed (NO BACKUP!)"
                fi
            }
            
            echo ""
            log_warning "Kernel resume parameters must be removed manually:"
            echo "  GRUB:         sudo grubby --update-kernel=ALL --remove-args='resume resume_offset'"
            echo "  systemd-boot: /etc/kernel/cmdlineremove resume lines from"
            echo ""
            log_warning "initramfs must be regenerated:"
            echo "  sudo dracut --force --kver \$(uname -r)"
        fi
    fi
    
    echo ""
    log_success "Operation completed. Reboot recommended."
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN
#───────────────────────────────────────────────────────────────────────────────

# Root check
if [[ $EUID -ne 0 ]] && [[ "$1" != "--help" ]] && [[ "$1" != "-h" ]]; then
    log_error "Root required: sudo $0 $*"
    exit 1
fi

case "${1:-}" in
    --restore|-r)
        do_restore
        ;;
    --list|-l)
        list_backups
        ;;
    --status|-s)
        show_status
        ;;
    --help|-h)
        show_usage
        ;;
    "")
        do_uninstall
        ;;
    *)
        log_error "Bilinmeyen parametre: $1"
        show_usage
        exit 1
        ;;
esac
