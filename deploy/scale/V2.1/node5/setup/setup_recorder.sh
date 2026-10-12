#!/usr/bin/env bash
# node5 — Recording için Python paket kurulumu
# Çalıştır: sudo bash deploy/scale/V2.1/node5/setup/setup_recorder.sh
set -euo pipefail

VENV="/opt/teqlif-agent/venv/bin/pip"

echo "=== Agent venv'e kayıt paketleri kuruluyor ==="
$VENV install --quiet "aiortc>=1.9.0" "livekit-api>=1.2.0"

echo "Kurulu versiyonlar:"
/opt/teqlif-agent/venv/bin/pip show aiortc livekit-api 2>/dev/null | grep -E 'Name|Version'

echo ""
echo "=== Sonraki adımlar ==="
echo "1. /etc/teqlif-agent/env dosyasına ekle:"
echo "   (zaten LIVEKIT_API_KEY ve LIVEKIT_API_SECRET var — başka bir şey gerekmez)"
echo ""
echo "2. cluster.yaml'da livekit_ws_url doğru ayarlı:"
echo "   teqlif-livekit-staging → ws://127.0.0.1:7890"
echo "   teqlif-livekit         → ws://127.0.0.1:7880"
echo ""
echo "3. sudo teqlif-restart"
