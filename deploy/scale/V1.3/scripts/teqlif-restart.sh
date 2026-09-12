#!/usr/bin/env bash
# teqlif-restart — Kodu günceller, stack'i yeniden başlatır, süreci canlı izler.
#
# Kullanım:
#   sudo teqlif-restart            # ortam otomatik tespit edilir
#   sudo teqlif-restart prod       # zorunlu override
#   sudo teqlif-restart staging    # zorunlu override
#
# Kurulum (VPS'te bir kez):
#   sudo install -m 755 /var/www/teqlif.com/deploy/scale/V1.3/scripts/teqlif-restart.sh \
#        /usr/local/bin/teqlif-restart

set -euo pipefail

REPO_DIR="/var/www/teqlif.com"

# ── ortam tespiti ─────────────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
    ENV="$1"
elif systemctl cat teqlif.service &>/dev/null; then
    ENV="prod"
elif systemctl cat teqlif-staging.service &>/dev/null; then
    ENV="staging"
else
    echo "Hata: teqlif.service veya teqlif-staging.service bulunamadı." >&2
    exit 1
fi

case "$ENV" in
    prod|production)
        MAIN_SVC="teqlif"
        WORKER_SVC="teqlif-worker"
        WORKER_CRIT_SVC="teqlif-worker-critical"
        ENV_LABEL="PRODUCTION"
        HEADER_CLR="\033[0;31m"
        ;;
    staging)
        MAIN_SVC="teqlif-staging"
        WORKER_SVC="teqlif-worker-staging"
        WORKER_CRIT_SVC="teqlif-worker-critical-staging"
        ENV_LABEL="STAGING"
        HEADER_CLR="\033[0;33m"
        ;;
    *)
        echo "Hata: geçersiz ortam '$ENV'. prod veya staging kullanın." >&2
        exit 1
        ;;
esac

# ── renkler ───────────────────────────────────────────────────────────────────
R="\033[0m"; B="\033[1m"; D="\033[2m"
G="\033[0;32m"; RE="\033[0;31m"; Y="\033[1;33m"; C="\033[0;36m"
HR="${B}${HEADER_CLR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"

# ── başlık ────────────────────────────────────────────────────────────────────
echo ""
echo -e "$HR"
printf "${B}  Teqlif Deploy  ${HEADER_CLR}%-10s${R}  ${D}%s${R}\n" \
       "$ENV_LABEL" "$(date '+%Y-%m-%d %H:%M:%S')"
echo -e "$HR"
echo ""

# ── 1. git pull ───────────────────────────────────────────────────────────────
echo -e "${B}[1/4] git pull${R}"
cd "$REPO_DIR"

GIT_BEFORE=$(git rev-parse HEAD)

if ! git pull --ff-only 2>&1 | sed 's/^/  /'; then
    echo -e "  ${RE}git pull başarısız — yerel değişiklik veya çakışma var.${R}" >&2
    exit 1
fi

GIT_AFTER=$(git rev-parse HEAD)

if [[ "$GIT_BEFORE" == "$GIT_AFTER" ]]; then
    echo -e "  ${D}Değişiklik yok — zaten güncel.${R}"
else
    CHANGED=$(git diff --name-only "$GIT_BEFORE" "$GIT_AFTER" | wc -l | tr -d ' ')
    echo -e "  ${G}${CHANGED} dosya güncellendi:${R}"
    git log --oneline "$GIT_BEFORE..$GIT_AFTER" | sed 's/^/    /'
fi
echo ""

# ── 2. mevcut durum ───────────────────────────────────────────────────────────
svc_state() { systemctl is-active "$1" 2>/dev/null || echo "unknown"; }

echo -e "${B}[2/4] Mevcut durum${R}"
for svc in "$MAIN_SVC" "$WORKER_SVC" "$WORKER_CRIT_SVC"; do
    st=$(svc_state "$svc")
    case "$st" in
        active)   clr="$G"  ;;
        inactive) clr="$D"  ;;
        *)        clr="$RE" ;;
    esac
    printf "  %-52s ${clr}%s${R}\n" "$svc" "$st"
