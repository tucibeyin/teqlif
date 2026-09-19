#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/test_all.sh
# Teqlif Scale V1.4 — Kapsamlı Sistem & Güvenlik Test Paketi
#
# Kullanım:
#   Geliştirici makinesi : bash deploy/scale/V1.4/scripts/test_all.sh
#   Mesh node üzerinden  : bash deploy/scale/V1.4/scripts/test_all.sh
#
# Geliştirici makinesi: ~/.ssh/config'deki teqlif-* alias'larını kullanır.
# Mesh node: WireGuard IP'leri üzerinden direkt bağlanır.
# Kaynak: deploy/scale/V1.4/documents/final.md

set -o pipefail

# ══════════════════════════════════════════════════════════════════════════════
# § TOPOLOJI — final.md §2, §3'ten sabit değerler
# ══════════════════════════════════════════════════════════════════════════════
SSH_USER="tucibeyin"
REPO_PATH="/var/www/teqlif.com"
BACKEND_PATH="$REPO_PATH/backend"

#             idx:  0              1                2              3             4              5
NODE_NAMES=(        gateway        node1            node2          node3         node4          node5        )
NODE_ROLES=(        "EDGE PROXY"   "EDGE 1"         "AI PROXY 1"   "MON/STAGING" "EDGE 2"       "CORE"       )
NODE_WG=(           10.10.0.2      10.10.0.1        10.10.0.3      10.10.0.4     10.10.0.6      10.10.0.5    )
NODE_PUB=(          94.16.105.135  135.125.175.223  198.12.123.33  5.249.165.10  51.75.74.124   45.146.252.165)
# ~/.ssh/config alias'ları (geliştirici makinesinden bağlantı için)
NODE_ALIAS=(        teqlif-gateway teqlif-node1     teqlif-node2   teqlif-node3  teqlif-node4   teqlif-node5 )

# Servis listeleri — final.md §9
NODE_SVCS_0="nginx node_exporter promtail"
NODE_SVCS_1="livekit minio redis-server edge-metrics-agent node_exporter promtail"
NODE_SVCS_2="teqlif-ai-proxy cf-failover node_exporter promtail"
NODE_SVCS_3="teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging livekit minio teqlif-ai-proxy clickhouse-server prometheus loki grafana-server alertmanager node_exporter promtail redis-server postgresql"
NODE_SVCS_4="livekit minio redis-server edge-metrics-agent node_exporter promtail"
NODE_SVCS_5="teqlif teqlif-worker teqlif-worker-critical postgresql clickhouse-server redis-server node_exporter promtail"

# ClickHouse tabloları — final.md §14
CH_TABLES=(user_events feed_analytics search_events swipe_live_events direct_sale_events)

# ══════════════════════════════════════════════════════════════════════════════
# § ÇALIŞMA BAĞLAMI — mesh içi mi dışı mı?
# ══════════════════════════════════════════════════════════════════════════════
MY_WG_IP=$(ip -4 addr show wg0 2>/dev/null | grep -Eo '10\.10\.0\.[0-9]+' | head -1)
IN_MESH=0
MY_IDX=-1

if [[ -n "$MY_WG_IP" ]]; then
  IN_MESH=1
  for i in "${!NODE_WG[@]}"; do
    [[ "${NODE_WG[$i]}" == "$MY_WG_IP" ]] && MY_IDX=$i && break
  done
fi

# SSH hedefleri: mesh içindeyse WireGuard IP, dışarıdaysa ~/.ssh/config alias'ı
declare -a SSH_T  # SSH_T[idx] = alias veya user@wg-ip
for i in "${!NODE_NAMES[@]}"; do
  if [[ $IN_MESH -eq 1 ]]; then
    SSH_T[$i]="${SSH_USER}@${NODE_WG[$i]}"
  else
    SSH_T[$i]="${NODE_ALIAS[$i]}"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# § SSH YARDIMCILARI
# ══════════════════════════════════════════════════════════════════════════════
SSH_OPTS="-o ConnectTimeout=6 -o BatchMode=yes -o StrictHostKeyChecking=no \
-o LogLevel=ERROR -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
-o ControlMaster=auto -o ControlPath=/tmp/ssh_tst_%r@%h:%p -o ControlPersist=60s"

# _rc idx "komut"  → uzak (veya lokal) komut çalıştır
_rc() {
  local idx="$1"; shift
  if [[ $IN_MESH -eq 1 && "$idx" -eq "$MY_IDX" ]]; then
    bash -c "$*" 2>/dev/null
  else
    ssh $SSH_OPTS "${SSH_T[$idx]}" "$*" 2>/dev/null
  fi
}

# _chk idx  → SSH bağlantısı var mı?
_chk() {
  if [[ $IN_MESH -eq 1 && "$1" -eq "$MY_IDX" ]]; then return 0; fi
  ssh $SSH_OPTS "${SSH_T[$1]}" true >/dev/null 2>&1
}

# ══════════════════════════════════════════════════════════════════════════════
# § ÇIKTI YARDIMCILARI
# ══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0; WARN=0

pass()   { echo -e "  ${GREEN}✓${RESET}  $1"; PASS=$((PASS+1)); }
fail()   { echo -e "  ${RED}✗${RESET}  $1"; FAIL=$((FAIL+1)); }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $1"; WARN=$((WARN+1)); }
info()   { echo -e "  ${CYAN}·${RESET}  $1"; }
header() { echo -e "\n${CYAN}${BOLD}══ $1 ══${RESET}"; }
sep()    { echo -e "${BOLD}────────────────────────────────────────────────────────────${RESET}"; }

