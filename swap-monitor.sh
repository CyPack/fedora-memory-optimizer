#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# FEDORA MEMORY OPTIMIZER v4.0 - SWAP MONITOR
#═══════════════════════════════════════════════════════════════════════════════
#
# This script monitors swap usage and sends desktop notifications.
# Runs as user systemd service (not root).
#
# KURULUM:
#   ./swap-monitor.sh --install
#
# KALDIRMA:
#   ./swap-monitor.sh --uninstall
#
# MANUEL TEST:
#   ./swap-monitor.sh --check
#
#═══════════════════════════════════════════════════════════════════════════════

SCRIPT_VERSION="4.0.0"
SCRIPT_NAME="swap-monitor"

# Thresholds (%)
SWAP_WARNING_THRESHOLD=50      # First warning
SWAP_CRITICAL_THRESHOLD=80     # Critical warning
ZRAM_WARNING_THRESHOLD=70      # zram warning

# Cooldown (seconds) - to avoid sending the same warning repeatedly
NOTIFICATION_COOLDOWN=300      # 5 minutes

# State file (keeps last notification time)
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/swap-monitor"
STATE_FILE="$STATE_DIR/last_notification"

# Colors (for terminal)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

#───────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; }

# Create state directory
init_state() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
}

# Check last notification time (cooldown)
can_send_notification() {
    local notification_type="$1"
    local state_file="$STATE_DIR/last_${notification_type}"
    
    if [[ ! -f "$state_file" ]]; then
        return 0  # No notification sent yet
    fi
    
    local last_time=$(cat "$state_file" 2>/dev/null || echo 0)
    local current_time=$(date +%s)
    local diff=$((current_time - last_time))
    
    if [[ $diff -ge $NOTIFICATION_COOLDOWN ]]; then
        return 0  # Cooldown passed
    fi
    
    return 1  # Still in cooldown
}

# Save notification time
mark_notification_sent() {
    local notification_type="$1"
    local state_file="$STATE_DIR/last_${notification_type}"
    date +%s > "$state_file"
}

# Reset notification state (when swap returns to normal)
reset_notification_state() {
    local notification_type="$1"
    rm -f "$STATE_DIR/last_${notification_type}" 2>/dev/null || true
}

#───────────────────────────────────────────────────────────────────────────────
# MEMORY INFO FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

get_memory_info() {
    # Read values from /proc/meminfo
    local meminfo=$(cat /proc/meminfo)
    
    # Total and Free RAM (KB)
    MEM_TOTAL=$(echo "$meminfo" | awk '/^MemTotal:/ {print $2}')
    MEM_AVAILABLE=$(echo "$meminfo" | awk '/^MemAvailable:/ {print $2}')
    MEM_FREE=$(echo "$meminfo" | awk '/^MemFree:/ {print $2}')
    
    # Swap (KB)
    SWAP_TOTAL=$(echo "$meminfo" | awk '/^SwapTotal:/ {print $2}')
    SWAP_FREE=$(echo "$meminfo" | awk '/^SwapFree:/ {print $2}')
    SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))
    
    # Percentages
    if [[ $SWAP_TOTAL -gt 0 ]]; then
        SWAP_PERCENT=$((SWAP_USED * 100 / SWAP_TOTAL))
    else
        SWAP_PERCENT=0
    fi
    
    MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
    MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))
    
    # In GB (for display)
    MEM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_TOTAL/1024/1024}")
    MEM_USED_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_USED/1024/1024}")
    SWAP_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $SWAP_TOTAL/1024/1024}")
    SWAP_USED_GB=$(awk "BEGIN {printf \"%.1f\", $SWAP_USED/1024/1024}")
}

get_zram_info() {
    ZRAM_TOTAL=0
    ZRAM_USED=0
    ZRAM_PERCENT=0
    ZRAM_COMP_RATIO="N/A"
    
    if [[ -b /dev/zram0 ]]; then
        # Get info with zramctl
        local zram_info=$(zramctl --bytes 2>/dev/null | grep zram0)
        
        if [[ -n "$zram_info" ]]; then
            # zramctl format: NAME ALGORITHM DISKSIZE DATA COMPR TOTAL STREAMS MOUNTPOINT
            ZRAM_TOTAL=$(echo "$zram_info" | awk '{print $3}')  # DISKSIZE
            ZRAM_USED=$(echo "$zram_info" | awk '{print $4}')   # DATA (uncompressed)
            local zram_compr=$(echo "$zram_info" | awk '{print $5}')  # COMPR (compressed)
            
            # Bytes to KB
            ZRAM_TOTAL=$((ZRAM_TOTAL / 1024))
            ZRAM_USED=$((ZRAM_USED / 1024))
            
            if [[ $ZRAM_TOTAL -gt 0 ]]; then
                ZRAM_PERCENT=$((ZRAM_USED * 100 / ZRAM_TOTAL))
            fi
            
            # Compression ratio
            if [[ $zram_compr -gt 0 ]] && [[ $ZRAM_USED -gt 0 ]]; then
                ZRAM_COMP_RATIO=$(awk "BEGIN {printf \"%.1f\", ($ZRAM_USED*1024)/$zram_compr}")
            fi
        fi
    fi
    
    ZRAM_TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $ZRAM_TOTAL/1024/1024}")
    ZRAM_USED_GB=$(awk "BEGIN {printf \"%.1f\", $ZRAM_USED/1024/1024}")
}

