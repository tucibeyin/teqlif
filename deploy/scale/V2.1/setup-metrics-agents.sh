#!/usr/bin/env bash
# Edge Metrics Agent — Tüm Node Kurulum Scripti
# Çalıştırma: bash deploy/scale/V2.1/setup-metrics-agents.sh
# Gereksinim:  deploy/scale/V2.1/secrets.env gerçek değerlere sahip olmalı

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="$SCRIPT_DIR/secrets.env"

if [ ! -f "$SECRETS" ]; then
  echo "HATA: $SECRETS bulunamadı."
  exit 1
fi

source "$SECRETS"

echo "=== Edge Metrics Agent Kurulumu başlıyor ==="

# ── node1 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node1 (api,storage)"
ssh node1 bash << EOFN1
set -e
# .env.production'a yeni vars ekle (idempotent)
grep -q "CORE_REDIS_URL" /project/teqlif/config/.env.production || \
  echo "CORE_REDIS_URL=redis://:${core_redis_pass}@127.0.0.1:6379/0" >> /project/teqlif/config/.env.production

grep -q "EDGE_NODE_TYPE" /project/teqlif/config/.env.production || \
  printf '\nEDGE_NODE_TYPE=api,storage\nNODE_SERVICES=postgres,minio,redis\nEDGE_MINIO_URL=http://10.10.0.1:9000\nEDGE_NODE_REGION=eu-west\nEDGE_LIVEKIT_URLS=wss://live2.teqlif.com,wss://live1.teqlif.com\n' \
    >> /project/teqlif/config/.env.production

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node1 metrics: RUNNING"

# AlertManager için teqlif servisini de restart et
sudo systemctl restart teqlif.service
sleep 3
sudo systemctl is-active teqlif.service && echo "node1 teqlif: RUNNING"
EOFN1

# ── node2 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node2 (backup)"
ssh node2 bash << EOFN2
set -e
sudo mkdir -p /project/teqlif/config
sudo tee /project/teqlif/config/.env.metrics-agent > /dev/null << 'ENV'
CORE_REDIS_URL=redis://:${core_redis_pass}@10.10.0.1:6379/0
EDGE_NODE_ID=node2
EDGE_NODE_TYPE=backup
NODE_SERVICES=minio_backup,redis_backup,pg_backup,clickhouse
EDGE_NODE_REGION=eu-central
DISK_PATH=/
CLICKHOUSE_HOST=127.0.0.1
CLICKHOUSE_PORT=8123
EDGE_METRICS_INTERVAL_SEC=10
ENV
sudo chmod 600 /project/teqlif/config/.env.metrics-agent

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node2 metrics: RUNNING"
EOFN2

# ── node3 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node3 (media/livekit EU-1)"
ssh node3 bash << EOFN3
set -e
cat > /project/teqlif/config/.env.metrics-agent << 'ENV'
CORE_REDIS_URL=redis://:${core_redis_pass}@10.10.0.1:6379/0
EDGE_NODE_ID=node3
EDGE_NODE_TYPE=media
NODE_SERVICES=livekit
EDGE_LIVEKIT_URL=wss://live2.teqlif.com
EDGE_NODE_REGION=eu-central
DISK_PATH=/
LIVEKIT_API_KEY=${livekit_api_key}
LIVEKIT_API_SECRET=${livekit_api_secret}
EDGE_METRICS_INTERVAL_SEC=5
ENV
chmod 600 /project/teqlif/config/.env.metrics-agent

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node3 metrics: RUNNING"
EOFN3

# ── node4 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node4 (media/livekit EU-2)"
ssh node4 bash << EOFN4
set -e
cat > /project/teqlif/config/.env.metrics-agent << 'ENV'
CORE_REDIS_URL=redis://:${core_redis_pass}@10.10.0.1:6379/0
EDGE_NODE_ID=node4
EDGE_NODE_TYPE=media
NODE_SERVICES=livekit
EDGE_LIVEKIT_URL=wss://live1.teqlif.com
EDGE_NODE_REGION=eu-central
DISK_PATH=/
LIVEKIT_API_KEY=${livekit_api_key}
LIVEKIT_API_SECRET=${livekit_api_secret}
EDGE_METRICS_INTERVAL_SEC=5
ENV
chmod 600 /project/teqlif/config/.env.metrics-agent

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node4 metrics: RUNNING"
EOFN4

# ── node5 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node5 (ai-secondary/staging)"
ssh node5 bash << EOFN5
set -e
cat > /project/teqlif/config/.env.metrics-agent << 'ENV'
CORE_REDIS_URL=redis://:${core_redis_pass}@10.10.0.1:6379/0
EDGE_NODE_ID=node5
EDGE_NODE_TYPE=ai,staging
NODE_SERVICES=ai_proxy
EDGE_AI_PROXY_URL=http://10.10.0.5:8001
EDGE_NODE_REGION=eu-west
DISK_PATH=/
EDGE_METRICS_INTERVAL_SEC=10
ENV
chmod 600 /project/teqlif/config/.env.metrics-agent

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node5 metrics: RUNNING"
EOFN5

# ── node6 ─────────────────────────────────────────────────────────────────
echo ""
echo ">>> node6 (ai-primary)"
ssh node6 bash << EOFN6
set -e
sudo mkdir -p /project/teqlif/config
cat > /tmp/.env.ma.n6 << 'ENV'
CORE_REDIS_URL=redis://:${core_redis_pass}@10.10.0.1:6379/0
EDGE_NODE_ID=node6
EDGE_NODE_TYPE=ai
NODE_SERVICES=ai_proxy
EDGE_AI_PROXY_URL=http://10.10.0.6:8001
EDGE_NODE_REGION=us-east
DISK_PATH=/
EDGE_METRICS_INTERVAL_SEC=10
ENV
sudo mv /tmp/.env.ma.n6 /project/teqlif/config/.env.metrics-agent
sudo chmod 600 /project/teqlif/config/.env.metrics-agent
sudo chown tucibeyin:tucibeyin /project/teqlif/config/.env.metrics-agent

sudo systemctl enable --now teqlif-metrics-agent 2>/dev/null || sudo systemctl restart teqlif-metrics-agent
sleep 2
sudo systemctl is-active teqlif-metrics-agent && echo "node6 metrics: RUNNING"
EOFN6

echo ""
echo "=== Kurulum tamamlandı ==="
echo ""
echo "Redis'te metrik kontrolü (node1 üzerinden):"
echo "  ssh node1 \"redis-cli -a '...' keys 'edge:metrics:*'\""
