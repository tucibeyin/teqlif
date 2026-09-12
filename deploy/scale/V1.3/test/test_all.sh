#!/usr/bin/env bash
# deploy/scale/V1.3/test/test_all.sh
# Teqlif Scale V1.3 — Kapsamlı Test Paketi
# Çalıştırma: bash deploy/scale/V1.3/test/test_all.sh
# Gereksinim: SSH alias'ları tanımlı olmalı (teqlif-node1, teqlif-node2, teqlif-node3, teqlif-gateway)
set -o pipefail   # pipeline hataları yakalanır; -e YOK (test scripti tüm kontrolleri yapar)

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
NODES=(teqlif-node1 teqlif-gateway teqlif-node2 teqlif-node3)
NODE_NAMES=(node1 gateway node2 node3)
NODE_WG=(10.10.0.1 10.10.0.2 10.10.0.3 10.10.0.4)
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
  host="${NODES[$i]}"
  name="${NODE_NAMES[$i]}"
  wg_ip="${NODE_WG[$i]}"

  # wg0 aktif mi? (sudo gerektirmez)
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
header "2. Servis Sağlığı — systemd"

_check_svc() {
  local host="$1" svc="$2" label="$3"
  local status
  # status'u subshell dışında yakala — "activating\nunknown" hatasını önler
  status=$(_ssh "$host" "systemctl is-active $svc || true" 2>/dev/null) || status="unknown"
  # Birden fazla satır varsa ilkini al
  status=$(echo "$status" | head -1)
  if [[ "$status" == "active" ]]; then
    pass "$label: $svc active"
  else
    fail "$label: $svc $status"
  fi
}

# node1
if _is_reachable 0; then
  for svc in teqlif teqlif-worker teqlif-worker-critical node_exporter promtail redis-server livekit minio; do
    _check_svc teqlif-node1 "$svc" "node1"
  done
  timer_enabled=$(_ssh teqlif-node1 "systemctl is-enabled teqlif-backup.timer" 2>/dev/null) || timer_enabled="disabled"
  [[ "$timer_enabled" == "enabled" ]] && pass "node1: teqlif-backup.timer enabled" || fail "node1: teqlif-backup.timer enabled değil"
fi

# gateway
if _is_reachable 1; then
  for svc in nginx node_exporter promtail; do
    _check_svc teqlif-gateway "$svc" "gateway"
  done
  for svc in prometheus loki alertmanager; do
    status=$(_ssh teqlif-gateway "systemctl is-active $svc || true" 2>/dev/null) || status="inactive"
    status=$(echo "$status" | head -1)
    if [[ "$status" != "active" ]]; then
      pass "gateway: $svc kaldırıldı (inactive — beklenen)"
    else
      warn "gateway: $svc hâlâ aktif — node3'e taşınması gerekiyordu"
    fi
  done
fi

# node2
if _is_reachable 2; then
  for svc in teqlif-ai-proxy cf-failover node_exporter promtail; do
    _check_svc teqlif-node2 "$svc" "node2"
  done
fi

# node3
if _is_reachable 3; then
  for svc in teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging \
             teqlif-ai-proxy prometheus loki alertmanager \
             node_exporter promtail minio livekit nginx; do
    _check_svc teqlif-node3 "$svc" "node3"
  done
fi

# ── 3. HTTP ENDPOINT SAĞLIĞI ───────────────────────────────────────────────────
header "3. HTTP Endpoint Sağlığı"

_curl_ok() {
  local label="$1" url="$2"
  local result http_code
  result=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null) || result="000"
  http_code=$(echo "$result" | tail -1)
  if [[ "$http_code" =~ ^(200|204|301|302)$ ]]; then
    pass "$label: $url → HTTP $http_code"
  else
    fail "$label: $url → HTTP $http_code"
  fi
}

_curl_ok "gateway public"  "https://teqlif.com/api/health"
_curl_ok "uploads CDN"     "https://uploads.teqlif.com/"
# cf-health: nginx location opsiyonel — 404 fail değil warn
cf_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://teqlif.com/cf-health" 2>/dev/null) || cf_code="000"
[[ "$cf_code" == "200" ]] && pass "gateway cf-health → 200" || warn "gateway cf-health → HTTP $cf_code (nginx port 80 location kontrol et)"

