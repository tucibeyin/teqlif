#!/usr/bin/env bash
# deploy/scale/resources/node2_services.sh
# Kullanım: bash node2_services.sh [start|stop|restart|status]
set -euo pipefail

ACTION="${1:-status}"

CORE=(teqlif-ai-proxy cf-failover)
OBS=(node_exporter promtail)
ALL=("${CORE[@]}" "${OBS[@]}")

case "$ACTION" in
  start)
    echo "==> node2 servisleri başlatılıyor..."
    sudo systemctl start "${ALL[@]}"
    echo "Tamam."
    ;;
  stop)
    echo "==> node2 servisleri durduruluyor..."
    sudo systemctl stop "${CORE[@]}"
    echo "Not: node_exporter ve promtail durdurulmadı (monitoring devam ediyor)."
    ;;
  restart)
    echo "==> node2 servisleri yeniden başlatılıyor..."
    sudo systemctl restart "${ALL[@]}"
    echo "Tamam."
    ;;
  status)
    sudo systemctl status "${ALL[@]}" --no-pager -l 2>/dev/null || true
    ;;
  *)
    echo "Kullanım: $0 [start|stop|restart|status]"
    exit 1
    ;;
esac