# ══════════════════════════════════════════════════════════════════════════════
# BAŞLIK
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
echo -e "${BOLD}  Teqlif V1.4 — Sistem & Güvenlik Test Paketi${RESET}"
echo -e "  $(date '+%Y-%m-%d %H:%M:%S')"
if [[ $IN_MESH -eq 1 ]]; then
  echo -e "  ${CYAN}Çalışma bağlamı: mesh içi (${NODE_NAMES[$MY_IDX]}, wg0: $MY_WG_IP)${RESET}"
else
  echo -e "  ${CYAN}Çalışma bağlamı: mesh dışı (geliştirici makinesi)${RESET}"
fi
sep

# ══════════════════════════════════════════════════════════════════════════════
# 0. SSH ERİŞİM KONTROLÜ
# ══════════════════════════════════════════════════════════════════════════════
header "0. SSH Erişim Kontrolü"
REACHABLE=()
for i in "${!NODE_NAMES[@]}"; do
  name="${NODE_NAMES[$i]}"; target="${SSH_T[$i]}"
  if _chk "$i"; then
    pass "$name ($target) erişilebilir"
    REACHABLE+=("$i")
  else
    warn "$name ($target) SSH ulaşılamıyor — bu node testleri atlanacak"
  fi
done
_ok() { printf '%s\n' "${REACHABLE[@]}" | grep -qx "$1"; }

# ══════════════════════════════════════════════════════════════════════════════
# 1. WireGuard MESH — final.md §3
# ══════════════════════════════════════════════════════════════════════════════
header "1. WireGuard Mesh — IP Atamaları & Tam Mesh Ping"

for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"; wg="${NODE_WG[$i]}"

  state=$(_rc "$i" "systemctl is-active wg-quick@wg0 2>/dev/null || echo inactive")
  [[ "$state" == "active" ]] \
    && pass "$name: wg-quick@wg0 aktif" \
    || fail "$name: wg-quick@wg0 $state"

  _rc "$i" "ip addr show wg0 2>/dev/null | grep -q '$wg'" \
    && pass "$name: wg0 IP $wg atanmış" \
    || fail "$name: wg0 IP $wg atanmamış"
done

# Tam mesh ping testi — her erişilebilir node, diğer tüm WG IP'lerine ping atar
if _ok 5; then
  info "node5'ten tüm mesh node'larına ping:"
  for j in "${!NODE_WG[@]}"; do
    [[ "${NODE_WG[$j]}" == "${NODE_WG[5]}" ]] && continue
    target_wg="${NODE_WG[$j]}"; target_name="${NODE_NAMES[$j]}"
    _rc 5 "ping -c1 -W2 $target_wg >/dev/null 2>&1" \
      && pass "  node5 → $target_name ($target_wg) OK" \
      || fail "  node5 → $target_name ($target_wg) PING BAŞARISIZ — WireGuard peer sorunu!"
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# 2. SERVİS SAĞLIĞI — final.md §9
# ══════════════════════════════════════════════════════════════════════════════
header "2. Servis Sağlığı — systemd"

_svc_check() {
  local idx="$1" svc="$2" name="$3" opt="${4:-}"
  local target="$svc"
  # postgresql@xx versiyonlu adı dinamik bul
  if [[ "$svc" == "postgresql" ]]; then
    pg=$(_rc "$idx" "systemctl list-units 'postgresql@*' --no-legend --state=active 2>/dev/null | awk '{print \$1}' | head -1")
    [[ -n "$pg" ]] && target="$pg"
  fi
  local st=$(_rc "$idx" "systemctl is-active $target 2>/dev/null || echo inactive")
  if   [[ "$st" == "active"   ]]; then pass "$name: $svc active"
  elif [[ -n "$opt"           ]]; then warn "$name: $svc $st (opsiyonel)"
  else                                 fail "$name: $svc $st"
  fi
}

for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"
  eval "svcs=\"\$NODE_SVCS_${i}\""
  for svc in $svcs; do
    # node3 staging uygulamaları opsiyonel (staging down olabilir)
    if [[ "$name" == "node3" && "$svc" =~ ^teqlif-(staging|worker-staging|worker-critical-staging)$ ]]; then
      _svc_check "$i" "$svc" "$name" "optional"
    else
      _svc_check "$i" "$svc" "$name"
    fi
  done
done

# ══════════════════════════════════════════════════════════════════════════════
# 3. PORT İZOLASYONU — final.md §10, §12
# ══════════════════════════════════════════════════════════════════════════════
header "3. Port İzolasyonu — Kritik Portlar Dışa Kapalı mı?"
info "DB (5432/6379/8123) ve monitoring (9090/3100/3000/9093) portları dışa kapalı olmalı."

_port_closed() {
  local label="$1" ip="$2" port="$3"
  nc -zw3 "$ip" "$port" 2>/dev/null \
    && fail "$label ($ip:$port) dışarıya AÇIK — güvenlik açığı!" \
    || pass "$label ($ip:$port) dışarıya kapalı"
}
_port_open() {
  local label="$1" ip="$2" port="$3"
  nc -zw4 "$ip" "$port" 2>/dev/null \
    && pass "$label ($ip:$port) erişilebilir" \
    || fail "$label ($ip:$port) erişilemiyor"
}

