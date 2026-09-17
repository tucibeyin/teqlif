#!/usr/bin/env bash
# deploy/scale/V1.4/node3/resources/node3_services.sh
set -euo pipefail
CMD="${1:-status}"
# Node3: Monitor (Prometheus, Loki, Grafana, Alertmanager), Staging (API, MinIO, Worker), ve AI Proxy 2
SERVICES=(teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging minio teqlif-ai-proxy prometheus loki grafana-server alertmanager node_exporter promtail)
case "$CMD" in
  start|stop|restart)
    for svc in "${SERVICES[@]}"; do sudo systemctl "$CMD" "$svc" 2>/dev/null || true; done
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
