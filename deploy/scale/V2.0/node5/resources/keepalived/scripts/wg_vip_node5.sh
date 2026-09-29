#!/bin/bash
STATE="${1}"
SECRETS_FILE="/etc/keepalived/secrets/failover.env"
[ -f "${SECRETS_FILE}" ] && source "${SECRETS_FILE}"

if [ "$STATE" = "MASTER" ]; then
    if sudo -u postgres psql -h 127.0.0.1 -q -t \
         -c "SELECT pg_is_in_recovery();" 2>/dev/null | grep -q 't'; then
        sudo -u postgres pg_ctl promote -D /var/lib/postgresql/17/main
        sleep 2
    fi
    systemctl enable pgbouncer
    systemctl start pgbouncer
    systemctl start teqlif teqlif-worker teqlif-worker-critical teqlif-guardian
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_ALERTS}" \
        -d "text=*FAILBACK TAMAMLANDI: node6→node5 VIP geri dönüşü* — servisler aktif" \
        -d "parse_mode=Markdown" > /dev/null 2>&1 || true
else
    systemctl stop teqlif teqlif-worker teqlif-worker-critical pgbouncer 2>/dev/null || true
    systemctl disable pgbouncer
fi

logger "wg_vip_node5: STATE=${STATE} completed"
