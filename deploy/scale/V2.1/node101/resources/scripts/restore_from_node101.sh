#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  teqlif V2.1 — node101 Offsite Felaket Kurtarma                            ║
# ║                                                                              ║
# ║  ÇALIŞTIRILACAK YER: node101 (root)                                         ║
# ║  KULLANIM: sudo bash restore_from_node101.sh                                 ║
# ║                                                                              ║
# ║  Senaryolar:                                                                 ║
# ║    DUMP  — pg_dump restore → RPO ~24 saat (hızlı)                           ║
# ║    PITR  — pg_basebackup + WAL → RPO ~1 saat (tam kurtarma)                 ║
# ║    LIST  — Mevcut snapshot'ları listele                                      ║
# ║    CHECK — Bütünlük doğrulaması (restic check)                               ║
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

[ "$(id -u)" -eq 0 ] || { log_err "sudo ile çalıştırın: sudo bash $0"; exit 1; }

RESTIC_ENV=/etc/teqlif-offsite/restic.env
[ -f "${RESTIC_ENV}" ] || { log_err "${RESTIC_ENV} bulunamadı"; exit 1; }

# shellcheck source=/dev/null
. "${RESTIC_ENV}"
export RESTIC_REPOSITORY RESTIC_PASSWORD
export RESTIC_CACHE_DIR=/mnt/data/cache/restic
export TMPDIR=/mnt/data/tmp
mkdir -p "${RESTIC_CACHE_DIR}" "${TMPDIR}"

LOG=/mnt/data/tmp/restore_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "${LOG}") 2>&1

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   teqlif node101 Kurtarma — $(date -u +%Y-%m-%d\ %H:%M\ UTC)         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Log: ${LOG}"
echo ""

# ── Mod seçimi ───────────────────────────────────────────────────────────────
MODE="${1:-}"
if [ -z "${MODE}" ]; then
    echo "Mod seçin:"
    echo "  1) LIST  — Snapshot'ları listele"
    echo "  2) CHECK — Bütünlük kontrolü (restic check --read-data-subset=5%)"
    echo "  3) DUMP  — pg_dump restore (RPO ~24 saat)"
    echo "  4) PITR  — pg_basebackup + WAL (RPO ~1 saat)"
    read -r -p "Seçiminiz [1-4]: " choice
    case "${choice}" in
        1) MODE=LIST  ;;
        2) MODE=CHECK ;;
        3) MODE=DUMP  ;;
        4) MODE=PITR  ;;
        *) log_err "Geçersiz seçim"; exit 1 ;;
    esac
fi

# ════════════════════════════════════════════════════════════════════════════
# LIST
# ════════════════════════════════════════════════════════════════════════════
if [ "${MODE}" = "LIST" ]; then
    log_step "Snapshot Listesi"
    restic snapshots
    echo ""
    echo "Tag bazlı özet:"
    echo "  daily-full : $(restic snapshots --tag daily-full --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")"
    echo "  pg_wal     : $(restic snapshots --tag pg_wal     --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# CHECK
# ════════════════════════════════════════════════════════════════════════════
if [ "${MODE}" = "CHECK" ]; then
    log_step "Bütünlük Kontrolü"
    restic check --read-data-subset=5%
    log_ok "Bütünlük kontrolü tamamlandı"
    exit 0
fi

# ── Hedef sunucu bilgisi ─────────────────────────────────────────────────────
log_step "Hedef Sunucu"
read -r -p "  Yeni node1 IP adresi (boş = yerel /mnt/data/tmp/restore): " TARGET_IP
RESTORE_BASE=$(mktemp -d /mnt/data/tmp/restore_$(date +%Y%m%d)_XXXXXX)
log_ok "Çalışma dizini: ${RESTORE_BASE}"

# ── Snapshot seçimi ──────────────────────────────────────────────────────────
log_step "Snapshot Seçimi"
restic snapshots --tag daily-full
echo ""
read -r -p "  Kullanılacak snapshot ID (boş = latest): " SNAP_ID
SNAP_ID="${SNAP_ID:-latest}"
log_ok "Snapshot: ${SNAP_ID}"