# node5 public IP — DB portları kapalı
_port_closed "node5 PostgreSQL"         "${NODE_PUB[5]}" 5432
_port_closed "node5 Redis Core"         "${NODE_PUB[5]}" 6379
_port_closed "node5 ClickHouse HTTP"    "${NODE_PUB[5]}" 8123
_port_closed "node5 FastAPI direkt"     "${NODE_PUB[5]}" 8000

# node3 public IP — monitoring portları kapalı
_port_closed "node3 Prometheus"         "${NODE_PUB[3]}" 9090
_port_closed "node3 Loki"              "${NODE_PUB[3]}" 3100
_port_closed "node3 Grafana"           "${NODE_PUB[3]}" 3000
_port_closed "node3 Alertmanager"      "${NODE_PUB[3]}" 9093
_port_closed "node3 ClickHouse HTTP"   "${NODE_PUB[3]}" 8123
_port_closed "node3 PostgreSQL"        "${NODE_PUB[3]}" 5432
_port_closed "node3 AI Proxy direkt"   "${NODE_PUB[3]}" 8080

# node2 public — AI Proxy sadece WireGuard'dan
_port_closed "node2 AI Proxy direkt"   "${NODE_PUB[2]}" 8080

# node1/node4 — Edge Redis dışa kapalı
_port_closed "node1 Redis Edge"        "${NODE_PUB[1]}" 6379
_port_closed "node4 Redis Edge"        "${NODE_PUB[4]}" 6379

# Public portlar AÇIK olmalı
_port_open "gateway port 80"           "${NODE_PUB[0]}" 80
_port_open "gateway port 443"          "${NODE_PUB[0]}" 443
_port_open "node1 LiveKit API"         "${NODE_PUB[1]}" 7880
_port_open "node1 MinIO S3 API"        "${NODE_PUB[1]}" 9010
_port_open "node3 LiveKit staging"     "${NODE_PUB[3]}" 7880

# WireGuard iç erişimler: node5'ten node3:3100 (Loki) erişilebilir olmalı
if _ok 5; then
  _rc 5 "nc -zw3 ${NODE_WG[3]} 3100 2>/dev/null" \
    && pass "node5 → node3:3100 (Loki) WireGuard üzerinden erişilebilir" \
    || fail "node5 → node3:3100 (Loki) erişilemiyor — promtail logları gitmiyor!"
fi

# node3'ten tüm node_exporter portları erişilebilir olmalı (Prometheus scraping)
if _ok 3; then
  for j in "${!NODE_WG[@]}"; do
    wg="${NODE_WG[$j]}"; nname="${NODE_NAMES[$j]}"
    _rc 3 "nc -zw3 $wg 9100 2>/dev/null" \
      && pass "node3 → $nname:9100 (node_exporter) erişilebilir" \
      || fail "node3 → $nname:9100 (node_exporter) erişilemiyor — Prometheus scraping çalışmıyor!"
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. VERİTABANI & CACHE CANLILIK — final.md §5
# ══════════════════════════════════════════════════════════════════════════════
header "4. Veritabanı & Cache Canlılık"

# ── node5 production ──
if _ok 5; then
  _rc 5 'ss -tln | grep -q ":5432 "' \
    && pass "node5: PostgreSQL port 5432 dinliyor" \
    || fail "node5: PostgreSQL port 5432 kapalı"

  _rc 5 'clickhouse-client -q "SELECT 1" >/dev/null 2>&1' \
    && pass "node5: ClickHouse yanıt veriyor" \
    || fail "node5: ClickHouse yanıt vermiyor"

  rr=$(_rc 5 'redis-cli ping 2>&1')
  if   echo "$rr" | grep -q "NOAUTH"; then pass "node5: Redis Core canlı ve şifreli (ACL)"
  elif echo "$rr" | grep -q "PONG";   then fail "node5: Redis Core canlı FAKAT ŞİFRESİZ!"
  else                                       fail "node5: Redis Core yanıt vermiyor"
  fi

  # Redis Core mesh erişimi — node2 ve node3 AI Proxy bağlanabiliyor mu?
  _ok 2 && {
    _rc 2 "nc -zw3 ${NODE_WG[5]} 6379 2>/dev/null" \
      && pass "node2 → node5:6379 (Redis Core) WireGuard üzerinden OK" \
      || fail "node2 → node5:6379 (Redis Core) erişilemiyor — AI Proxy rate limit çalışmaz!"
  }
  _ok 3 && {
    _rc 3 "nc -zw3 ${NODE_WG[5]} 6379 2>/dev/null" \
      && pass "node3 → node5:6379 (Redis Core) WireGuard üzerinden OK" \
      || fail "node3 → node5:6379 (Redis Core) erişilemiyor — AI Proxy rate limit çalışmaz!"
  }
fi

# ── node3 staging ──
if _ok 3; then
  _rc 3 'ss -tln | grep -q ":5432 "' \
    && pass "node3: PostgreSQL staging port 5432 dinliyor" \
    || warn "node3: PostgreSQL staging port 5432 kapalı"

  _rc 3 'clickhouse-client -q "SELECT 1" >/dev/null 2>&1' \
    && pass "node3: ClickHouse staging yanıt veriyor" \
    || fail "node3: ClickHouse staging yanıt vermiyor"

  rr=$(_rc 3 'redis-cli ping 2>&1')
  if   echo "$rr" | grep -q "NOAUTH"; then pass "node3: Redis staging canlı ve şifreli"
  elif echo "$rr" | grep -q "PONG";   then fail "node3: Redis staging canlı FAKAT ŞİFRESİZ!"
  else                                       warn "node3: Redis staging yanıt vermiyor"
  fi

  # Staging Redis izolasyonu — sadece 127.0.0.1 bağlı olmalı
  _rc 3 'ss -tln | grep ":6379 " | grep -q "127.0.0.1"' \
    && pass "node3: Staging Redis 127.0.0.1 bağlı (izole)" \
    || warn "node3: Staging Redis bind adresi beklenmiyor — izolasyon kontrol et"