get_top_memory_processes() {
    # Top 5 RAM-consuming processes
    TOP_PROCESSES=$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{
        mem_mb = $6/1024;
        printf "  • %s: %.0f MB (%.1f%%)\n", $11, mem_mb, $4
    }' | head -5)
}

#───────────────────────────────────────────────────────────────────────────────
# NOTIFICATION FUNCTIONS
#───────────────────────────────────────────────────────────────────────────────

send_notification() {
    local urgency="$1"      # low, normal, critical
    local title="$2"
    local message="$3"
    local icon="$4"
    
    # notify-send available?
    if ! command -v notify-send &> /dev/null; then
        # Print to terminal
        echo "[$urgency] $title: $message"
        return 1
    fi
    
    # Icon belirleme
    case "$icon" in
        warning)  icon_name="dialog-warning" ;;
        error)    icon_name="dialog-error" ;;
        info)     icon_name="dialog-information" ;;
        memory)   icon_name="utilities-system-monitor" ;;
        *)        icon_name="dialog-information" ;;
    esac
    
    # Send notification
    notify-send \
        --urgency="$urgency" \
        --icon="$icon_name" \
        --app-name="Memory Monitor" \
        "$title" \
        "$message" 2>/dev/null || true
}

#───────────────────────────────────────────────────────────────────────────────
# CHECK FUNCTION
#───────────────────────────────────────────────────────────────────────────────

do_check() {
    init_state
    get_memory_info
    get_zram_info
    get_top_memory_processes
    
    local notification_sent=false
    
    # 1. SWAP CRITICAL CHECK (>80%)
    if [[ $SWAP_PERCENT -ge $SWAP_CRITICAL_THRESHOLD ]]; then
        if can_send_notification "swap_critical"; then
            local remaining=$((100 - SWAP_PERCENT))
            send_notification "critical" \
                "⚠️ Swap Kritik: %${SWAP_PERCENT}" \
                "Swap almost full! Remaining: %${remaining}

RAM: ${MEM_USED_GB}/${MEM_TOTAL_GB} GB (%${MEM_PERCENT})
Swap: ${SWAP_USED_GB}/${SWAP_TOTAL_GB} GB

Top RAM-consuming applications:
${TOP_PROCESSES}

Suggestions:
• Close unused applications
• Reduce browser tab count
• System may slow down" \
                "error"
            mark_notification_sent "swap_critical"
            notification_sent=true
        fi
    
    # 2. SWAP WARNING CHECK (>50%)
    elif [[ $SWAP_PERCENT -ge $SWAP_WARNING_THRESHOLD ]]; then
        if can_send_notification "swap_warning"; then
            send_notification "normal" \
                "💾 Swap Usage: %${SWAP_PERCENT}" \
                "System switched to swap.

RAM: ${MEM_USED_GB}/${MEM_TOTAL_GB} GB (%${MEM_PERCENT})
Swap: ${SWAP_USED_GB}/${SWAP_TOTAL_GB} GB
zram: ${ZRAM_USED_GB}/${ZRAM_TOTAL_GB} GB (%${ZRAM_PERCENT})

Top RAM consumers:
${TOP_PROCESSES}

ℹ️ Performance degradation may occur" \
                "warning"
            mark_notification_sent "swap_warning"
            notification_sent=true
        fi
    else
        # Swap returned to normal - reset states
        reset_notification_state "swap_warning"
        reset_notification_state "swap_critical"
    fi
    
    # 3. ZRAM WARNING CHECK (>70%)
    if [[ $ZRAM_PERCENT -ge $ZRAM_WARNING_THRESHOLD ]]; then
        if can_send_notification "zram_warning"; then
            send_notification "low" \
                "🗜️ zram Usage: %${ZRAM_PERCENT}" \
                "Compressed RAM is heavily used.

zram: ${ZRAM_USED_GB}/${ZRAM_TOTAL_GB} GB
Compression ratio: ${ZRAM_COMP_RATIO}x

This is normal operation - data is kept in RAM through compression." \
                "info"
            mark_notification_sent "zram_warning"
            notification_sent=true
        fi
    else
        reset_notification_state "zram_warning"
    fi
    
    # Return result
    if [[ "$notification_sent" == "true" ]]; then
        return 1  # Notification sent
    fi
    return 0  # Everything is normal
}

