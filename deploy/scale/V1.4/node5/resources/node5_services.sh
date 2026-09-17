#!/usr/bin/env bash
# deploy/scale/V1.4/node5/resources/node5_services.sh  —  node5 (Core) servis yönetimi
# Kullanım: bash node5_services.sh <start|stop|restart|status>
set -euo pipefail
CMD="${1:-status}"
# Core Node5 servisleri: teqlif (API), teqlif-worker (ARQ), teqlif-worker-critical, exporter'lar ve veritabanları
SERVICES=(teqlif teqlif-worker teqlif-worker-critical node_exporter promtail postgresql clickhouse-server redis-server)

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