fi

# ── Edge Redis izolasyonu ──
for i in 1 4; do
  _ok $i || continue
  name="${NODE_NAMES[$i]}"
  _rc "$i" 'ss -tln | grep ":6379 " | grep -q "127.0.0.1"' \
    && pass "$name: Edge Redis 127.0.0.1 bağlı (izole)" \
    || warn "$name: Edge Redis bind beklenmiyor"
done

# ══════════════════════════════════════════════════════════════════════════════
# 5. CLICKHOuSE DB İZOLASYONU — final.md §14
# ══════════════════════════════════════════════════════════════════════════════
header "5. ClickHouse DB İzolasyonu"
info "Prod: teqlif_prod_analytics | Staging: teqlif_staging_analytics | default DB boş olmalı."

_ch_tables() {
  local idx="$1" db="$2" label="$3"
  db_ok=$(_rc "$idx" "clickhouse-client --query \"SELECT count() FROM system.databases WHERE name='$db'\" 2>/dev/null")
  if [[ "$db_ok" != "1" ]]; then
    fail "$label: DB '$db' YOK — ClickHouse kurulumu eksik!"
    return
  fi
  pass "$label: DB '$db' mevcut"
  for tbl in "${CH_TABLES[@]}"; do
    cnt=$(_rc "$idx" "clickhouse-client --query \"SELECT count() FROM system.tables WHERE database='$db' AND name='$tbl'\" 2>/dev/null")
    [[ "$cnt" == "1" ]] \
      && pass "  $label: $db.$tbl mevcut" \
      || fail "  $label: $db.$tbl EKSIK!"
  done
  # default DB kirlenmesi
  def=$(_rc "$idx" "clickhouse-client --query \"SELECT count() FROM system.tables WHERE database='default' AND name IN ('user_events','feed_analytics','search_events','swipe_live_events','direct_sale_events')\" 2>/dev/null")
  if [[ "$def" == "0" ]]; then
    pass "  $label: default DB temiz (analytics tablosu yok)"
  else
    warn "  $label: default DB'de $def analytics tablosu var — init_clickhouse() bug'u tetiklenmiş!"
  fi
}

_ok 5 && _ch_tables 5 "teqlif_prod_analytics"    "node5 (prod)"
_ok 3 && _ch_tables 3 "teqlif_staging_analytics" "node3 (staging)"

# ══════════════════════════════════════════════════════════════════════════════
# 6. MiNIO SAĞLIK & BUCKET — final.md §5, §7
# ══════════════════════════════════════════════════════════════════════════════
header "6. MinIO Sağlık & Bucket Kontrolü"

_minio_health() {
  local idx="$1" name="$2"
  st=$(_rc "$idx" "curl -s -o /dev/null -w '%{http_code}' http://localhost:9010/minio/health/live 2>/dev/null")
  [[ "$st" == "200" ]] \
    && pass "$name: MinIO health OK (HTTP 200)" \
    || fail "$name: MinIO health başarısız (HTTP $st)"
}

_minio_bucket() {
  local idx="$1" name="$2" bucket="$3"
  # HEAD /<bucket> → 200/301/403=var, 404=yok
  code=$(_rc "$idx" "curl -s -o /dev/null -w '%{http_code}' http://localhost:9010/$bucket 2>/dev/null")
  if [[ "$code" == "404" ]]; then
    fail "$name: bucket '$bucket' YOK!"
  elif [[ "$code" =~ ^(200|301|403)$ ]]; then
    pass "$name: bucket '$bucket' mevcut (HTTP $code)"
  else
    warn "$name: bucket '$bucket' kontrol edilemedi (HTTP $code)"
  fi
}

for i in 1 4; do
  _ok $i || continue
  name="${NODE_NAMES[$i]}"
  _minio_health "$i" "$name"
  _minio_bucket "$i" "$name" "teqlif"
  _minio_bucket "$i" "$name" "teqlif-dm"
done

if _ok 3; then
  _minio_health 3 "node3 (staging)"
  _minio_bucket 3 "node3 (staging)" "teqlif-staging"
  _minio_bucket 3 "node3 (staging)" "teqlif-dm-staging"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 7. AI PROXY YETKİ TESTİ — final.md §4, §12
# ══════════════════════════════════════════════════════════════════════════════
header "7. AI Proxy — Yetkisiz İstek Engelleme"
info "Yetkisiz POST → 401/403/422 bekleniyor. node5'ten WireGuard üzerinden test edilir."