# node1 lokal API
if _is_reachable 0; then
  node1_health=$(_ssh teqlif-node1 "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health" 2>/dev/null) || node1_health="000"
  [[ "$node1_health" =~ ^(200|204)$ ]] \
    && pass "node1: lokal API health → HTTP $node1_health" \
    || fail "node1: lokal API health → HTTP $node1_health"
fi

# node3 staging health
if _is_reachable 3; then
  staging_health=$(_ssh teqlif-node3 "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/api/health" 2>/dev/null) || staging_health="000"
  [[ "$staging_health" =~ ^(200|204)$ ]] \
    && pass "node3: staging API health → HTTP $staging_health" \
    || fail "node3: staging API health → HTTP $staging_health"
fi

# AI proxy health (node1'den WireGuard üzerinden)
if _is_reachable 0; then
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    health=$(_ssh teqlif-node1 "curl -s -o /dev/null -w '%{http_code}' http://$proxy_ip:8080/health" 2>/dev/null) || health="000"
    [[ "$health" =~ ^(200|204)$ ]] \
      && pass "node1→$proxy_label AI proxy health → HTTP $health" \
      || fail "node1→$proxy_label AI proxy health → HTTP $health"
  done
fi

# ── 4. AI PROXY FALLBACK ZİNCİRİ ──────────────────────────────────────────────
header "4. AI Proxy — Fallback Zinciri"

if _is_reachable 0; then
  # Token olmadan 401/403 beklenir
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    code=$(_ssh teqlif-node1 "curl -s -o /dev/null -w '%{http_code}' -X POST http://$proxy_ip:8080/generate" 2>/dev/null) || code="000"
    if [[ "$code" =~ ^(401|403|422)$ ]]; then
      pass "$proxy_label AI proxy: token olmadan $code (auth korumalı)"
    else
      warn "$proxy_label AI proxy: token olmadan $code (401/403 beklenir)"
    fi
  done

  # Config'de proxy URL'leri dolu mu?
  node2_url=$(_ssh teqlif-node1 "grep -E '^NODE2_AI_PROXY_URL=.+' /var/www/teqlif.com/deploy/scale/resources/node1/.env.production" 2>/dev/null) || node2_url=""
  node3_url=$(_ssh teqlif-node1 "grep -E '^NODE3_AI_PROXY_URL=.+' /var/www/teqlif.com/deploy/scale/resources/node1/.env.production" 2>/dev/null) || node3_url=""
  [[ -n "$node2_url" ]] && pass "node1 .env: NODE2_AI_PROXY_URL tanımlı" || fail "node1 .env: NODE2_AI_PROXY_URL boş"
  [[ -n "$node3_url" ]] && pass "node1 .env: NODE3_AI_PROXY_URL tanımlı" || fail "node1 .env: NODE3_AI_PROXY_URL boş"

  # AI_PROXY_INTERNAL_TOKEN 3 node'da tutarlı mı?
  tok1=$(_ssh teqlif-node1 "grep -E '^AI_PROXY_INTERNAL_TOKEN=' /var/www/teqlif.com/deploy/scale/resources/node1/.env.production | cut -d= -f2-" 2>/dev/null) || tok1=""
  tok2=""; tok3=""
  _is_reachable 2 && tok2=$(_ssh teqlif-node2 "grep -E '^AI_PROXY_INTERNAL_TOKEN=' /var/www/teqlif.com/deploy/scale/resources/node2/.env.production | cut -d= -f2-" 2>/dev/null) || tok2=""
  _is_reachable 3 && tok3=$(_ssh teqlif-node3 "grep -E '^AI_PROXY_INTERNAL_TOKEN=' /var/www/teqlif.com/deploy/scale/resources/node3/.env.production | cut -d= -f2-" 2>/dev/null) || tok3=""

  if [[ -z "$tok1" ]]; then
    warn "AI_PROXY_INTERNAL_TOKEN: node1'den okunamadı"
  elif [[ -z "$tok2" || -z "$tok3" ]]; then
    warn "AI_PROXY_INTERNAL_TOKEN: node2/node3 SSH eksik — karşılaştırma atlandı"
  elif [[ "$tok1" == "$tok2" && "$tok1" == "$tok3" ]]; then
    pass "AI_PROXY_INTERNAL_TOKEN: node1=node2=node3 (tutarlı)"
  else
    fail "AI_PROXY_INTERNAL_TOKEN: node'lar arasında FARKLI — 403 hatalarına yol açar"
  fi
