#!/usr/bin/env bash
# deploy/scale/resources/node1_services.sh
# Kullanım: bash node1_services.sh [start|stop|restart|status]
set -euo pipefail

ACTION="${1:-status}"

CORE=(teqlif teqlif-staging teqlif-worker teqlif-worker-critical)
OBS=(node_exporter promtail)
ALL=("${CORE[@]}" "${OBS[@]}")

case "$ACTION" in
  start)
    echo "==> node1 servisleri başlatılıyor..."
    sudo systemctl start "${ALL[@]}"
    sudo systemctl start redis-backup.timer
    echo "Tamam."
    ;;
  stop)
    echo "==> node1 servisleri durduruluyor..."
    sudo systemctl stop "${CORE[@]}"
    echo "Not: node_exporter ve promtail durdurulmadı (monitoring devam ediyor)."
    ;;
  restart)
    echo "==> node1 servisleri yeniden başlatılıyor..."
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
