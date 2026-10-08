#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  teqlif V2.1 — node1 Tam Çöküş Kurtarma Runbook                           ║
# ║                                                                              ║
# ║  ÇALIŞTIRILACAK YER: node2                                                  ║
# ║  KULLANIM: sudo bash runbook.sh                                              ║
# ║                                                                              ║
# ║  İki mod (otomatik seçilir):                                                 ║
# ║    PITR  — pg_basebackup + WAL replay → RPO ~1 dk  (tercih edilen)          ║
# ║    DUMP  — pg_dump restore            → RPO ~24 saat (fallback)             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_step() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }
log_ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
log_err()  { echo -e "${RED}  ✗${NC} $*" >&2; }
confirm()  {
    echo -e "${YELLOW}  → $1${NC}"
    read -r -p "    Devam et? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || { echo "İptal edildi."; exit 1; }
}

# ── Sabitler ─────────────────────────────────────────────────────────────────
NODE2_IP="135.125.223.43"
NODE1_WG="10.10.0.1"
PG_DATA="/var/lib/postgresql/17/main"
PG_CONF="/etc/postgresql/17/main"
WAL_DIR="/project/teqlif/backups/pg_wal"
BASEBACKUP_DIR="/project/teqlif/backups/pg_basebackup"
DUMP_DIR="/project/teqlif/backups/pg_dump"
RESTORE_DIR="/project/teqlif/recovery/pg_restore"
LOG="/project/teqlif/logs/runbook_$(date +%Y%m%d_%H%M%S).log"

source /project/teqlif/config/.env.backup

# ── Yetki kontrolü ───────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || { log_err "sudo ile çalıştırın: sudo bash $0"; exit 1; }

exec > >(tee -a "${LOG}") 2>&1

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       teqlif node1 Kurtarma Runbook — $(date -u +%Y-%m-%d\ %H:%M\ UTC)     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
log_warn "Bu script node1 tamamen erişilemez olduğunda çalıştırılır."
log_warn "Log: ${LOG}"
echo ""

# ────────────────────────────────────────────────────────────────────────────
log_step "1. Ön Kontroller"
# ────────────────────────────────────────────────────────────────────────────

# node1 gerçekten çökmüş mü?
if ping -c 2 -W 2 "${NODE1_WG}" >/dev/null 2>&1; then
    log_warn "node1 (${NODE1_WG}) PING'e yanıt veriyor!"
    confirm "node1 erişilebilir görünüyor. Yine de devam etmek istiyor musun?"
else
    log_ok "node1 erişilemez — devam."
fi

# WAL güncelliği
log_step "WAL Segment Durumu"
LATEST_WAL=$(ls -t "${WAL_DIR}" 2>/dev/null | head -1)
if [ -z "${LATEST_WAL}" ]; then
    log_warn "WAL dizini boş: ${WAL_DIR}"
else
    WAL_AGE=$(( $(date +%s) - $(stat -c %Y "${WAL_DIR}/${LATEST_WAL}") ))
    WAL_AGE_MIN=$(( WAL_AGE / 60 ))
    if [ "${WAL_AGE_MIN}" -lt 5 ]; then
        log_ok "Son WAL segmenti ${WAL_AGE_MIN} dk önce (${LATEST_WAL})"
    else
        log_warn "Son WAL segmenti ${WAL_AGE_MIN} dk önce — pg_receivewal durmuş olabilir"
    fi
fi

# pg_receivewal durdur
log_step "2. pg_receivewal Durdur"
if systemctl is-active teqlif-pg-receivewal >/dev/null 2>&1; then
    systemctl stop teqlif-pg-receivewal
    log_ok "teqlif-pg-receivewal durduruldu"
else
    log_ok "teqlif-pg-receivewal zaten durmuş"
fi

# ────────────────────────────────────────────────────────────────────────────
log_step "3. Kurtarma Modu Seç"
# ────────────────────────────────────────────────────────────────────────────

