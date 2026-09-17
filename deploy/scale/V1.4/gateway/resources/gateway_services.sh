#!/usr/bin/env bash
# deploy/scale/V1.4/gateway/resources/gateway_services.sh
# gateway servis yönetimi
set -euo pipefail
CMD="${1:-status}"

SERVICES=(nginx node_exporter promtail)

case "$CMD" in
  start|stop|restart)
    for svc in "${SERVICES[@]}"; do 
      sudo systemctl "$CMD" "$svc" 2>/dev/null || echo "Uyarı: $svc servisi başarısız."
    done
    ;;
  status)
    for svc in "${SERVICES[@]}"; do
      printf '%-30s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'kurulu değil')"
    done
    ;;
  *)
    echo "Kullanım: $0 <start|stop|restart|status>"
    exit 1
    ;;
esac
