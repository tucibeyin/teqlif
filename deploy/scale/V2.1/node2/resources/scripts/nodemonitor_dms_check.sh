#!/bin/bash
# Dead Man's Switch: nodeMonitor (Prometheus + Alertmanager) erişilebilirlik kontrolü.
# teqlif izleme altyapısından (nodeMonitor) BAĞIMSIZ çalışır — node2'den başlatılır.
#
# Davranış:
#   Her çalışmada Prometheus /-/healthy ve Alertmanager /-/healthy kontrol edilir.
#   Her iki endpoint de yanıt verirse sayaç sıfırlanır.
#   3 ardışık başarısızlıkta Telegram uyarısı gönderilir.
#   Cooldown (30 dk) boyunca tekrar alarm gönderilmez.
#   Kurtarma (başarılı check sonrası): "nodeMonitor kurtarıldı" bildirimi.
#
# Bağımlılıklar: bash, curl, python3, /project/teqlif/config/.env.backup
set -euo pipefail

source /project/teqlif/config/.env.backup

FAILURES_DIR=/var/lib/teqlif-dms
FAILURES_FILE="${FAILURES_DIR}/failures"
ALERT_COOLDOWN_FILE="${FAILURES_DIR}/last_alert"
ALERT_SENT_FILE="${FAILURES_DIR}/alert_active"
MAX_FAILURES=3
ALERT_COOLDOWN_SEC=1800   # 30 dakika — aynı arıza için tekrar alarm

PROM_URL="http://10.10.0.99:9090/-/healthy"
# Alertmanager 127.0.0.1:9093 — sadece localhost dinliyor, WireGuard üzerinden ulaşılamaz
# Prometheus sağlıklıysa izleme altyapısı çalışıyor demektir; AM check kaldırıldı

mkdir -p "${FAILURES_DIR}"
chmod 700 "${FAILURES_DIR}"

check_healthy() {
    curl -sf --max-time 5 "$1" > /dev/null 2>&1
}

current_failures() {
    cat "${FAILURES_FILE}" 2>/dev/null || echo 0
}

reset_failures() {
    echo 0 > "${FAILURES_FILE}"
}

increment_failures() {
    local n
    n=$(current_failures)
    echo $((n + 1)) > "${FAILURES_FILE}"
}

send_telegram() {
    export DMS_TEXT="$1"
    python3 - <<'PYEOF'
import urllib.request, json, os, sys

token   = os.environ.get('TELEGRAM_BOT_TOKEN', '')
chat_id = os.environ.get('TELEGRAM_CHAT_ID', '')
text    = os.environ.get('DMS_TEXT', '')
if not token or not chat_id:
    sys.exit(0)

data = json.dumps({'chat_id': chat_id, 'text': text, 'parse_mode': 'HTML'}).encode()
req  = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/sendMessage',
    data=data,
    headers={'Content-Type': 'application/json'},
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print(f'telegram DMS notify failed: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
}

in_cooldown() {
    if [ ! -f "${ALERT_COOLDOWN_FILE}" ]; then return 1; fi
    local last_ts
    last_ts=$(cat "${ALERT_COOLDOWN_FILE}")
    local now
    now=$(date +%s)
    [ $((now - last_ts)) -lt ${ALERT_COOLDOWN_SEC} ]
}

set_cooldown() {
    date +%s > "${ALERT_COOLDOWN_FILE}"
}

# ── Ana kontrol ───────────────────────────────────────────────────────────────
prom_ok=0
check_healthy "${PROM_URL}" && prom_ok=1 || true

if [ "${prom_ok}" -eq 1 ]; then
    was_active=0
    [ -f "${ALERT_SENT_FILE}" ] && was_active=1
    reset_failures
    if [ "${was_active}" -eq 1 ]; then
        rm -f "${ALERT_COOLDOWN_FILE}" "${ALERT_SENT_FILE}"
        send_telegram "✅ <b>nodeMonitor kurtarıldı</b> — Prometheus ve Alertmanager tekrar erişilebilir." || true
        logger "teqlif-dms: nodeMonitor kurtarıldı"
    fi
    exit 0
fi

# Başarısız: sayacı artır
increment_failures
failures=$(current_failures)
logger "teqlif-dms: nodeMonitor Prometheus erişilemiyor (ardışık=${failures})"

if [ "${failures}" -lt "${MAX_FAILURES}" ]; then
    exit 0
fi

# Eşik aşıldı — alarm gönder (cooldown kontrolü)
if in_cooldown; then
    exit 0
fi

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

send_telegram "🚨 <b>nodeMonitor ÇÖKTÜ!</b>
${ts}
Prometheus ❌ (10.10.0.99:9090 yanıt vermiyor)
Ardışık başarısız kontrol: ${failures}

<b>nodeMonitor (10.10.0.99) erişilemiyor.</b> İzleme altyapısı ve teqlif-agent lider çalışmıyor olabilir." || true

set_cooldown
touch "${ALERT_SENT_FILE}"
logger "teqlif-dms: nodeMonitor DOWN alarmı gönderildi (ardışık=${failures})"
