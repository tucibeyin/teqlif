#!/usr/bin/env bash
# deploy/scale/resources/gateway_services.sh
# Kullanım: bash gateway_services.sh [start|stop|restart|status]
set -euo pipefail

ACTION="${1:-status}"

CORE=(nginx)
OBS=(prometheus alertmanager loki promtail node_exporter)
ALL=("${CORE[@]}" "${OBS[@]}")

case "$ACTION" in
  start)
    echo "==> gateway servisleri başlatılıyor..."
    sudo systemctl start "${ALL[@]}"
    echo "Tamam."
    ;;
  stop)
    echo "==> gateway servisleri durduruluyor..."
    sudo systemctl stop "${CORE[@]}"
    echo "Not: prometheus, loki, alertmanager, promtail, node_exporter durdurulmadı."
    ;;
  restart)
    echo "==> gateway servisleri yeniden başlatılıyor..."
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
