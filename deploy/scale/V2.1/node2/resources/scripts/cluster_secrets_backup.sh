#!/bin/bash
# cluster_secrets_backup.sh — node1..6 + nodeMonitor + node101 TLS/WG/env sırları
# Zamanlama: her gün 06:20 UTC (teqlif-cluster-secrets-backup.timer)
#
# Kapsam (her node):
#   /etc/ssl/teqlif/           — Cloudflare origin TLS sertifikaları (crt + key)
#   /etc/wireguard/            — WireGuard privatekey + wg0.conf (disaster recovery)
#   /project/teqlif/config/    — .env* uygulama sırları
#
# Kapsam DIŞI (bilinçli):
#   /etc/letsencrypt/          — LE certs 90 günde otomatik yenilenir (certbot)
#   /etc/teqlif-agent/env      — teqlif-agent servis kullanıcısına ait; sırlar .env*'de
#
# Çıktı: /project/teqlif/backups/cluster_secrets/{node}/ — chmod 700
# Offsite: offsite_sync.sh restic'e dahil (AES-256 şifreli node101'e)
#
# İzin gereksinimleri:
#   /etc/ssl/teqlif/*.key      → root:tucibeyin 640 (_common.sh apply_secrets)
#   /etc/wireguard/privatekey  → root:tucibeyin 640 (_common.sh apply_secrets)
#   /etc/wireguard/wg0.conf    → root:tucibeyin 640 (_common.sh apply_secrets)
#   node2 kendisi              → SSH yerine yerel rsync (SSH-to-self yok)

set -euo pipefail

BACKUP_BASE=/project/teqlif/backups/cluster_secrets
LOGFILE=/project/teqlif/logs/cluster_secrets_backup.log
SSH_KEY="/home/tucibeyin/.ssh/id_ed25519_cluster_backup"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10"

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

    if [[ "${node}" == "node2" ]]; then
        # Kendisi — SSH yerine yerel kopya
        [[ -d /etc/ssl/teqlif ]] && \
            rsync -az /etc/ssl/teqlif/ "${dest}/ssl_teqlif/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN node2 ssl rsync başarısız"; }

        [[ -d /etc/wireguard ]] && \
            rsync -az --include 'wg0.conf' --include 'privatekey' --include 'pubkey' --exclude '*' \
                /etc/wireguard/ "${dest}/wireguard/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN node2 wg rsync başarısız"; }

        [[ -d /project/teqlif/config ]] && \
            rsync -az --include '.env*' --exclude '*' \
                /project/teqlif/config/ "${dest}/env/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN node2 env rsync başarısız"; }
    else
        # SSH bağlantı testi — rc=255 bağlantı hatası, rc=1 "dizin yok"
        if ! ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" true 2>/dev/null; then
            echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} SSH bağlantı hatası"
            TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
            continue
        fi

        # TLS (yoksa sessiz geç)
        if ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" "[ -d /etc/ssl/teqlif ]" 2>/dev/null; then
            rsync -az \
                -e "ssh ${SSH_OPTS}" \
                tucibeyin@"${wg_ip}":/etc/ssl/teqlif/ \
                "${dest}/ssl_teqlif/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} ssl rsync başarısız"; }
        fi

        # WireGuard (yoksa sessiz geç)
        if ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" "[ -d /etc/wireguard ]" 2>/dev/null; then
            rsync -az \
                --include 'wg0.conf' --include 'privatekey' --include 'pubkey' --exclude '*' \
                -e "ssh ${SSH_OPTS}" \
                tucibeyin@"${wg_ip}":/etc/wireguard/ \
                "${dest}/wireguard/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} wg rsync başarısız"; }
        fi

        # .env* (yoksa sessiz geç)
        if ssh -q ${SSH_OPTS} tucibeyin@"${wg_ip}" "[ -d /project/teqlif/config ]" 2>/dev/null; then
            rsync -az \
                --include '.env*' --exclude '*' \
                -e "ssh ${SSH_OPTS}" \
                tucibeyin@"${wg_ip}":/project/teqlif/config/ \
                "${dest}/env/" 2>/dev/null \
            || { ok=0; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) cluster_secrets_backup: WARN ${node} env rsync başarısız"; }
        fi
    fi

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

if [[ "${TOTAL_FAIL}" -gt 0 ]]; then
    logger -p user.warning "teqlif cluster_secrets_backup: ${TOTAL_FAIL} node başarısız"
    exit 1
fi

touch "${BACKUP_BASE}/.last_backup_ok"

# job_ok yalnızca başarıda yazılır (TOTAL_FAIL=0 garantili buraya gelindiyse)
source /project/teqlif/config/.env.backup 2>/dev/null || true
redis-cli -h 10.10.0.1 -p 6379 -a "${CORE_REDIS_PASS:-}" --no-auth-warning \
    HSET teqlif:agent:job_ok cluster_secrets_backup "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
logger "teqlif cluster_secrets_backup: tamamlandı ok=${TOTAL_OK}"
