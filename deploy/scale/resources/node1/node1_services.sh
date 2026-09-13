#!/usr/bin/env bash
# deploy/scale/resources/node1/services.sh  —  node1 servis yönetimi
# Kullanım: bash services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"
SERVICES=(teqlif teqlif-worker teqlif-worker-critical node_exporter promtail nginx)

case "$CMD" in
  start|stop|restart)
    [[ "$CMD" != "stop" ]] && sudo ln -sf /var/www/teqlif.com/deploy/scale/V1.3/scripts/teqlif-restart.sh /usr/local/sbin/teqlif-restart
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
