#!/usr/bin/env bash
# redis_failover.sh — node2 üzerinde çalışır (teqlif-redis-failover.timer)
# node1 Redis'e 3 ardışık erişim başarısız olursa replica → master'a terfi.
# Bir kez promote edilince promoted_flag dosyası kalır; scripti tekrar çalıştırma etkisizdir.
# Failback: sudo bash deploy/scale/V2.1/node2/resources/scripts/redis_failback.sh
set -euo pipefail

source /project/teqlif/config/.env.backup

MASTER_HOST="10.10.0.1"
MASTER_PORT="6379"
PROMOTE_THRESHOLD=3
STATE_DIR="/var/lib/teqlif-redis-failover"
FAIL_FILE="${STATE_DIR}/fail_count"
PROMOTED_FLAG="${STATE_DIR}/promoted"

mkdir -p "$STATE_DIR"

# ── Zaten promote edilmişse sessizce çık ──────────────────────────────────────
if [ -f "$PROMOTED_FLAG" ]; then
    exit 0
fi

# ── Master'a ping ─────────────────────────────────────────────────────────────
if redis-cli -h "$MASTER_HOST" -p "$MASTER_PORT" \
        -a "${CORE_REDIS_PASS}" --no-auth-warning PING 2>/dev/null | grep -q PONG; then
    echo "0" > "$FAIL_FILE"
    exit 0
fi

# ── Erişilemez — sayacı artır ─────────────────────────────────────────────────
current=$(cat "$FAIL_FILE" 2>/dev/null || echo "0")
current=$((current + 1))
echo "$current" > "$FAIL_FILE"
logger -t redis-failover "node1 Redis erişilemez ($current/$PROMOTE_THRESHOLD)"

if [ "$current" -lt "$PROMOTE_THRESHOLD" ]; then
    exit 0
fi

# ── PROMOTE ───────────────────────────────────────────────────────────────────
logger -t redis-failover "Eşik aşıldı — REPLICAOF NO ONE çalıştırılıyor"
redis-cli -h 127.0.0.1 -p 6379 \
    -a "${CORE_REDIS_PASS}" --no-auth-warning \
    REPLICAOF NO ONE

touch "$PROMOTED_FLAG"
logger -t redis-failover "node2 Redis master'a terfi edildi"

# ── VIP: iptables DNAT (port 6379) ───────────────────────────────────────────
# WireGuard'dan gelen 10.10.0.1:6379 paketleri PREROUTING ile 10.10.0.2:6379'a
# yönlendirilir. node2 üzerinden çıkan 10.10.0.1:6379 bağlantıları OUTPUT ile
# 127.0.0.1:6379'a yeniden yönlendirilir.
# NOT: ip addr add 10.10.0.1/32 dev lo KULLANILMAZ — kernel local tablosuna
# 10.10.0.1 ekler ve pg_receivewal (5432)/MinIO (9000) trafiğini wg0 yerine lo'ya
# düşürür; iptables DNAT port 6379 için yeterlidir.
sudo /sbin/iptables -t nat -C PREROUTING \
    -d 10.10.0.1 -p tcp --dport 6379 \
    -j DNAT --to-destination 10.10.0.2:6379 2>/dev/null \
|| sudo /sbin/iptables -t nat -A PREROUTING \
    -d 10.10.0.1 -p tcp --dport 6379 \
    -j DNAT --to-destination 10.10.0.2:6379
sudo /sbin/iptables -t nat -C OUTPUT \
    -d 10.10.0.1 -p tcp --dport 6379 \
    -j DNAT --to-destination 127.0.0.1:6379 2>/dev/null \
|| sudo /sbin/iptables -t nat -A OUTPUT \
    -d 10.10.0.1 -p tcp --dport 6379 \
    -j DNAT --to-destination 127.0.0.1:6379
logger -t redis-failover "iptables DNAT 6379 → 10.10.0.2 (gelen) / 127.0.0.1 (yerel) eklendi"

# ── Telegram bildirimi ────────────────────────────────────────────────────────
export _NODE
_NODE=$(hostname -s)

python3 - <<'PYEOF'
import urllib.request, json, os, sys

token   = os.environ.get('TELEGRAM_BOT_TOKEN', '')
chat_id = os.environ.get('TELEGRAM_CHAT_ID', '')
node    = os.environ.get('_NODE', 'node2')

if not token or not chat_id:
    sys.exit(0)

text = (
    '\U0001f6a8 <b>' + node + '</b> — Redis Otomatik Failover\n'
    'node1 Redis 3 kez erişilemez → node2 master\'a terfi edildi.\n\n'
    '<b>Failback (node1 geri döndüğünde):</b>\n'
    '<code>sudo bash /var/www/teqlif.com/deploy/scale/V2.1/node2/resources/scripts/redis_failback.sh</code>'
)

data = json.dumps({'chat_id': chat_id, 'text': text, 'parse_mode': 'HTML'}).encode()
req  = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/sendMessage',
    data=data,
    headers={'Content-Type': 'application/json'},
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print(f'Telegram gönderilemedi: {e}', file=sys.stderr)
PYEOF

# ── job_ok heartbeat ──────────────────────────────────────────────────────────
# Failover sırasında node1 (10.10.0.1) DOWN olduğundan heartbeat yerel master'a yazılır
redis-cli -h 127.0.0.1 -p 6379 \
    -a "${CORE_REDIS_PASS}" --no-auth-warning \
    HSET teqlif:agent:job_ok redis_failover "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >/dev/null 2>&1 || true
