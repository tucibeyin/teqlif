#!/usr/bin/env bash
# deploy/scale/V1.4/node4/resources/node4_services.sh
# node4 (Edge 2) servis yönetimi
set -euo pipefail
CMD="${1:-status}"

# Edge Node4 servisleri: Sadece Medya, Depolama ve Metrik Ajanı. (Postgres, FastAPI YOKTUR)
SERVICES=(livekit minio redis-server edge-metrics-agent node_exporter promtail)

case "$CMD" in
  start|stop|restart)
    for svc in "${SERVICES[@]}"; do 
      sudo systemctl "$CMD" "$svc" 2>/dev/null || echo "Uyarı: $svc servisi bulunamadı veya işlem başarısız oldu, atlanıyor."
    done
    ;;
  status)
    for svc in "${SERVICES[@]}"; do
      printf '%-30s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo 'kurulu değil / kapalı')"
    done
    ;;
  *)
    echo "Kullanım: $0 <start|stop|restart|status>"
    exit 1
    ;;
esac