_ai_proxy_test() {
  local from_idx="$1" target_wg="$2" target_name="$3"
  _ok "$from_idx" || { warn "$target_name: test için node5 erişilemiyor"; return; }
  code=$(_rc "$from_idx" \
    "curl -s -o /dev/null -w '%{http_code}' \
     -X POST http://${target_wg}:8080/generate \
     -H 'Content-Type: application/json' \
     -d '{\"prompt\":\"test\"}' --max-time 5 2>/dev/null" || echo "000")
  if   [[ "$code" =~ ^(401|403|422)$ ]]; then pass "$target_name AI Proxy: yetkisiz istek engellendi (HTTP $code)"
  elif [[ "$code" == "000"           ]]; then warn "$target_name AI Proxy: bağlantı zaman aşımı"
  else                                         warn "$target_name AI Proxy: beklenmedik yanıt (HTTP $code)"
  fi
}

_ai_proxy_test 5 "${NODE_WG[2]}" "node2 (primary)"
_ai_proxy_test 5 "${NODE_WG[3]}" "node3 (secondary)"

# ══════════════════════════════════════════════════════════════════════════════
# 8. HTTP ENDPOINT SAĞLIĞI — final.md §11
# ══════════════════════════════════════════════════════════════════════════════
header "8. HTTP Endpoint Sağlığı"
info "Proxied: CF üzerinden. DNS Only: direkt node public IP."

_curl_ok() {
  local label="$1" url="$2"
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null) || code="000"
  if   [[ "$code" =~ ^(200|204|301|302|401|403|404)$ ]]; then pass "$label → HTTP $code  ($url)"
  elif [[ "$code" == "000"                            ]]; then fail "$label → zaman aşımı / bağlantı reddedildi ($url)"
  else                                                          fail "$label → HTTP $code ($url)"
  fi
}

# Cloudflare Proxied
_curl_ok "teqlif.com"             "https://teqlif.com"
_curl_ok "api.teqlif.com"         "https://api.teqlif.com/api/health"
_curl_ok "staging.teqlif.com"     "https://staging.teqlif.com/api/health"
_curl_ok "api-staging.teqlif.com" "https://api-staging.teqlif.com/api/health"

# DNS Only — direkt node'a gider
_curl_ok "live1.teqlif.com"          "http://live1.teqlif.com:7880"
_curl_ok "live2.teqlif.com"          "http://live2.teqlif.com:7880"
_curl_ok "minio1.teqlif.com"         "http://minio1.teqlif.com:9010/minio/health/live"
_curl_ok "minio2.teqlif.com"         "http://minio2.teqlif.com:9010/minio/health/live"
_curl_ok "live-staging.teqlif.com"   "http://live-staging.teqlif.com:7880"
_curl_ok "minio-staging.teqlif.com"  "http://minio-staging.teqlif.com:9010/minio/health/live"

# node5 FastAPI — gateway üzerinden (WireGuard bypass yok)
_curl_ok "API gateway proxy"         "https://api.teqlif.com"

# LiveKit API erişimi: node5'ten node1 ve node4'e
if _ok 5; then
  for i in 1 4; do
    name="${NODE_NAMES[$i]}"; wg="${NODE_WG[$i]}"
    code=$(_rc 5 "curl -s -o /dev/null -w '%{http_code}' http://${wg}:7880 --max-time 5 2>/dev/null")
    [[ "$code" =~ ^(200|204|400|404)$ ]] \
      && pass "node5 → $name LiveKit API ($wg:7880) erişilebilir (HTTP $code)" \
      || warn "node5 → $name LiveKit API ($wg:7880) erişilemiyor (HTTP $code)"
  done
fi

# node5'ten node1/node4 MinIO erişimi
if _ok 5; then
  for i in 1 4; do
    name="${NODE_NAMES[$i]}"; wg="${NODE_WG[$i]}"
    code=$(_rc 5 "curl -s -o /dev/null -w '%{http_code}' http://${wg}:9010/minio/health/live --max-time 5 2>/dev/null")
    [[ "$code" == "200" ]] \
      && pass "node5 → $name MinIO ($wg:9010) erişilebilir" \
      || warn "node5 → $name MinIO ($wg:9010) erişilemiyor (HTTP $code)"
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# 9. MONİTORİNG STACK — final.md §13
# ══════════════════════════════════════════════════════════════════════════════
header "9. Monitoring Stack — node3"

if _ok 3; then
  # Prometheus: 7 hedef bekleniyor (6 node + kendisi)
  praw=$(_rc 3 "curl -s http://localhost:9090/api/v1/targets 2>/dev/null") || praw="{}"
  up_n=$(echo "$praw" | grep -o '"health":"up"' | wc -l | tr -d ' ')
  tot=$(echo  "$praw" | grep -o '"health":'     | wc -l | tr -d ' ')
  if   [[ "$up_n" -ge 7 ]]; then pass "node3 Prometheus: $up_n/$tot hedef UP (beklenen: 7)"
  elif [[ "$up_n" -ge 4 ]]; then warn "node3 Prometheus: $up_n/$tot hedef UP — bazı node'lar scraping dışında"
  else                            fail "node3 Prometheus: $up_n/$tot hedef UP (kritik, min 7 bekleniyor)"
  fi

  # Loki /ready
  lst=$(_rc 3 "curl -s -o /dev/null -w '%{http_code}' http://localhost:3100/ready 2>/dev/null")
  [[ "$lst" == "200" ]] \
    && pass "node3 Loki: /ready OK" \
    || fail "node3 Loki: /ready başarısız (HTTP $lst)"

  # Loki'ye kaç node'dan log geliyor?
  lnodes=$(_rc 3 \
    "curl -s 'http://localhost:3100/loki/api/v1/label/node/values' 2>/dev/null \
     | grep -o '\"[a-z0-9]*\"' | wc -l | tr -d ' '")
  if   [[ "$lnodes" -ge 6 ]]; then pass "node3 Loki: $lnodes node'dan log geliyor"
  elif [[ "$lnodes" -gt 0 ]]; then warn "node3 Loki: $lnodes node'dan log geliyor (6 bekleniyor)"
  else                              fail "node3 Loki: hiç log stream'i yok — promtail hedefleri hatalı!"
  fi

  # Grafana
  gst=$(_rc 3 "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/health 2>/dev/null")
  [[ "$gst" == "200" ]] \
    && pass "node3 Grafana: sağlıklı (HTTP 200)" \
    || warn "node3 Grafana: beklenmedik yanıt (HTTP $gst)"

  # Alertmanager
  _rc 3 "ss -tln | grep -q ':9093 '" \
    && pass "node3 Alertmanager: port 9093 dinliyor" \
    || fail "node3 Alertmanager: port 9093 kapalı"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 10. CONFIG DOSYALARI BÜTÜNLÜĞÜ — final.md §8, §13
