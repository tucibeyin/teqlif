#!/bin/bash
# Cloudflare DNS failover daemon
# Gateway down → DNS'i node1'e çevir; gateway geri gelince → gateway'e döndür

CF_ZONE_ID="${CF_ZONE_ID:?CF_ZONE_ID gerekli}"
CF_API_TOKEN="${CF_API_TOKEN:?CF_API_TOKEN gerekli}"

GATEWAY_IP="94.16.105.135"
NODE1_IP="135.125.175.223"
HEALTH_URL="http://${GATEWAY_IP}/cf-health"

CHECK_INTERVAL=10      # saniye
FAIL_THRESHOLD=3       # bu kadar ardışık hata → failover
RECOVER_THRESHOLD=3    # bu kadar ardışık başarı → geri dön

DNS_NAMES=("teqlif.com")

current_target="gateway"
fail_count=0
ok_count=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

get_record_id() {
    curl -sf \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${1}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'])"
}

update_dns() {
    local name="$1" record_id="$2" ip="$3"
    local result
    result=$(curl -sf -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"content\":\"${ip}\"}" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d['success'] else str(d['errors']))")
    log "  ${name} → ${ip}: ${result}"
}

switch_to() {
    local target="$1"
    local ip
    [ "$target" = "node1" ] && ip="$NODE1_IP" || ip="$GATEWAY_IP"
    log "=== SWITCH: ${current_target} → ${target} (${ip}) ==="
    for name in "${DNS_NAMES[@]}"; do
        local rid
        rid=$(get_record_id "$name") || { log "  ${name}: record ID alınamadı"; continue; }
        update_dns "$name" "$rid" "$ip"
    done
    current_target="$target"
}

log "cf-failover başladı. Gateway: ${GATEWAY_IP}, Node1: ${NODE1_IP}"

while true; do
    if curl -sf --max-time 5 "$HEALTH_URL" > /dev/null 2>&1; then
        fail_count=0
        if [ "$current_target" = "node1" ]; then
            ok_count=$((ok_count + 1))
            log "Gateway geri geldi (${ok_count}/${RECOVER_THRESHOLD})"
            if [ "$ok_count" -ge "$RECOVER_THRESHOLD" ]; then
                switch_to "gateway"
                ok_count=0
            fi
        fi
    else
        ok_count=0
        if [ "$current_target" = "gateway" ]; then
            fail_count=$((fail_count + 1))
            log "Gateway erişilemiyor (${fail_count}/${FAIL_THRESHOLD})"
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                switch_to "node1"
                fail_count=0
            fi
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