fi

# ── 5. BACKUP SİSTEMİ ──────────────────────────────────────────────────────────
header "5. Backup Sistemi"

if _is_reachable 0; then
  latest_backup=$(_ssh teqlif-node1 "ls -t /var/backups/pg/teqlif-*.sql.gz 2>/dev/null | head -1") || latest_backup=""
  if [[ -n "$latest_backup" ]]; then
    backup_age=$(_ssh teqlif-node1 "echo \$(( (\$(date +%s) - \$(stat -c%Y '$latest_backup' 2>/dev/null || echo 0)) / 86400 ))") || backup_age="99"
    backup_age=$(echo "$backup_age" | head -1)
    if [[ "$backup_age" -le 1 ]]; then
      pass "node1: pg backup mevcut — ${backup_age} gün önce ($latest_backup)"
    elif [[ "$backup_age" -le 3 ]]; then
      warn "node1: pg backup ${backup_age} gün eski"
    else
      fail "node1: pg backup ${backup_age} gün eski — çalışmıyor olabilir"
    fi
  else
    fail "node1: /var/backups/pg/ altında backup dosyası yok"
  fi

  # id_backup: /root/.ssh/ dizini root:root 700 — doğrudan test -f çalışmaz.
  # Dolaylı doğrulama: offsite backup başarılıysa (node3'te dosya var) key çalışıyor demektir.
  if _is_reachable 3; then
    backup_count=$(_ssh teqlif-node3 "ls /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | wc -l | tr -d ' '") || backup_count="0"
    backup_count=$(echo "$backup_count" | head -1 | tr -d '[:space:]')
    if [[ "$backup_count" -gt 0 ]]; then
      pass "node1: backup SSH key çalışıyor (node3'te $backup_count offsite dosya mevcut)"
    else
      warn "node1: backup SSH key doğrulanamadı — node3'te offsite dosya yok"
    fi
  fi
fi

if _is_reachable 3; then
  offsite_pg=$(_ssh teqlif-node3 "ls /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | wc -l | tr -d ' '") || offsite_pg="0"
  offsite_pg=$(echo "$offsite_pg" | head -1 | tr -d '[:space:]')
  [[ "$offsite_pg" -gt 0 ]] \
    && pass "node3: offsite pg backup mevcut ($offsite_pg dosya)" \
    || fail "node3: /var/backups/teqlif/pg/ boş — rsync çalışmamış olabilir"

  redis_bak=$(_ssh teqlif-node3 "ls /var/backups/teqlif/redis/ 2>/dev/null | wc -l | tr -d ' '") || redis_bak="0"
  redis_bak=$(echo "$redis_bak" | head -1 | tr -d '[:space:]')
  [[ "$redis_bak" -gt 0 ]] \
    && pass "node3: Redis backup mevcut ($redis_bak dosya)" \
    || warn "node3: Redis backup dizini boş"
fi

# ── 6. MONİTORİNG STACK ────────────────────────────────────────────────────────
header "6. Monitoring Stack (node3)"