# ══════════════════════════════════════════════════════════════════════════════
header "10. Config Dosyaları Bütünlüğü"

# node3 Prometheus
if _ok 3; then
  _rc 3 "test -f /etc/prometheus/prometheus-rules.yml" \
    && pass "node3: /etc/prometheus/prometheus-rules.yml mevcut" \
    || fail "node3: /etc/prometheus/prometheus-rules.yml EKSIK (wildcard path mi kullanılıyor?)"

  _rc 3 "grep -q 'prometheus-rules.yml' /etc/prometheus/prometheus.yml 2>/dev/null" \
    && pass "node3: prometheus.yml doğru rules yolunu gösteriyor" \
    || warn "node3: prometheus.yml rules yolu beklenmiyor — 'prometheus-rules.yml' olmalı"

  _rc 3 "test -f /etc/loki/config.yml" \
    && pass "node3: /etc/loki/config.yml mevcut" \
    || fail "node3: /etc/loki/config.yml EKSIK"

  _rc 3 "test -f /etc/alertmanager/alertmanager.yml" \
    && pass "node3: /etc/alertmanager/alertmanager.yml mevcut" \
    || fail "node3: /etc/alertmanager/alertmanager.yml EKSIK"
fi

# LiveKit config: node1, node3, node4
for i in 1 3 4; do
  _ok $i || continue
  name="${NODE_NAMES[$i]}"
  _rc "$i" "test -f /etc/livekit/livekit.yaml" \
    && pass "$name: /etc/livekit/livekit.yaml mevcut" \
    || fail "$name: /etc/livekit/livekit.yaml EKSIK"
done

# Promtail config: tüm node'larda mevcut ve doğru hedefe işaret ediyor
for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"
  _rc "$i" "test -f /etc/promtail-config.yml" \
    && pass "$name: /etc/promtail-config.yml mevcut" \
    || fail "$name: /etc/promtail-config.yml EKSIK"

  if [[ "$name" != "node3" ]]; then
    # node3 dışındakiler 10.10.0.4:3100'e gönderimeli
    _rc "$i" "grep -q '10.10.0.4:3100' /etc/promtail-config.yml 2>/dev/null" \
      && pass "$name: promtail hedefi 10.10.0.4:3100 (node3 Loki) — doğru" \
      || fail "$name: promtail hedefi yanlış! 10.10.0.4:3100 olmalı"
  else
    # node3 kendi Loki'sine göndermeli
    _rc "$i" "grep -qE 'localhost:3100|127\.0\.0\.1:3100' /etc/promtail-config.yml 2>/dev/null" \
      && pass "$name: promtail hedefi localhost:3100 (kendi Loki) — doğru" \
      || fail "$name: promtail hedefi yanlış — localhost:3100 olmalı"
  fi
done

# Gateway nginx: doğru upstream'lere işaret ediyor mu?
if _ok 0; then
  _rc 0 "grep -q '${NODE_WG[5]}:8000' /etc/nginx/sites-available/teqlif.com.conf 2>/dev/null" \
    && pass "gateway: nginx upstream teqlif_core → ${NODE_WG[5]}:8000 (node5)" \
    || warn "gateway: nginx upstream teqlif_core beklenmiyor"

  _rc 0 "grep -q '${NODE_WG[3]}:8001' /etc/nginx/sites-available/teqlif.com.conf 2>/dev/null" \
    && pass "gateway: nginx upstream teqlif_staging → ${NODE_WG[3]}:8001 (node3)" \
    || warn "gateway: nginx upstream teqlif_staging beklenmiyor"

  _rc 0 "systemctl is-active nginx | grep -q '^active'" \
    && pass "gateway: nginx aktif ve çalışıyor" \
    || fail "gateway: nginx DURDU — servis aktif değil!"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 11. EDGE-METRICS AGENT — final.md §5
# ══════════════════════════════════════════════════════════════════════════════
header "11. Edge-Metrics Agent"
info "node1/node4 → node5 Redis DB1 (edge_metrics:*), her 3s."

for i in 1 4; do
  _ok $i || continue
  name="${NODE_NAMES[$i]}"
  st=$(_rc "$i" "systemctl is-active edge-metrics-agent 2>/dev/null || echo inactive")
  [[ "$st" == "active" ]] \
    && pass "$name: edge-metrics-agent active" \
    || fail "$name: edge-metrics-agent $st"
done