# ════════════════════════════════════════════════════════════════════════════
# DUMP RESTORE
# ════════════════════════════════════════════════════════════════════════════
if [ "${MODE}" = "DUMP" ]; then
    log_step "pg_dump Restore"
    confirm "Snapshot '${SNAP_ID}' pg_dump dosyası ${RESTORE_BASE} dizinine çıkarılacak"

    restic restore "${SNAP_ID}" \
        --tag daily-full \
        --include /project/teqlif/backups/pg_dump \
        --target "${RESTORE_BASE}"

    DUMP_DIR="${RESTORE_BASE}/project/teqlif/backups/pg_dump"
    DUMP_FILE=$(ls "${DUMP_DIR}"/teqlif_*.dump 2>/dev/null | sort | tail -1)
    [ -f "${DUMP_FILE}" ] || { log_err "Dump dosyası bulunamadı: ${DUMP_DIR}"; exit 1; }

    log_step "pg_restore --list Doğrulaması"
    TABLE_COUNT=$(pg_restore --list "${DUMP_FILE}" 2>/dev/null | grep -c "TABLE DATA" || echo "0")
    log_ok "Dump: ${DUMP_FILE} ($(du -sh "${DUMP_FILE}" | cut -f1))"
    log_ok "Tablo verisi nesne sayısı: ${TABLE_COUNT}"
    pg_restore --list "${DUMP_FILE}" > /dev/null
    log_ok "pg_restore --list: GEÇTI"

    if [ -n "${TARGET_IP}" ]; then
        log_step "Yeni Sunucuya Transfer"
        confirm "pg_dump dosyası ${TARGET_IP}:/project/teqlif/backups/pg_dump/ adresine rsync edilecek"
        rsync -avz --progress "${DUMP_DIR}/" "${TARGET_IP}:/project/teqlif/backups/pg_dump/"
        log_ok "Transfer tamamlandı"
        log_warn "Yeni sunucuda 'runbook.sh DUMP' modunu çalıştırın"
    else
        log_warn "Target IP girilmedi — dosyalar ${RESTORE_BASE} içinde"
        log_warn "Manuel transfer: rsync -avz ${RESTORE_BASE}/project/teqlif/backups/pg_dump/ <YENI_NODE>:/project/teqlif/backups/pg_dump/"
    fi

    rm -rf "${RESTORE_BASE}"
    log_ok "Geçici dizin temizlendi"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# PITR RESTORE
# ════════════════════════════════════════════════════════════════════════════
if [ "${MODE}" = "PITR" ]; then
    log_step "pg_basebackup + WAL (PITR) Restore"
    log_warn "Bu mod pg_basebackup + pg_wal verilerini çıkarır."
    log_warn "Yeni node1 üzerinde mevcut PGDATA'yı siler ve PITR uygular."
    confirm "Snapshot '${SNAP_ID}' basebackup+WAL ${RESTORE_BASE} dizinine çıkarılacak"

    restic restore "${SNAP_ID}" \
        --tag daily-full \
        --include /project/teqlif/backups/pg_basebackup \
        --include /project/teqlif/backups/pg_wal \
        --target "${RESTORE_BASE}"

    BB_DIR="${RESTORE_BASE}/project/teqlif/backups/pg_basebackup"
    WAL_DIR="${RESTORE_BASE}/project/teqlif/backups/pg_wal"

    log_ok "Basebackup dizini: ${BB_DIR}"
    ls -1 "${BB_DIR}/" 2>/dev/null | head -5

    # En yeni basebackup tarih dizini
    BB_TARIH=$(ls -1 "${BB_DIR}" 2>/dev/null | sort | tail -1)
    BASE_TAR="${BB_DIR}/${BB_TARIH}/base.tar.gz"
    WAL_TAR="${BB_DIR}/${BB_TARIH}/pg_wal.tar.gz"

    [ -f "${BASE_TAR}" ] || { log_err "base.tar.gz bulunamadı: ${BASE_TAR}"; exit 1; }
    log_ok "base.tar.gz: ${BASE_TAR} ($(du -sh "${BASE_TAR}" | cut -f1))"
    log_ok "WAL segmentleri: ${WAL_DIR} ($(du -sh "${WAL_DIR}" 2>/dev/null | cut -f1))"

    if [ -n "${TARGET_IP}" ]; then
        log_step "Yeni Sunucuya Transfer"
        confirm "Basebackup ve WAL verileri ${TARGET_IP} adresine gönderilecek"
        rsync -avz --progress "${BB_DIR}/" "${TARGET_IP}:/project/teqlif/backups/pg_basebackup/"
        rsync -avz --progress "${WAL_DIR}/" "${TARGET_IP}:/project/teqlif/backups/pg_wal/"
        log_ok "Transfer tamamlandı"
        log_warn "Yeni sunucuda runbook.sh PITR modunu çalıştırın"
    else
        log_warn "Target IP girilmedi — dosyalar ${RESTORE_BASE} içinde"
        echo ""
        echo "  Manuel PITR adımları (yeni node1 üzerinde):"
        echo "  1. sudo systemctl stop postgresql@17-main"
        echo "  2. sudo rm -rf /var/lib/postgresql/17/main"
        echo "  3. sudo install -d -o postgres -g postgres -m 700 /var/lib/postgresql/17/main"
        echo "  4. sudo -u postgres tar -xzf ${BASE_TAR} -C /var/lib/postgresql/17/main"
        echo "  5. sudo -u postgres mkdir -p /var/lib/postgresql/17/main/pg_wal"
        echo "  6. sudo -u postgres tar -xzf ${WAL_TAR} -C /var/lib/postgresql/17/main/pg_wal/"
        echo "  7. echo \"restore_command = 'cp ${WAL_DIR}/%f %p'\" | sudo -u postgres tee -a /var/lib/postgresql/17/main/postgresql.auto.conf"
        echo "  8. sudo -u postgres touch /var/lib/postgresql/17/main/recovery.signal"
        echo "  9. sudo systemctl start postgresql@17-main"
        echo "  10. sudo -u postgres psql -c \"SELECT pg_is_in_recovery();\"  # → f (promoted)"
    fi

    rm -rf "${RESTORE_BASE}"
    log_ok "Geçici dizin temizlendi"
    exit 0
fi

log_err "Bilinmeyen mod: ${MODE}"
exit 1