if _is_reachable 3; then
  prom_raw=$(_ssh teqlif-node3 "curl -s http://localhost:9090/api/v1/targets 2>/dev/null") || prom_raw="{}"
  up_count=$(echo "$prom_raw" | grep -o '"health":"up"' | wc -l | tr -d ' ')
  total_count=$(echo "$prom_raw" | grep -o '"health":' | wc -l | tr -d ' ')
  if [[ "$up_count" -eq 7 ]]; then
    pass "node3 Prometheus: tüm 7 hedef UP"
  elif [[ "$up_count" -gt 0 ]]; then
    warn "node3 Prometheus: $up_count/$total_count hedef UP (7 beklenir)"
  else
    fail "node3 Prometheus: hedefler alınamadı"
  fi

  # Her job ayrı
  for job in node-gateway node-node1 node-node2 node-node3 livekit postgres prometheus; do
    job_health=$(echo "$prom_raw" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for t in d.get('data',{}).get('activeTargets',[]):
    if t.get('labels',{}).get('job','')=='$job':
      print(t.get('health','unknown'))
      break
  else:
    print('not_found')
except:
  print('error')
" 2>/dev/null) || job_health="unknown"
    job_health=$(echo "$job_health" | head -1)
    [[ "$job_health" == "up" ]] && pass "Prometheus: job=$job UP" || fail "Prometheus: job=$job $job_health"
  done

  # Loki node label'ları
  loki_raw=$(_ssh teqlif-node3 "curl -s 'http://localhost:3100/loki/api/v1/label/node/values' 2>/dev/null") || loki_raw="{}"
  for node_label in node1 node2 node3 gateway; do
    echo "$loki_raw" | grep -q "\"$node_label\"" \
      && pass "Loki: node=$node_label log akışı var" \
      || fail "Loki: node=$node_label log akışı YOK"
  done

  # Alertmanager
  am_code=$(_ssh teqlif-node3 "curl -s -o /dev/null -w '%{http_code}' http://localhost:9093/api/v2/alerts" 2>/dev/null) || am_code="000"
  [[ "$am_code" == "200" ]] \
    && pass "node3 Alertmanager: /api/v2/alerts → 200" \
    || fail "node3 Alertmanager: /api/v2/alerts → $am_code"
fi

# ── 7. SYSTEMD BAĞIMLILIKLARI ──────────────────────────────────────────────────
header "7. Systemd Bağımlılıkları (Wants / PartOf / BindsTo)"

if _is_reachable 0; then
  wants=$(_ssh teqlif-node1 "systemctl show teqlif.service --property=Wants --value" 2>/dev/null) || wants=""
  echo "$wants" | grep -q "teqlif-worker.service" \
    && pass "node1 teqlif.service: Wants=teqlif-worker.service" \
    || fail "node1 teqlif.service: Wants içinde teqlif-worker.service yok"
  echo "$wants" | grep -q "teqlif-worker-critical.service" \
    && pass "node1 teqlif.service: Wants=teqlif-worker-critical.service" \
    || fail "node1 teqlif.service: Wants içinde teqlif-worker-critical.service yok"

  for wrkr in teqlif-worker teqlif-worker-critical; do
    binds=$(_ssh teqlif-node1 "systemctl show ${wrkr}.service --property=BindsTo --value" 2>/dev/null) || binds=""
    part=$(_ssh teqlif-node1  "systemctl show ${wrkr}.service --property=PartOf --value"  2>/dev/null) || part=""
    echo "$binds" | grep -q "teqlif.service" \
      && pass "node1 $wrkr: BindsTo=teqlif.service" \
      || fail "node1 $wrkr: BindsTo eksik"
    echo "$part" | grep -q "teqlif.service" \
      && pass "node1 $wrkr: PartOf=teqlif.service" \
      || fail "node1 $wrkr: PartOf eksik"
  done

  exec_pre=$(_ssh teqlif-node1 "systemctl show teqlif.service --property=ExecStartPre --value" 2>/dev/null) || exec_pre=""
  echo "$exec_pre" | grep -qi "alembic"   && pass "node1 teqlif.service: ExecStartPre alembic"    || fail "node1 teqlif.service: ExecStartPre alembic yok"
  echo "$exec_pre" | grep -qi "sync_main" && pass "node1 teqlif.service: ExecStartPre sync_main"  || fail "node1 teqlif.service: ExecStartPre sync_main yok"
fi

if _is_reachable 3; then
  wants_s=$(_ssh teqlif-node3 "systemctl show teqlif-staging.service --property=Wants --value" 2>/dev/null) || wants_s=""
  echo "$wants_s" | grep -q "teqlif-worker-staging.service" \
    && pass "node3 teqlif-staging.service: Wants=worker-staging" \
    || fail "node3 teqlif-staging.service: Wants içinde worker-staging yok"
  for wrkr in teqlif-worker-staging teqlif-worker-critical-staging; do
    binds=$(_ssh teqlif-node3 "systemctl show ${wrkr}.service --property=BindsTo --value" 2>/dev/null) || binds=""
    echo "$binds" | grep -q "teqlif-staging.service" \
      && pass "node3 $wrkr: BindsTo=teqlif-staging.service" \
      || fail "node3 $wrkr: BindsTo eksik"
  done
fi

# ── 8. STAGING İZOLASYONU ──────────────────────────────────────────────────────
header "8. Staging İzolasyonu"

if _is_reachable 0; then
  s_enabled=$(_ssh teqlif-node1 "systemctl is-enabled teqlif-staging.service 2>/dev/null || echo disabled") || s_enabled="disabled"
  s_enabled=$(echo "$s_enabled" | head -1)
  [[ "$s_enabled" != "enabled" ]] \
    && pass "node1: teqlif-staging.service yok/disabled (beklenen)" \
    || fail "node1: teqlif-staging.service hâlâ enabled"

  ufw_8001=$(_ssh teqlif-node1 "sudo ufw status 2>/dev/null | grep 8001 || echo ''") || ufw_8001=""
  [[ -z "$ufw_8001" ]] \
    && pass "node1: UFW 8001 kuralı yok (beklenen)" \
    || warn "node1: UFW 8001 kuralı hâlâ mevcut"
fi

if _is_reachable 3; then
  pg_s=$(_ssh teqlif-node3 "pg_isready -h 127.0.0.1 -U teqlif_staging -d teqlif_staging -q 2>/dev/null && echo 1 || echo 0" 2>/dev/null) || pg_s="0"
  pg_s=$(echo "$pg_s" | head -1 | tr -d '[:space:]')
  [[ "$pg_s" == "1" ]] \
    && pass "node3: teqlif_staging DB erişilebilir" \
    || fail "node3: teqlif_staging DB erişilemiyor"

  # MinIO alias: port 9010 üzerindeki alias'ı bul (genellikle "node3-staging")
  mc_alias=$(_ssh teqlif-node3 "mc alias list --json 2>/dev/null | python3 -c \"import sys,json; [print(json.loads(l).get('alias','')) for l in sys.stdin if '9010' in l]\" 2>/dev/null | head -1") || mc_alias=""
  mc_alias=$(echo "$mc_alias" | tr -d '[:space:]')
  [[ -z "$mc_alias" ]] && mc_alias="node3-staging"
  for bucket in teqlif-staging teqlif-dm-staging; do
    bk=$(_ssh teqlif-node3 "mc ls $mc_alias/$bucket >/dev/null 2>&1 && echo ok || echo fail") || bk="fail"
    bk=$(echo "$bk" | head -1)
    [[ "$bk" == "ok" ]] && pass "node3: MinIO bucket $bucket mevcut ($mc_alias)" || fail "node3: MinIO bucket $bucket yok ($mc_alias)"
  done

  if _is_reachable 0; then
    for bucket in teqlif-staging teqlif-dm-staging; do
      gone=$(_ssh teqlif-node1 "mc ls local/$bucket >/dev/null 2>&1 && echo exists || echo gone") || gone="gone"
      gone=$(echo "$gone" | head -1)
      [[ "$gone" == "gone" ]] && pass "node1: MinIO $bucket kaldırıldı (beklenen)" || warn "node1: MinIO $bucket hâlâ mevcut"
    done

    prod_db=$(_ssh teqlif-node1 "grep -E '^DATABASE_URL=' /var/www/teqlif.com/deploy/scale/resources/node1/.env.production | cut -d= -f2-" 2>/dev/null) || prod_db=""
    stag_db=$(_ssh teqlif-node3 "grep -E '^DATABASE_URL=' /var/www/teqlif.com/deploy/scale/resources/node3/.env.staging | cut -d= -f2-" 2>/dev/null) || stag_db=""
    if [[ -z "$prod_db" || -z "$stag_db" ]]; then
      warn "DB URL karşılaştırması: bir veya iki taraf okunamadı"
    elif [[ "$prod_db" != "$stag_db" ]]; then
      pass "Staging DB URL prod'dan farklı (izolasyon OK)"
    else
      fail "Staging DB URL prod ile AYNI — izolasyon bozuk"
    fi
  fi
fi

# ── 9. GÜVENLİK ────────────────────────────────────────────────────────────────
header "9. Güvenlik"

if _is_reachable 0; then
  redis_listen=$(_ssh teqlif-node1 "ss -tlnp 2>/dev/null | grep :6379") || redis_listen=""
  # Sadece local bind sütununda 0.0.0.0:6379 veya *:6379 ara — "0.0.0.0:*" remote kolonu normal
  if echo "$redis_listen" | grep -qE "0\.0\.0\.0:6379|\*:6379"; then
    warn "node1: Redis 0.0.0.0:6379 bind — UFW dışarıdan koruyor (redis.conf'ta bind 127.0.0.1 10.10.0.1 önerilir)"
  else
    pass "node1: Redis lokal/WireGuard dinliyor (OK)"
  fi
fi

# UFW: sudo gerektirmeden /etc/ufw/ufw.conf kontrolü
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

# AI proxy — token olmadan erişim engeli (node1'den)
if _is_reachable 0; then
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    code=$(_ssh teqlif-node1 "curl -s -o /dev/null -w '%{http_code}' -X POST http://$proxy_ip:8080/generate" 2>/dev/null) || code="000"
    code=$(echo "$code" | head -1)
    [[ "$code" =~ ^(401|403|422)$ ]] \
      && pass "$proxy_label AI proxy: yetkisiz istek $code (korumalı)" \
      || warn "$proxy_label AI proxy: yetkisiz istek $code döndü (401/403 beklenir)"
  done
fi

# ── 10. PERFORMANS: Temel Yanıt Süreleri ──────────────────────────────────────
header "10. Performans — Yanıt Süreleri"

_latency() {
  local label="$1" url="$2" threshold_ms="$3"
  local result http_code time_ms
  result=$(curl -sk -o /dev/null -w "%{http_code} %{time_total}" --max-time 10 "$url" 2>/dev/null) || result="000 99"
  http_code=$(echo "$result" | awk '{print $1}')
  time_ms=$(echo "$result" | awk '{printf "%d", $2*1000}')
  if [[ "$http_code" =~ ^(200|204|301|302)$ ]] && [[ "$time_ms" -lt "$threshold_ms" ]]; then
    pass "$label: ${time_ms}ms < ${threshold_ms}ms (HTTP $http_code)"
  elif [[ "$http_code" =~ ^(200|204|301|302)$ ]]; then
    warn "$label: ${time_ms}ms ≥ ${threshold_ms}ms — yavaş"
  else
    fail "$label: HTTP $http_code (${time_ms}ms)"
  fi
}

_latency "gateway teqlif.com"      "https://teqlif.com/"              3000
_latency "prod API health"         "https://teqlif.com/api/health"    3000
_latency "uploads.teqlif.com"      "https://uploads.teqlif.com/"      3000

if _is_reachable 0; then
  local_result=$(_ssh teqlif-node1 "curl -s -o /dev/null -w '%{http_code} %{time_total}' http://127.0.0.1:8000/api/health" 2>/dev/null) || local_result="000 99"
  local_ms=$(echo "$local_result" | awk '{printf "%d", $2*1000}')
  [[ "$local_ms" -lt 500 ]] \
    && pass "node1 lokal API: ${local_ms}ms < 500ms" \
    || warn "node1 lokal API: ${local_ms}ms — yüksek"
fi

# ── 11. LOG AKIŞI ──────────────────────────────────────────────────────────────
header "11. Log Akışı — promtail positions"

for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  _ssh_check "$host" "test -f /var/lib/promtail/positions.yaml" \
    && pass "$name: /var/lib/promtail/positions.yaml mevcut" \
    || fail "$name: positions.yaml yok — promtail veri kaybı riski"
done

# Uygulama log dizini yalnızca FastAPI çalıştıran node'larda beklenir (node1, node3)
for i in 0 3; do
  _is_reachable "$i" || continue
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  # /var/log/teqlif dizini veya /var/www/teqlif.com/logs symlink'i
  _ssh_check "$host" "test -d /var/log/teqlif || test -d /var/www/teqlif.com/logs || test -L /var/www/teqlif.com/logs" \
    && pass "$name: uygulama log dizini mevcut" \
    || warn "$name: /var/log/teqlif bulunamadı — bootstrap'te log dizini oluşturulur"
done

# ── 12. SERTİFİKA GEÇERLİLİĞİ ─────────────────────────────────────────────────
header "12. TLS Sertifika Geçerliliği"

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

_check_cert "teqlif.com"              "teqlif.com"
_check_cert "uploads.teqlif.com"      "uploads.teqlif.com"
_check_cert "staging.teqlif.com"      "staging.teqlif.com"
_check_cert "uploads-staging"         "uploads-staging.teqlif.com"
_check_cert "live.teqlif.com"         "live.teqlif.com"
_check_cert "live-staging.teqlif.com" "live-staging.teqlif.com"

# ── ÖZET ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
echo -e "${BOLD} Teqlif V1.3 Test Özeti${RESET}"
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