# Redis DB1'de edge_metrics key'leri var mı? — .env'den Redis şifresini parse et
if _ok 5; then
  key_count=$(_rc 5 \
    'RPASS=$(grep "^REDIS_URL=" '"$BACKEND_PATH"'/.env.production 2>/dev/null | sed -E "s|.*:([^:@]*)@.*|\1|"); \
     redis-cli -a "${RPASS:-}" --no-auth-warning -n 1 keys "edge:metrics:*" 2>/dev/null | wc -l' \
    || echo "0")
  key_count=$(echo "$key_count" | tr -d '[:space:]')
  if   [[ "$key_count" -ge 2 ]]; then pass "node5 Redis DB1: $key_count edge_metrics key — node1 ve node4 yazıyor"
  elif [[ "$key_count" -eq 1 ]]; then warn "node5 Redis DB1: $key_count edge_metrics key — bir edge yazamıyor"
  else                                 warn "node5 Redis DB1: edge_metrics key yok — agent yazamıyor ya da auth sorunu"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 12. DİSK, BELLEK & SWAP — final.md §2, §13
# ══════════════════════════════════════════════════════════════════════════════
header "12. Disk, Bellek & Swap"
info "Prometheus alarm eşikleri: Disk>%80 / RAM>%85 / Swap>%50."

for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"

  # Disk
  disk=$(_rc "$i" "df / | awk 'NR==2 {gsub(\"%\",\"\",\$5); print \$5}'" 2>/dev/null)
  if [[ "$disk" =~ ^[0-9]+$ ]]; then
    if   [[ "$disk" -ge 80 ]]; then fail "$name: Disk %$disk — ALARM! (>%80)"
    elif [[ "$disk" -ge 70 ]]; then warn "$name: Disk %$disk — kritik eşiğe yaklaşıyor"
    else                            pass "$name: Disk %$disk"
    fi
  fi

  # RAM
  ram=$(_rc "$i" "free | awk '/^Mem:/ {\$2>0 ? printf \"%.0f\", \$3/\$2*100 : print 0}'" 2>/dev/null)
  if [[ "$ram" =~ ^[0-9]+$ ]]; then
    if   [[ "$ram" -ge 85 ]]; then fail "$name: RAM %$ram — ALARM! (>%85)"
    elif [[ "$ram" -ge 75 ]]; then warn "$name: RAM %$ram — yüksek"
    else                           pass "$name: RAM %$ram"
    fi
  fi

  # Swap
  swap_total=$(_rc "$i" "free -m | awk '/^Swap:/ {print \$2}'" 2>/dev/null || echo 0)
  swap_pct=$(_rc   "$i" "free | awk '/^Swap:/ {\$2>0 ? printf \"%.0f\", \$3/\$2*100 : print 0}'" 2>/dev/null || echo 0)
  if [[ "$swap_total" =~ ^[0-9]+$ && "$swap_total" -gt 0 ]]; then
    if [[ "$swap_pct" -ge 50 ]]; then warn "$name: Swap %$swap_pct — ALARM! (>%50)"
    else                              pass "$name: Swap ${swap_total}MB, %$swap_pct kullanımda"
    fi
  else
    warn "$name: Swap yok"
  fi
done

# node3 Zap-Hosting balloon kontrolü (90 gün girişsizlik → 1.8GB'a düşer)
if _ok 3; then
  ram_total=$(_rc 3 "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo 0)
  if [[ "$ram_total" =~ ^[0-9]+$ ]]; then
    if   [[ "$ram_total" -lt 2000 ]]; then fail "node3: RAM sadece ${ram_total}MB — Zap-Hosting balloon! Panel girişi gerekiyor (deadline: 2026-12-10)"
    elif [[ "$ram_total" -lt 3200 ]]; then warn "node3: RAM ${ram_total}MB — düşük"
    else                                   pass "node3: RAM ${ram_total}MB (balloon yok)"
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 13. RED TEAM — HASSas VERİ İFŞASI — final.md §12
# ══════════════════════════════════════════════════════════════════════════════
header "13. Red Team — Hassas Veri İfşası"

_blocked() {
  local label="$1" url="$2"
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 6 "$url" 2>/dev/null)
  if   [[ "$code" =~ ^(403|404|000|500)$ ]]; then pass "$label engellendi (HTTP $code)"
  elif [[ "$code" == "521"               ]]; then warn "$label test edilemedi — origin ulaşılamıyor (CF 521)"
  else                                            fail "$label SIZI: HTTP $code — $url"
  fi
}

_blocked "/.env sızıntısı"                    "https://teqlif.com/.env"
_blocked "/.env.production sızıntısı"         "https://teqlif.com/.env.production"
_blocked "/.git/config sızıntısı"             "https://teqlif.com/.git/config"
_blocked "/firebase-service-account.json"     "https://api.teqlif.com/firebase-service-account.json"
_blocked "/.env staging sızıntısı"            "https://staging.teqlif.com/.env"

# Auth bypass — sahte token ile private endpoint
auth_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 6 \
  -H "Authorization: Bearer fake_hack_token_v14_test" \
  "https://api.teqlif.com/api/auth/me" 2>/dev/null || echo "000")
if   [[ "$auth_code" =~ ^(401|403)$ ]]; then pass "API auth bypass engellendi (HTTP $auth_code)"
elif [[ "$auth_code" == "200"        ]]; then fail "API auth bypass MÜMKÜN — yetkisiz erişim!"
else                                          warn "API auth bypass testi belirsiz (HTTP $auth_code)"
fi

