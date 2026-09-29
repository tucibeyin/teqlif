#!/bin/bash
STATE=$1
SECRETS_FILE="/etc/keepalived/secrets/failover.env"

if [ ! -f "${SECRETS_FILE}" ]; then
    logger "wg_vip_failover: HATA — secrets dosyası bulunamadı"
    exit 1
fi
. "${SECRETS_FILE}"

if [ "$STATE" = "MASTER" ]; then
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
           -i /home/tucibeyin/.ssh/id_ed25519_failover \
           tucibeyin@10.10.0.5 "exit 0" 2>/dev/null; then
        logger "wg_vip_failover: MASTER geçişi iptal — node5 hâlâ erişilebilir"
        exit 1
    fi
    NEW_PRIMARY_PUBKEY="${NODE6_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.7/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE5_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.5/32"
else
    NEW_PRIMARY_PUBKEY="${NODE5_PUBKEY}"
    NEW_PRIMARY_IPS="10.10.0.5/32,10.10.0.10/32,10.10.0.11/32"
    NEW_STANDBY_PUBKEY="${NODE6_PUBKEY}"
    NEW_STANDBY_IPS="10.10.0.7/32"
fi

ALL_WG_IPS="10.10.0.2 10.10.0.9 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.8 10.10.0.12 10.10.0.13"

for WG_IP in ${ALL_WG_IPS}; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i /home/tucibeyin/.ssh/id_ed25519_failover \
        tucibeyin@${WG_IP} \
        "sudo wg set wg0 peer ${NEW_PRIMARY_PUBKEY} allowed-ips ${NEW_PRIMARY_IPS} && \
         sudo wg set wg0 peer ${NEW_STANDBY_PUBKEY} allowed-ips ${NEW_STANDBY_IPS}" \
        2>/dev/null || true &
done
wait

sudo wg set wg0 peer "${NEW_PRIMARY_PUBKEY}" allowed-ips "${NEW_PRIMARY_IPS}"
sudo wg set wg0 peer "${NEW_STANDBY_PUBKEY}" allowed-ips "${NEW_STANDBY_IPS}"

if [ "$STATE" = "MASTER" ]; then
    redis-cli -p 6379 -a "${CORE_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-core.conf
    redis-cli -p 6380 -a "${ORCH_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-orch.conf
    redis-cli -p 6382 -a "${GUARDIAN_REDIS_PASS}" REPLICAOF NO ONE 2>/dev/null || true
    sed -i '/^replicaof /d' /etc/redis/redis-guardian.conf

    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2
    fi

    sudo -u postgres psql -c \
      "SELECT pg_create_physical_replication_slot('wal_backup_node9') \
       WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='wal_backup_node9');" \
      2>/dev/null || true

    systemctl enable pgbouncer
    systemctl start pgbouncer
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian

    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} "sudo wg-quick save wg0" 2>/dev/null || true &
    done
    wait
    wg-quick save wg0

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILOVER TAMAMLANDI: node5→node6 VIP geçişi*" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true
else
    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} \
            "sudo wg set wg0 peer ${NEW_PRIMARY_PUBKEY} allowed-ips ${NEW_PRIMARY_IPS} && \
             sudo wg set wg0 peer ${NEW_STANDBY_PUBKEY} allowed-ips ${NEW_STANDBY_IPS}" \
            2>/dev/null || true &
    done
    wait

    sudo wg set wg0 peer "${NEW_PRIMARY_PUBKEY}" allowed-ips "${NEW_PRIMARY_IPS}"
    sudo wg set wg0 peer "${NEW_STANDBY_PUBKEY}" allowed-ips "${NEW_STANDBY_IPS}"

    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
    systemctl disable pgbouncer

    grep -q '^replicaof' /etc/redis/redis-core.conf    || echo "replicaof 10.10.0.11 6379" >> /etc/redis/redis-core.conf
    grep -q '^replicaof' /etc/redis/redis-orch.conf    || echo "replicaof 10.10.0.11 6380" >> /etc/redis/redis-orch.conf
    grep -q '^replicaof' /etc/redis/redis-guardian.conf || echo "replicaof 10.10.0.5 6382" >> /etc/redis/redis-guardian.conf
    systemctl restart redis-core redis-orch redis-guardian

    for WG_IP in ${ALL_WG_IPS}; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -i /home/tucibeyin/.ssh/id_ed25519_failover \
            tucibeyin@${WG_IP} "sudo wg-quick save wg0" 2>/dev/null || true &
    done
    wait
    wg-quick save wg0
fi

logger "wg_vip_failover: STATE=${STATE} completed"
