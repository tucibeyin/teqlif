#!/bin/bash
# teqlif-backup-failed@<unit>.service tarafından çağrılır.
# $1: başarısız unit adı (örn. teqlif-pg-dump.service)
set -euo pipefail

source /project/teqlif/config/.env.backup

export NOTIFY_UNIT="${1:-bilinmeyen}"
export NOTIFY_NODE
NOTIFY_NODE=$(hostname -s)
export NOTIFY_TS
NOTIFY_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
export NOTIFY_LOG
NOTIFY_LOG=$(journalctl -u "${NOTIFY_UNIT}" -n 5 --no-pager --output=short-iso 2>/dev/null || echo "(log alınamadı)")

python3 - <<'PYEOF'
import urllib.request, json, sys, os

token = os.environ.get('TELEGRAM_BOT_TOKEN', '')
chat_id = os.environ.get('TELEGRAM_CHAT_ID', '')
if not token or not chat_id:
    sys.exit(0)

unit = os.environ['NOTIFY_UNIT']
node = os.environ['NOTIFY_NODE']
ts   = os.environ['NOTIFY_TS']
log  = os.environ['NOTIFY_LOG']

text = (
    f'\U0001f6a8 <b>{node}</b> — Backup başarısız\n'
    f'<code>{unit}</code>\n'
    f'{ts}\n\n'
    f'<pre>{log}</pre>'
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
    print(f'telegram notify failed: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF
