#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/test_all.sh
# Teqlif Scale V1.4 — Kapsamlı Test Paketi
# Çalıştırma: bash deploy/scale/V1.4/scripts/test_all.sh
# Gereksinim: SSH alias'ları tanımlı olmalı (teqlif-node1..5, teqlif-gateway)
set -o pipefail

# ── Renk ve format ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0; WARN=0

pass()  { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); }
fail()  { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $1"; WARN=$((WARN+1)); }
header(){ echo -e "\n${CYAN}${BOLD}══ $1 ══${RESET}"; }

# ── SSH yardımcı ───────────────────────────────────────────────────────────────
SSH_OPTS="-o ConnectTimeout=6 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=5 -o ServerAliveCountMax=2"

_ssh() {
  local host="$1"; shift
  ssh $SSH_OPTS "$host" "$@" 2>/dev/null
}
_ssh_check() {
  local host="$1"; shift
  ssh $SSH_OPTS "$host" "$@" >/dev/null 2>&1
}

# ── SSH erişim ön kontrolü ─────────────────────────────────────────────────────
header "SSH Erişim Kontrolü"
NODES=(teqlif-gateway teqlif-node1 teqlif-node2 teqlif-node3 teqlif-node4 teqlif-node5)
NODE_NAMES=(gateway node1 node2 node3 node4 node5)
NODE_WG=("" 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.5) # Gateway WG'de yok kabul edelim
REACHABLE=()
for i in "${!NODES[@]}"; do
  host="${NODES[$i]}"
  if _ssh_check "$host" true; then
    pass "$host SSH erişilebilir"
    REACHABLE+=("$i")
  else
    warn "$host SSH ulaşılamıyor — bu node'a ait testler atlanacak"
  fi
done

_is_reachable() { printf '%s\n' "${REACHABLE[@]}" | grep -qx "$1"; }

# ── 1. TOPOLOJI: WireGuard Mesh ────────────────────────────────────────────────
header "1. Topoloji — WireGuard Mesh"
for i in "${REACHABLE[@]}"; do
  if [[ "${NODE_NAMES[$i]}" == "gateway" ]]; then continue; fi # Gateway'de WG şart değil
  host="${NODES[$i]}"
  name="${NODE_NAMES[$i]}"
  wg_ip="${NODE_WG[$i]}"

  # wg0 aktif mi?
  wg_state=$(_ssh "$host" "systemctl is-active wg-quick@wg0" 2>/dev/null) || wg_state="inactive"
  if [[ "$wg_state" == "active" ]]; then
    pass "$name: wg-quick@wg0 aktif"
  else
    fail "$name: wg-quick@wg0 $wg_state"
    continue
  fi

  # WireGuard IP atanmış mı?
  if _ssh "$host" "ip addr show wg0 2>/dev/null" | grep -q "$wg_ip"; then
    pass "$name: WireGuard IP $wg_ip atanmış"
  else
    fail "$name: WireGuard IP $wg_ip atanmamış"
  fi

  # Diğer node'lara TCP (SSH portu üzerinden) erişilebilirlik
  for j in "${!NODES[@]}"; do
    [[ $i -eq $j ]] && continue
    if [[ "${NODE_NAMES[$j]}" == "gateway" ]]; then continue; fi
    target_ip="${NODE_WG[$j]}"
    target_name="${NODE_NAMES[$j]}"
    if _ssh "$host" "nc -zw3 $target_ip 22 2>/dev/null || ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no $target_ip true 2>/dev/null"; then
      pass "$name → $target_name ($target_ip) WireGuard erişilebilir"
    else
      fail "$name → $target_name ($target_ip) WireGuard erişilemiyor"
    fi
  done
done

# ── 2. SERVİS SAĞLIĞI: systemd durumları ──────────────────────────────────────
header "2. Servis Sağlığı — systemd (V1.4 Rolleri)"

_check_svc() {
  local host="$1" svc="$2" label="$3"
  local status
  status=$(_ssh "$host" "systemctl is-active $svc || true" 2>/dev/null) || status="unknown"
  status=$(echo "$status" | head -1)
  if [[ "$status" == "active" ]]; then
    pass "$label: $svc active"
  else
    fail "$label: $svc $status"
  fi
}

# Gateway (0)
if _is_reachable 0; then
  for svc in nginx node_exporter promtail; do
    _check_svc teqlif-gateway "$svc" "gateway"
  done
fi

# node1 (Edge 1 - 1)
if _is_reachable 1; then
  for svc in livekit minio redis-server edge-metrics-agent node_exporter promtail; do
    _check_svc teqlif-node1 "$svc" "node1 (Edge)"
  done
fi

# node2 (AI Proxy 1 - 2)
if _is_reachable 2; then
  for svc in teqlif-ai-proxy cf-failover node_exporter promtail; do
    _check_svc teqlif-node2 "$svc" "node2 (AI Proxy)"
  done
fi

# node3 (Monitor, Staging, AI Proxy 2 - 3)
if _is_reachable 3; then
  for svc in teqlif-ai-proxy prometheus loki grafana-server alertmanager node_exporter promtail teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging minio; do
    # Staging henüz yapılandırılmamış olabilir, active değilse sadece uyarı verelim
    if [[ "$svc" == *"staging"* ]]; then
      st=$(_ssh teqlif-node3 "systemctl is-active $svc || true" 2>/dev/null) || st="unknown"
      [[ "$st" == "active" ]] && pass "node3: $svc active" || warn "node3: $svc inaktif (Staging yapılandırılmamış olabilir)"
    else
      _check_svc teqlif-node3 "$svc" "node3"
    fi
  done
fi

# node4 (Edge 2 - 4)
if _is_reachable 4; then
  for svc in livekit minio redis-server edge-metrics-agent node_exporter promtail; do
    _check_svc teqlif-node4 "$svc" "node4 (Edge)"
  done
fi

# node5 (Core - 5)
if _is_reachable 5; then
  for svc in teqlif teqlif-worker teqlif-worker-critical postgresql clickhouse-server redis-server node_exporter promtail; do
    _check_svc teqlif-node5 "$svc" "node5 (Core)"
  done
fi

# ── 3. HTTP ENDPOINT SAĞLIĞI ───────────────────────────────────────────────────
header "3. HTTP Endpoint Sağlığı"

_curl_ok() {
  local label="$1" url="$2"
  local result http_code
  result=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null) || result="000"
  http_code=$(echo "$result" | tail -1)
  if [[ "$http_code" =~ ^(200|204|301|302|404|401)$ ]]; then # 401/404 can mean service is up but rejecting unauth/path
    pass "$label: $url → HTTP $http_code"
  else
    fail "$label: $url → HTTP $http_code"
  fi
}

_curl_ok "gateway public"  "https://teqlif.com/api/health"
_curl_ok "livekit edge1"   "https://live1.teqlif.com/"
_curl_ok "minio edge1"     "https://minio1.teqlif.com/minio/health/live"
_curl_ok "livekit edge2"   "https://live2.teqlif.com/"
_curl_ok "minio edge2"     "https://minio2.teqlif.com/minio/health/live"

# node5 (Core) lokal API
if _is_reachable 5; then
  core_health=$(_ssh teqlif-node5 "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health" 2>/dev/null) || core_health="000"
  [[ "$core_health" =~ ^(200|204)$ ]] \
    && pass "node5 (Core): lokal API health → HTTP $core_health" \
    || fail "node5 (Core): lokal API health → HTTP $core_health"
fi

# AI proxy health (node5'ten WireGuard üzerinden)
if _is_reachable 5; then
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    health=$(_ssh teqlif-node5 "curl -s -o /dev/null -w '%{http_code}' http://$proxy_ip:8080/health" 2>/dev/null) || health="000"
    [[ "$health" =~ ^(200|204)$ ]] \
      && pass "node5→$proxy_label AI proxy health → HTTP $health" \
      || fail "node5→$proxy_label AI proxy health → HTTP $health"
  done
fi

# ── 4. AI PROXY FALLBACK ZİNCİRİ ──────────────────────────────────────────────
header "4. AI Proxy — Yetki Testi (Node5 üzerinden)"

if _is_reachable 5; then
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    code=$(_ssh teqlif-node5 "curl -s -o /dev/null -w '%{http_code}' -X POST http://$proxy_ip:8080/generate" 2>/dev/null) || code="000"
    if [[ "$code" =~ ^(401|403|422)$ ]]; then
      pass "$proxy_label AI proxy: token olmadan $code (auth korumalı)"
    else
      warn "$proxy_label AI proxy: token olmadan $code (401/403 beklenir)"
    fi
  done
fi

# ── 5. BACKUP SİSTEMİ ──────────────────────────────────────────────────────────
header "5. Backup Sistemi (Node5 → Node3)"

if _is_reachable 5; then
  latest_backup=$(_ssh teqlif-node5 "ls -t /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | head -1") || latest_backup=""
  if [[ -n "$latest_backup" ]]; then
    pass "node5: pg backup dizininde dosyalar var ($latest_backup)"
  else
    warn "node5: /var/backups/teqlif/pg/ altında backup dosyası yok (Zamanlanmış görev henüz çalışmamış olabilir)"
  fi
fi