#───────────────────────────────────────────────────────────────────────────────
# STATUS FUNCTION (for terminal)
#───────────────────────────────────────────────────────────────────────────────

do_status() {
    get_memory_info
    get_zram_info
    get_top_memory_processes
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}MEMORY MONITOR STATUS${NC}                                            ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # RAM status
    local ram_color=$GREEN
    [[ $MEM_PERCENT -ge 80 ]] && ram_color=$YELLOW
    [[ $MEM_PERCENT -ge 95 ]] && ram_color=$RED
    
    echo -e "${BOLD}RAM:${NC}"
    echo -e "  Usage: ${ram_color}${MEM_USED_GB} / ${MEM_TOTAL_GB} GB (%${MEM_PERCENT})${NC}"
    echo ""
    
    # Swap status
    if [[ $SWAP_TOTAL -gt 0 ]]; then
        local swap_color=$GREEN
        [[ $SWAP_PERCENT -ge $SWAP_WARNING_THRESHOLD ]] && swap_color=$YELLOW
        [[ $SWAP_PERCENT -ge $SWAP_CRITICAL_THRESHOLD ]] && swap_color=$RED
        
        echo -e "${BOLD}Swap:${NC}"
        echo -e "  Usage: ${swap_color}${SWAP_USED_GB} / ${SWAP_TOTAL_GB} GB (%${SWAP_PERCENT})${NC}"
        
        if [[ $SWAP_PERCENT -ge $SWAP_CRITICAL_THRESHOLD ]]; then
            echo -e "  ${RED}⚠️  CRITICAL: Swap almost full!${NC}"
        elif [[ $SWAP_PERCENT -ge $SWAP_WARNING_THRESHOLD ]]; then
            echo -e "  ${YELLOW}⚠️  WARNING: High swap usage${NC}"
        fi
        echo ""
    fi
    
    # zram status
    if [[ $ZRAM_TOTAL -gt 0 ]]; then
        local zram_color=$GREEN
        [[ $ZRAM_PERCENT -ge $ZRAM_WARNING_THRESHOLD ]] && zram_color=$YELLOW
        
        echo -e "${BOLD}zram (Compressed):${NC}"
        echo -e "  Usage: ${zram_color}${ZRAM_USED_GB} / ${ZRAM_TOTAL_GB} GB (%${ZRAM_PERCENT})${NC}"
        echo -e "  Compression: ${ZRAM_COMP_RATIO}x"
        echo ""
    fi
    
    # Top processes
    echo -e "${BOLD}Top RAM-Consuming Applications:${NC}"
    echo "$TOP_PROCESSES"
    echo ""
    
    # Thresholds
    echo -e "${BOLD}Notification Thresholds:${NC}"
    echo "  Swap Warning:  %$SWAP_WARNING_THRESHOLD"
    echo "  Swap Critical: %$SWAP_CRITICAL_THRESHOLD"
    echo "  zram Warning:  %$ZRAM_WARNING_THRESHOLD"
    echo "  Cooldown:      ${NOTIFICATION_COOLDOWN}s"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# INSTALL FUNCTION
#───────────────────────────────────────────────────────────────────────────────

do_install() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}SWAP MONITOR - KURULUM${NC}                                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # notify-send check
    if ! command -v notify-send &> /dev/null; then
        log_warning "notify-send not found. Installing..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y libnotify 2>/dev/null || {
                log_error "Could not install libnotify. Manual installation required:"
                echo "  sudo dnf install libnotify"
                return 1
            }
        else
            log_error "Package manager not found. Manual installation required."
            return 1
        fi
    fi
    log_success "notify-send available"
    
    # Copy script to ~/.local/bin
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    
    local script_path="$(readlink -f "$0")"
    cp "$script_path" "$install_dir/swap-monitor"
    chmod +x "$install_dir/swap-monitor"
    log_success "Script kuruldu: $install_dir/swap-monitor"
    
    # User systemd service directory
    local systemd_dir="$HOME/.config/systemd/user"
    mkdir -p "$systemd_dir"
    
    # Service file
    cat > "$systemd_dir/swap-monitor.service" << 'EOF'