LATEST_BASEBACKUP=$(ls -1dt "${BASEBACKUP_DIR}"/[0-9]* 2>/dev/null | head -1 || true)
LATEST_DUMP=$(ls -1t "${DUMP_DIR}"/teqlif_*.dump* 2>/dev/null | head -1 || true)

if [ -n "${LATEST_BASEBACKUP}" ]; then
    BB_AGE=$(( ( $(date +%s) - $(stat -c %Y "${LATEST_BASEBACKUP}") ) / 3600 ))
    log_ok "pg_basebackup bulundu: $(basename ${LATEST_BASEBACKUP}) (${BB_AGE} saat önce)"
    log_ok "WAL ile birlikte RPO ~1 dk"
    RESTORE_MODE="PITR"
else
    log_warn "pg_basebackup YOK — pg_dump'a düşülüyor (RPO ~24 saat)"
    if [ -z "${LATEST_DUMP}" ]; then
        log_err "pg_dump da bulunamadı! ${DUMP_DIR} kontrol et."
        exit 1
    fi
    DUMP_AGE=$(( ( $(date +%s) - $(stat -c %Y "${LATEST_DUMP}") ) / 3600 ))
    log_ok "pg_dump bulundu: $(basename ${LATEST_DUMP}) (${DUMP_AGE} saat önce)"
    RESTORE_MODE="DUMP"
fi

echo ""
echo -e "  Kurtarma modu: ${BOLD}${RESTORE_MODE}${NC}"
confirm "Kurtarmaya başlanacak. Onaylıyor musun?"

# ────────────────────────────────────────────────────────────────────────────
log_step "4. PostgreSQL Hazırlık"
# ────────────────────────────────────────────────────────────────────────────

# Önce mevcut PG instance'ını durdur
systemctl stop postgresql 2>/dev/null || true
log_ok "Mevcut PostgreSQL durduruldu (varsa)"

if [ "${RESTORE_MODE}" = "PITR" ]; then
    # ── PITR: pg_basebackup + WAL replay ─────────────────────────────────────
    log_step "4a. PITR — Base Backup Geri Yükle"

    install -d "${RESTORE_DIR}"
    rm -rf "${PG_DATA}"
    install -d -o postgres -g postgres -m 700 "${PG_DATA}"

    # base.tar.gz'yi data dizinine aç
    BASE_TAR="${LATEST_BASEBACKUP}/base.tar.gz"
    log_ok "Aç: ${BASE_TAR} → ${PG_DATA}"
    sudo -u postgres tar -xzf "${BASE_TAR}" -C "${PG_DATA}"

    # pg_wal içeriğini WAL dizininden tamamla
    log_ok "WAL dizini: ${WAL_DIR}"
    sudo -u postgres mkdir -p "${PG_DATA}/pg_wal"

    # restore_command yapılandır
    cat > "${PG_CONF}/conf.d/recovery.conf" <<EOF
restore_command = 'cp ${WAL_DIR}/%f %p'
recovery_target = 'immediate'
EOF
    chown postgres:postgres "${PG_CONF}/conf.d/recovery.conf"

    # recovery.signal oluştur
    sudo -u postgres touch "${PG_DATA}/recovery.signal"
    log_ok "recovery.signal oluşturuldu — PG başlarken WAL replay yapacak"

else
    # ── DUMP: pg_restore ──────────────────────────────────────────────────────
    log_step "4b. DUMP — pg_restore"
    log_ok "Kaynak: ${LATEST_DUMP}"

    # node2 local PostgreSQL başlat (varsa, temiz halde)
    systemctl start postgresql
    sleep 3

    # Veritabanı oluştur ve restore et
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS teqlif;" postgres || true
    sudo -u postgres psql -c "CREATE DATABASE teqlif OWNER teqlif;" postgres

    EXT="${LATEST_DUMP##*.}"
    if [ "${EXT}" = "gz" ]; then
        zcat "${LATEST_DUMP}" | sudo -u postgres pg_restore -d teqlif --no-owner --role=teqlif
    else
        sudo -u postgres pg_restore -h 127.0.0.1 -d teqlif --no-owner --role=teqlif "${LATEST_DUMP}"
    fi
    log_ok "pg_restore tamamlandı"
