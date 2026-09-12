#!/usr/bin/env bash
# deploy/scale/resources/node3/node3_services.sh — node3 servis yönetimi
# Kullanım: bash node3_services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"

# Tüm node3 servisleri — başlatma sırası önemli
SERVICES=(
  # Depolama katmanı (staging bağımlı)
  postgresql
  redis-server
  minio
  # Uygulama katmanı
  teqlif-staging
  teqlif-worker-staging
  teqlif-worker-critical-staging
  # AI proxy
  teqlif-ai-proxy
  # nginx (uploads-staging.teqlif.com)
  nginx
  # Monitoring stack
  prometheus
  loki
  alertmanager
  # Metrik toplama
  node_exporter
  promtail
)

case "$CMD" in
  start|restart)
    sudo mkdir -p /var/lib/promtail && sudo chown tucibeyin:tucibeyin /var/lib/promtail
    for svc in "${SERVICES[@]}"; do sudo systemctl "$CMD" "$svc"; done
    ;;
  stop)
    for svc in "${SERVICES[@]}"; do sudo systemctl stop "$svc"; done
    ;;
  status)
    for svc in "${SERVICES[@]}"; do
      printf '%-45s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'unknown')"
    done
    ;;
  *)
    echo "Kullanim: $0 <start|stop|restart|status>"
    exit 1
    ;;
esac
