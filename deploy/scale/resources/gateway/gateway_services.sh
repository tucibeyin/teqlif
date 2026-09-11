#!/usr/bin/env bash
# deploy/scale/resources/gateway/services.sh  —  gateway servis yönetimi
# Kullanım: bash services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"
SERVICES=(nginx node_exporter promtail)  # Scale V1.3: prometheus/loki/alertmanager node3'e taşındı

case "$CMD" in
  start|stop|restart)
    for svc in "${SERVICES[@]}"; do sudo systemctl "$CMD" "$svc"; done
    ;;
  status)
    for svc in "${SERVICES[@]}"; do
      printf '%-30s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'unknown')"
    done
    ;;
  *)
    echo "Kullanim: $0 <start|stop|restart|status>"
    exit 1
    ;;
esac