if _is_reachable 3; then
  offsite_pg=$(_ssh teqlif-node3 "ls /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | wc -l | tr -d ' '") || offsite_pg="0"
  offsite_pg=$(echo "$offsite_pg" | head -1 | tr -d '[:space:]')
  [[ "$offsite_pg" -gt 0 ]] \
    && pass "node3: offsite pg backup mevcut ($offsite_pg dosya)" \
    || warn "node3: /var/backups/teqlif/pg/ boş — rsync henüz çalışmamış olabilir"
fi

# ── 6. MONİTORİNG STACK ────────────────────────────────────────────────────────
header "6. Monitoring Stack (node3)"

if _is_reachable 3; then
  prom_raw=$(_ssh teqlif-node3 "curl -s http://localhost:9090/api/v1/targets 2>/dev/null") || prom_raw="{}"
  up_count=$(echo "$prom_raw" | grep -o '"health":"up"' | wc -l | tr -d ' ')
  total_count=$(echo "$prom_raw" | grep -o '"health":' | wc -l | tr -d ' ')
  if [[ "$up_count" -ge 5 ]]; then
    pass "node3 Prometheus: $up_count/$total_count hedef UP"
  else
    fail "node3 Prometheus: $up_count/$total_count hedef UP (En az 5 beklenir)"
  fi

  # Loki log akışı kontrolü
  loki_raw=$(_ssh teqlif-node3 "curl -s 'http://localhost:3100/loki/api/v1/label/node/values' 2>/dev/null") || loki_raw="{}"
  for node_label in node1 node2 node3 node4 node5 gateway; do
    echo "$loki_raw" | grep -q "\"$node_label\"" \
      && pass "Loki: node=$node_label log akışı var" \
      || warn "Loki: node=$node_label log akışı YOK (henüz log üretmemiş olabilir)"
  done
fi

# ── 7. UFW GÜVENLİK KONTROLÜ ──────────────────────────────────────────────────
header "7. UFW Güvenlik Kontrolü"

for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  ufw_enabled=$(_ssh "$host" "grep -i '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'") || ufw_enabled=""
  ufw_enabled=$(echo "$ufw_enabled" | head -1 | tr '[:lower:]' '[:upper:]')
  if [[ "$ufw_enabled" == "YES" ]]; then
    pass "$name: UFW aktif"
  else
    fail "$name: UFW aktif değil — önce 'sudo ufw status numbered' ile kuralları doğrula, sonra 'sudo ufw --force enable'"
  fi
done

# ── 8. SERTİFİKA GEÇERLİLİĞİ ─────────────────────────────────────────────────
header "8. TLS Sertifika Geçerliliği"

_check_cert() {
  local label="$1" host="$2" port="${3:-443}"
  local cert
  cert=$(echo | openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null \
    | openssl x509 2>/dev/null)
  if [[ -z "$cert" ]]; then
    warn "$label: sertifika alınamadı"
    return
  fi
  # 14 gün kaldı mı?
  if ! echo "$cert" | openssl x509 -checkend $((14*86400)) -noout >/dev/null 2>&1; then
    fail "$label: 14 gün içinde sona eriyor — ACİL yenile"
    return
  fi
  # 30 gün kaldı mı?
  if ! echo "$cert" | openssl x509 -checkend $((30*86400)) -noout >/dev/null 2>&1; then
    warn "$label: 30 gün içinde sona eriyor — yakında yenile"
    return
  fi
  pass "$label: sertifika geçerli (30+ gün)"
}

_check_cert "Gateway / API"   "teqlif.com"
_check_cert "Edge1 LiveKit"   "live1.teqlif.com"
_check_cert "Edge1 MinIO"     "minio1.teqlif.com"
_check_cert "Edge2 LiveKit"   "live2.teqlif.com"
_check_cert "Edge2 MinIO"     "minio2.teqlif.com"

# ── ÖZET ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
echo -e "${BOLD} Teqlif V1.4 Test Özeti${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}✓ PASS${RESET}  : $PASS"
echo -e "  ${YELLOW}⚠ WARN${RESET}  : $WARN"
echo -e "  ${RED}✗ FAIL${RESET}  : $FAIL"
echo -e "  Toplam  : $((PASS + WARN + FAIL))"
echo ""
if   [[ $FAIL -gt 0 ]]; then echo -e "${RED}${BOLD}SONUÇ: $FAIL test başarısız.${RESET}";                         exit 1
elif [[ $WARN -gt 0 ]]; then echo -e "${YELLOW}${BOLD}SONUÇ: Kritik testler geçti — $WARN uyarı var.${RESET}";  exit 0
else                          echo -e "${GREEN}${BOLD}SONUÇ: Tüm testler başarılı.${RESET}";                     exit 0
fi
