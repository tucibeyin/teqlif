#!/bin/bash
# cluster_secrets_backup.sh — node1..6 + nodeMonitor + node101 TLS/env sırları
# Zamanlama: her gün 06:20 UTC (teqlif-cluster-secrets-backup.timer)
#
# Kapsam (her node):
#   /etc/ssl/teqlif/           — Cloudflare origin TLS sertifikaları (crt + key)
#   /project/teqlif/config/    — .env* uygulama sırları
#
# Çıktı: /project/teqlif/backups/cluster_secrets/{node}/ — chmod 700
# Offsite: offsite_sync.sh restic'e dahil (AES-256 şifreli node101'e)
#
# Ön koşul: node2'de ~/.ssh/id_ed25519_cluster_backup oluşturulmuş olmalı
#   ve her node'un authorized_keys dosyasına şu satır eklenmiş olmalı:
#   from="10.10.0.2" <id_ed25519_cluster_backup.pub içeriği>
#   (Bootstrap adımı: deploy/scale/V2.1/scripts/bootstrap_node2.sh print_summary)

set -euo pipefail

BACKUP_BASE=/project/teqlif/backups/cluster_secrets
LOGFILE=/project/teqlif/logs/cluster_secrets_backup.log
SSH_KEY="/home/tucibeyin/.ssh/id_ed25519_cluster_backup"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10"

# node: "hostname wg_ip" çiftleri
declare -A NODES=(
    [node1]="10.10.0.1"
    [node2]="10.10.0.2"
    [node3]="10.10.0.3"
    [node4]="10.10.0.4"
    [node5]="10.10.0.5"
    [node6]="10.10.0.6"
    [nodeMonitor]="10.10.0.99"
    [node101]="10.10.0.101"
)

install -d "$(dirname "${LOGFILE}")"
exec >> "${LOGFILE}" 2>&1
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: start"

TOTAL_OK=0
TOTAL_FAIL=0

for node in "${!NODES[@]}"; do
    wg_ip="${NODES[$node]}"
    dest="${BACKUP_BASE}/${node}"
    install -d "${dest}"
    chmod 700 "${dest}"

    ok=1

    # TLS sertifikaları (yoksa sessiz geç)
    if ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" "[ -d /etc/ssl/teqlif ]" 2>/dev/null; then
        rsync -az \
            -e "ssh ${SSH_OPTS}" \
            tucibeyin@"${wg_ip}":/etc/ssl/teqlif/ \
            "${dest}/ssl_teqlif/" 2>/dev/null || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} ssl rsync başarısız"; }
    fi

    # .env* uygulama sırları (yoksa sessiz geç)
    if ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" "[ -d /project/teqlif/config ]" 2>/dev/null; then
        rsync -az \
            --include '.env*' \
            --exclude '*' \
            -e "ssh ${SSH_OPTS}" \
            tucibeyin@"${wg_ip}":/project/teqlif/config/ \
            "${dest}/env/" 2>/dev/null || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} env rsync başarısız"; }
    fi

    # Dizin izinlerini 700 olarak koru
    chmod -R go-rwx "${dest}" 2>/dev/null || true

    if [[ "${ok}" -eq 1 ]]; then
        TOTAL_OK=$(( TOTAL_OK + 1 ))
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: ${node} OK"
    else
        TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
    fi
done

USED=$(du -sh "${BACKUP_BASE}" 2>/dev/null | cut -f1 || echo "?")
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: tamamlandı ok=${TOTAL_OK} fail=${TOTAL_FAIL} boyut=${USED}"

source /project/teqlif/config/.env.backup 2>/dev/null || true
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok cluster_secrets_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

if [[ "${TOTAL_FAIL}" -gt 0 ]]; then
    logger -p user.warning "teqlif cluster_secrets_backup: ${TOTAL_FAIL} node başarısız"
    exit 1
fi

touch "${BACKUP_BASE}/.last_backup_ok"
logger "teqlif cluster_secrets_backup: tamamlandı ok=${TOTAL_OK}"