# node5'te firebase-service-account.json OLMALI (ama git'te değil)
if _ok 5; then
  _rc 5 "test -f $BACKEND_PATH/firebase-service-account.json" \
    && pass "node5: firebase-service-account.json mevcut (FCM push çalışır)" \
    || warn "node5: firebase-service-account.json YOK — FCM push çalışmaz!"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 14. UFW & SSH GÜVENLİK KONTROLÜ — final.md §12
# ══════════════════════════════════════════════════════════════════════════════
header "14. UFW & SSH Güvenlik Kontrolü"

for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"

  ufw=$(_rc "$i" "grep -i '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'")
  [[ "$ufw" == "YES" ]] \
    && pass "$name: UFW aktif" \
    || fail "$name: UFW KAPALI — güvenlik duvarı yok!"

  root_login=$(_rc "$i" "grep -rh '^PermitRootLogin' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | tail -1 | awk '{print tolower(\$2)}'")
  pass_auth=$(_rc   "$i" "grep -rh '^PasswordAuthentication' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | tail -1 | awk '{print tolower(\$2)}'")

  [[ "$root_login" == "no" ]] \
    && pass "$name: Root girişi kapalı" \
    || warn "$name: Root girişi açık"
  [[ "$pass_auth" == "no" ]] \
    && pass "$name: Parola girişi kapalı (key-only)" \
    || warn "$name: Parola girişi açık"
done

# ══════════════════════════════════════════════════════════════════════════════
# 15. TLS SERTİFİKA GEÇERLİLİĞİ — final.md §11
# ══════════════════════════════════════════════════════════════════════════════
header "15. TLS Sertifika Geçerliliği"

_cert() {
  local label="$1" host="$2" port="${3:-443}"
  cert=$(echo | openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null \
         | openssl x509 2>/dev/null)
  if [[ -z "$cert" ]]; then warn "$label: Sertifika alınamadı ($host:$port)"; return; fi
  exp=$(echo "$cert" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if   ! echo "$cert" | openssl x509 -checkend $((14*86400)) -noout >/dev/null 2>&1; then
    fail "$label: 14 gün içinde BİTİYOR ($exp) — ACİL YENILE!"
  elif ! echo "$cert" | openssl x509 -checkend $((30*86400)) -noout >/dev/null 2>&1; then
    warn "$label: 30 gün içinde sona eriyor ($exp)"
  else
    pass "$label: geçerli — $exp"
  fi
}

# Cloudflare proxied → CF sertifikası
_cert "teqlif.com"           "teqlif.com"
_cert "api.teqlif.com"       "api.teqlif.com"
_cert "staging.teqlif.com"   "staging.teqlif.com"

# DNS Only → node sertifikası
_cert "live1.teqlif.com"          "live1.teqlif.com"
_cert "live2.teqlif.com"          "live2.teqlif.com"
_cert "minio1.teqlif.com"         "minio1.teqlif.com"
_cert "minio2.teqlif.com"         "minio2.teqlif.com"
_cert "live-staging.teqlif.com"   "live-staging.teqlif.com"
_cert "minio-staging.teqlif.com"  "minio-staging.teqlif.com"

# ══════════════════════════════════════════════════════════════════════════════
# 16. KRİTİK LOG ANALİZİ — son 1 saat
# ══════════════════════════════════════════════════════════════════════════════
header "16. Kritik Log Analizi — Son 1 Saat"

for i in "${REACHABLE[@]}"; do
  name="${NODE_NAMES[$i]}"
  cnt=$(_rc "$i" "journalctl -p 0..3 -S '1 hour ago' --no-pager 2>/dev/null | grep -v 'maximum authentication attempts\|Protocol major versions differ\|pam_unix.*conversation failed\|pam_unix.*auth could not' | wc -l" || echo 0)
  cnt=$(echo "$cnt" | tr -d '[:space:]')
  if   [[ "$cnt" -gt 50 ]]; then warn "$name: $cnt kritik log — journalctl -p 3 -xe ile incele"
  elif [[ "$cnt" -gt 10 ]]; then warn "$name: $cnt kritik log satırı (sınırda)"
  else                           pass "$name: $cnt kritik log satırı"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
# SONUÇ RAPORU
# ══════════════════════════════════════════════════════════════════════════════
echo ""
sep
echo -e "${BOLD}  Teqlif V1.4 — Test Sonuç Raporu${RESET}"
echo -e "  $(date '+%Y-%m-%d %H:%M:%S')"
sep
echo -e "  ${GREEN}${BOLD}✓ PASS${RESET}  : $PASS"
echo -e "  ${YELLOW}${BOLD}⚠ WARN${RESET}  : $WARN"
echo -e "  ${RED}${BOLD}✗ FAIL${RESET}  : $FAIL"
echo -e "  Toplam  : $((PASS + WARN + FAIL)) test"
echo ""
if   [[ $FAIL -gt 0 ]]; then echo -e "${RED}${BOLD}  SONUÇ: $FAIL test BAŞARISIZ — müdahale gerekiyor.${RESET}";     sep; exit 1
elif [[ $WARN -gt 0 ]]; then echo -e "${YELLOW}${BOLD}  SONUÇ: Tüm kritik testler geçti, $WARN uyarı var.${RESET}";  sep; exit 0
else                          echo -e "${GREEN}${BOLD}  SONUÇ: Tüm testler geçti — sistem sağlıklı.${RESET}";         sep; exit 0
fi
