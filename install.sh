#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# Fedora Memory Optimizer - OOM Protection Installer
# Bu script düzeltilmiş dosyaları sisteme kurar ve servisleri başlatır
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Fedora Memory Optimizer - OOM Protection Installer${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Root kontrolü
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}HATA: Bu script root olarak çalıştırılmalı${NC}"
    echo "Kullanım: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}[1/5]${NC} Daemon script kopyalanıyor..."
cp "${SCRIPT_DIR}/scripts/oom-protection-daemon.sh" /usr/local/bin/oom-protection-daemon
chmod +x /usr/local/bin/oom-protection-daemon
echo -e "      ${GREEN}✓${NC} /usr/local/bin/oom-protection-daemon"

echo -e "${YELLOW}[2/5]${NC} earlyoom config kopyalanıyor..."
cp "${SCRIPT_DIR}/config/oom/earlyoom.conf" /etc/default/earlyoom
echo -e "      ${GREEN}✓${NC} /etc/default/earlyoom"

echo -e "${YELLOW}[3/5]${NC} Systemd daemon-reload..."
systemctl daemon-reload
echo -e "      ${GREEN}✓${NC} daemon-reload tamamlandı"

echo -e "${YELLOW}[4/5]${NC} Servisler yeniden başlatılıyor..."

# earlyoom restart
if systemctl is-enabled earlyoom &>/dev/null; then
    systemctl restart earlyoom
    echo -e "      ${GREEN}✓${NC} earlyoom yeniden başlatıldı"
else
    echo -e "      ${YELLOW}!${NC} earlyoom aktif değil, başlatılıyor..."
    systemctl enable --now earlyoom
    echo -e "      ${GREEN}✓${NC} earlyoom aktifleştirildi ve başlatıldı"
fi

# oom-protection-daemon restart
if systemctl is-enabled oom-protection-daemon &>/dev/null; then
    systemctl restart oom-protection-daemon
    echo -e "      ${GREEN}✓${NC} oom-protection-daemon yeniden başlatıldı"
else
    echo -e "      ${YELLOW}!${NC} oom-protection-daemon aktif değil, başlatılıyor..."
    systemctl enable --now oom-protection-daemon
    echo -e "      ${GREEN}✓${NC} oom-protection-daemon aktifleştirildi ve başlatıldı"
fi

echo -e "${YELLOW}[5/5]${NC} Servis durumları kontrol ediliyor..."
echo ""

echo -e "${GREEN}─── earlyoom durumu ───${NC}"
systemctl status earlyoom --no-pager -l 2>&1 | head -15 || true
echo ""

echo -e "${GREEN}─── oom-protection-daemon durumu ───${NC}"
systemctl status oom-protection-daemon --no-pager -l 2>&1 | head -15 || true
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Kurulum tamamlandı!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Test için:"
echo "  sudo /usr/local/bin/oom-protection-daemon run-once"
echo ""
echo "Log takibi için:"
echo "  sudo journalctl -u oom-protection-daemon -f"
echo "  sudo journalctl -u earlyoom -f"
