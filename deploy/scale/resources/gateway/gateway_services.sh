#!/usr/bin/env bash
# deploy/scale/resources/gateway/services.sh  —  gateway servis yönetimi
# Kullanım: bash services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"
SERVICES=(nginx prometheus loki alertmanager node_exporter promtail)

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