fi

# ────────────────────────────────────────────────────────────────────────────
log_step "5. PostgreSQL Başlat"
# ────────────────────────────────────────────────────────────────────────────

systemctl start postgresql
sleep 5

if sudo -u postgres psql -At -c "SELECT 'OK';" teqlif 2>/dev/null | grep -q OK; then
    log_ok "PostgreSQL ayakta — teqlif veritabanı erişilebilir"
else
    log_err "PostgreSQL başlatılamadı! 'journalctl -u postgresql' kontrol et."
    exit 1
fi

if [ "${RESTORE_MODE}" = "PITR" ]; then
    # PITR tamamlanınca recovery.signal otomatik silinir
    # conf.d/recovery.conf'u temizle (artık gerekmiyor)
    rm -f "${PG_CONF}/conf.d/recovery.conf"
    systemctl reload postgresql 2>/dev/null || true
    log_ok "PITR tamamlandı — recovery modu kapatıldı"
fi

# ────────────────────────────────────────────────────────────────────────────
log_step "6. DNS Değişikliği (MANUEL)"
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}  Cloudflare panelinde şu A kayıtlarını ${NODE2_IP} yap:${NC}"
echo ""
echo -e "  ${YELLOW}teqlif.com${NC}         A  →  ${NODE2_IP}  (Proxied)"
echo -e "  ${YELLOW}www.teqlif.com${NC}     A  →  ${NODE2_IP}  (Proxied)"
echo -e "  ${YELLOW}api.teqlif.com${NC}     A  →  ${NODE2_IP}  (Proxied)"
echo -e "  ${YELLOW}uploads.teqlif.com${NC} A  →  ${NODE2_IP}  (DNS Only)"
echo ""
echo -e "  URL: ${CYAN}https://dash.cloudflare.com → teqlif.com → DNS${NC}"
echo ""
confirm "DNS değişikliklerini yaptın mı?"

# ────────────────────────────────────────────────────────────────────────────
log_step "7. Özet"
# ────────────────────────────────────────────────────────────────────────────

echo ""
log_ok "PostgreSQL: çalışıyor (node2 local, 127.0.0.1:5432)"
log_ok "Kurtarma modu: ${RESTORE_MODE}"
log_ok "DNS: node2'ye (${NODE2_IP}) yönlendirildi"
log_ok "Log dosyası: ${LOG}"
echo ""
echo -e "${YELLOW}  NOTLAR:${NC}"
echo "  • node2 HDD (~445 IOPS) — node1 NVMe'ye kıyasla %5-15 PG performansı"
echo "  • ML batch job'ları ve analytics pipeline'ı çalışmasın (${YELLOW}sudo systemctl stop teqlif-worker${NC})"
echo "  • FastAPI node2'de çalışmıyor — kullanıcı trafiği node2'ye ulaşıyor ama API cevap veremez"
echo -e "  ${RED}• FastAPI kurulumu bu runbook kapsamında değil — node1'i kurtarmak öncelik!${NC}"
echo ""
echo -e "${BOLD}  GERİ DÖNÜŞ (node1 kurtarıldığında):${NC}"
echo "  1. node1 bootstrap: sudo teqlif-restart"
echo "  2. node2'den pg_dump al: pg_dump -h 127.0.0.1 -U teqlif -Fc teqlif > /tmp/recovery.dump"
echo "  3. node1'e restore: scp /tmp/recovery.dump node1:/tmp/ && ssh node1 pg_restore ..."
echo "  4. DNS'i node1'e geri al"
echo "  5. pg_receivewal yeniden başlat: sudo systemctl start teqlif-pg-receivewal"
echo ""
echo -e "${GREEN}  Runbook tamamlandı — $(date -u +%Y-%m-%dT%H:%M:%SZ)${NC}"
