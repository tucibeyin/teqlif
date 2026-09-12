#!/usr/bin/env bash
# deploy/scale/resources/node2/services.sh  —  node2 servis yönetimi
# Kullanım: bash services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"
SERVICES=(teqlif-ai-proxy cf-failover node_exporter promtail)

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
      printf '%-30s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'unknown')"
    done
    ;;
  *)
    echo "Kullanim: $0 <start|stop|restart|status>"
    exit 1
    ;;
esac