[Unit]
Description=Swap Usage Monitor
Documentation=https://github.com/YOUR_USERNAME/fedora-memory-optimizer

[Service]
Type=oneshot
ExecStart=%h/.local/bin/swap-monitor --check
EOF
    log_success "Service created: swap-monitor.service"
    
    # Timer file (checks every 30 seconds)
    cat > "$systemd_dir/swap-monitor.timer" << 'EOF'
[Unit]
Description=Swap Monitor Timer
Documentation=https://github.com/YOUR_USERNAME/fedora-memory-optimizer

[Timer]
OnBootSec=60
OnUnitActiveSec=30
AccuracySec=10

[Install]
WantedBy=timers.target
EOF
    log_success "Timer created: swap-monitor.timer"
    
    # Systemd reload and enable
    systemctl --user daemon-reload
    systemctl --user enable swap-monitor.timer
    systemctl --user start swap-monitor.timer
    
    log_success "Timer started"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}     ${BOLD}INSTALLATION COMPLETE${NC}                                                ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Swap usage will be checked every 30 seconds."
    echo "  You will receive desktop notifications when thresholds are exceeded."
    echo ""
    echo "  ${BOLD}Komutlar:${NC}"
    echo "    swap-monitor --status    # Current status"
    echo "    swap-monitor --check     # Manual check"
    echo "    swap-monitor --test      # Test bildirimi"
    echo "    swap-monitor --uninstall # Remove"
    echo ""
    echo "  ${BOLD}Timer status:${NC}"
    systemctl --user status swap-monitor.timer --no-pager | head -5
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# UNINSTALL FUNCTION
#───────────────────────────────────────────────────────────────────────────────

do_uninstall() {
    echo ""
    log_info "Removing swap monitor..."
    
    # Stop and disable timer
    systemctl --user stop swap-monitor.timer 2>/dev/null || true
    systemctl --user disable swap-monitor.timer 2>/dev/null || true
    
    # Delete files
    rm -f "$HOME/.config/systemd/user/swap-monitor.service"
    rm -f "$HOME/.config/systemd/user/swap-monitor.timer"
    rm -f "$HOME/.local/bin/swap-monitor"
    rm -rf "$STATE_DIR"
    
    systemctl --user daemon-reload
    
    log_success "Swap monitor removed"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# TEST FUNCTION
#───────────────────────────────────────────────────────────────────────────────

do_test() {
    echo ""
    log_info "Sending test notification..."
    
    get_memory_info
    get_zram_info
    get_top_memory_processes
    
    send_notification "normal" \
        "🧪 Test Bildirimi" \
        "Swap Monitor is working!

RAM: ${MEM_USED_GB}/${MEM_TOTAL_GB} GB (%${MEM_PERCENT})
Swap: ${SWAP_USED_GB}/${SWAP_TOTAL_GB} GB (%${SWAP_PERCENT})

This is a test notification." \
        "info"
    
    log_success "Notification sent"
    echo ""
    echo "If you didn't see the notification:"
    echo "  1. notify-send kurulu mu? → which notify-send"
    echo "  2. Is desktop session active?"
    echo "  3. Is Do Not Disturb on?"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# USAGE
#───────────────────────────────────────────────────────────────────────────────

show_usage() {
    echo ""
    echo -e "${BOLD}Fedora Memory Optimizer - Swap Monitor v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage:"
    echo "  $0 --install     # Kurulum (user service)"
    echo "  $0 --uninstall   # Removema"
    echo "  $0 --status      # Current memory status"
    echo "  $0 --check       # Check and notify if needed"
    echo "  $0 --test        # Send test notification"
    echo "  $0 --help        # This help"
    echo ""
    echo "Thresholds (edit script to change):"
    echo "  SWAP_WARNING_THRESHOLD=$SWAP_WARNING_THRESHOLD%"
    echo "  SWAP_CRITICAL_THRESHOLD=$SWAP_CRITICAL_THRESHOLD%"
    echo "  NOTIFICATION_COOLDOWN=${NOTIFICATION_COOLDOWN}s"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN
#───────────────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --install|-i)
        do_install
        ;;
    --uninstall|-u)
        do_uninstall
        ;;
    --status|-s)
        do_status
        ;;
    --check|-c)
        do_check
        ;;
    --test|-t)
        do_test
        ;;
    --help|-h)
        show_usage
        ;;
    "")
        show_usage
        ;;
    *)
        log_error "Bilinmeyen parametre: $1"
        show_usage
        exit 1
        ;;
esac