done
echo ""

# ── 3. restart ────────────────────────────────────────────────────────────────
SINCE="$(date '+%Y-%m-%d %H:%M:%S')"

echo -e "${B}[3/4] Restart${R}"
echo -e "  ${D}► ExecStartPre-1  alembic upgrade head${R}"
echo -e "  ${D}► ExecStartPre-2  sync_main.py${R}"
echo -e "  ${D}► ExecStart       uvicorn${R}"
echo ""
echo -e "${C}${B}─── canlı journal ──────────────────────────────────────────────────${R}"

systemctl restart "$MAIN_SVC" &
RESTART_PID=$!

journalctl -u "$MAIN_SVC" -f --since "$SINCE" --no-pager --output=short-precise 2>/dev/null &
JOURNAL_PID=$!

MAX_WAIT=300; WAITED=0
while (( WAITED < MAX_WAIT )); do
    sleep 3; WAITED=$(( WAITED + 3 ))
    st=$(svc_state "$MAIN_SVC")
    [[ "$st" == "active" || "$st" == "failed" || "$st" == "inactive" ]] && break
done

sleep 1
kill "$JOURNAL_PID" 2>/dev/null || true
wait "$JOURNAL_PID" 2>/dev/null || true
wait "$RESTART_PID" 2>/dev/null || true

echo -e "${C}${B}────────────────────────────────────────────────────────────────────${R}"
echo ""

# ── 4. sonuç ─────────────────────────────────────────────────────────────────
echo -e "${B}[4/4] Durum${R}"
echo ""

FAILED=()

report_service() {
    local svc="$1" st pid started
    st=$(svc_state "$svc")
    if [[ "$st" == "active" ]]; then
        pid=$(systemctl show "$svc" --property=MainPID --value 2>/dev/null || echo "?")
        started=$(systemctl show "$svc" --property=ActiveEnterTimestamp --value 2>/dev/null \
            | sed 's/ [A-Z]*$//' | awk '{print $2, $3}')
        printf "  ${G}${B}✓ ACTIVE${R}   ${B}%-44s${R}  ${D}pid=%-6s  %s${R}\n" \
               "$svc" "$pid" "$started"
    else
        printf "  ${RE}${B}✗ %-8s${R}  ${B}%s${R}\n" "${st^^}" "$svc"
        FAILED+=("$svc")
    fi
}

report_service "$MAIN_SVC"
report_service "$WORKER_SVC"
report_service "$WORKER_CRIT_SVC"
echo ""

# ── başarı ────────────────────────────────────────────────────────────────────
if (( ${#FAILED[@]} == 0 )); then
    echo -e "$HR"
    echo -e "${G}${B}  ✓  Deploy başarılı — tüm servisler aktif.${R}"
    echo -e "$HR"
    echo ""
    exit 0
fi

# ── hata raporu ───────────────────────────────────────────────────────────────
echo -e "${RE}${B}  ✗  ${#FAILED[@]} servis başlatılamadı: ${FAILED[*]}${R}"
echo ""

for svc in "${FAILED[@]}"; do
    echo -e "${RE}${B}━━━━━━ Hata Raporu: ${svc} $(printf '━%.0s' {1..38})${R}"
    echo ""
    echo -e "${B}▸ systemctl status:${R}"
    systemctl status "$svc" --no-pager -l 2>&1 || true
    echo ""
    echo -e "${B}▸ Son 200 satır journal:${R}"
    journalctl -u "$svc" --no-pager -n 200 --output=short-precise 2>&1 || true
    echo ""
    echo -e "${RE}${B}$(printf '━%.0s' {1..72})${R}"
    echo ""
done

echo -e "${Y}StartLimitBurst aşıldıysa önce sayacı sıfırlayın:${R}"
for svc in "${FAILED[@]}"; do
    echo -e "  ${D}sudo systemctl reset-failed ${svc}${R}"
done
echo ""
exit 1
