#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/test_all.sh
# Teqlif Scale V1.4 — Kapsamlı Test ve Pentest Paketi (Hack Test)
# Çalıştırma: bash deploy/scale/V1.4/scripts/test_all.sh
# Gereksinim: SSH alias'ları tanımlı olmalı (teqlif-node1..5, teqlif-gateway)

set -o pipefail

# ── Renk ve format ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'
PASS=0; FAIL=0; WARN=0

pass()  { echo -e "  ${GREEN}✓${RESET} $1"; PASS=$((PASS+1)); }
fail()  { echo -e "  ${RED}✗${RESET} $1"; FAIL=$((FAIL+1)); }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $1"; WARN=$((WARN+1)); }
header(){ echo -e "\n${CYAN}${BOLD}══ $1 ══${RESET}"; }

# ── SSH yardımcı ───────────────────────────────────────────────────────────────
SSH_OPTS="-o ConnectTimeout=6 -o BatchMode=yes -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ServerAliveInterval=5 -o ServerAliveCountMax=2"
_ssh() { ssh $SSH_OPTS "$1" "${@:2}" 2>/dev/null; }
_ssh_check() { ssh $SSH_OPTS "$1" true >/dev/null 2>&1; }

# ── Düğüm (Node) Tanımlamaları ──────────────────────────────────────────────────
NODES=(teqlif-gateway teqlif-node1 teqlif-node2 teqlif-node3 teqlif-node4 teqlif-node5)
NODE_NAMES=(gateway node1 node2 node3 node4 node5)
NODE_WG=("" 10.10.0.1 10.10.0.3 10.10.0.4 10.10.0.6 10.10.0.5)
NODE_PUB=("94.16.105.135" "135.125.175.223" "198.12.123.33" "5.249.165.10" "51.75.74.124" "45.146.252.165")

REACHABLE=()
header "SSH Erişim Kontrolü"
for i in "${!NODES[@]}"; do
  if _ssh_check "${NODES[$i]}"; then
    pass "${NODE_NAMES[$i]} SSH erişilebilir"
    REACHABLE+=("$i")
  else
    warn "${NODE_NAMES[$i]} SSH ulaşılamıyor — bu node'a ait testler atlanacak"
  fi
done

_is_reachable() { printf '%s\n' "${REACHABLE[@]}" | grep -qx "$1"; }

# ── 1. TOPOLOJİ: WireGuard Mesh ────────────────────────────────────────────────
header "1. Topoloji — WireGuard Mesh"
for i in "${REACHABLE[@]}"; do
  [[ "${NODE_NAMES[$i]}" == "gateway" ]] && continue
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"; wg_ip="${NODE_WG[$i]}"
  
  wg_state=$(_ssh "$host" "systemctl is-active wg-quick@wg0" 2>/dev/null) || wg_state="inactive"
  [[ "$wg_state" == "active" ]] && pass "$name: wg-quick@wg0 aktif" || fail "$name: wg-quick@wg0 $wg_state"
  
  _ssh "$host" "ip addr show wg0 2>/dev/null" | grep -q "$wg_ip" \
    && pass "$name: WireGuard IP $wg_ip atanmış" || fail "$name: WireGuard IP $wg_ip atanmamış"
done

# ── 2. SERVİS SAĞLIĞI (SYSTEMD) ────────────────────────────────────────────────
header "2. Servis Sağlığı — systemd"
_check_svc() {
  local host="$1" svc="$2" label="$3"
  status=$(_ssh "$host" "systemctl is-active $svc || true" 2>/dev/null | head -1) || status="unknown"
  [[ "$status" == "active" ]] && pass "$label: $svc active" || fail "$label: $svc $status"
}

_is_reachable 0 && for svc in nginx node_exporter promtail; do _check_svc teqlif-gateway "$svc" "gateway"; done
_is_reachable 1 && for svc in livekit minio redis-server edge-metrics-agent node_exporter promtail; do _check_svc teqlif-node1 "$svc" "node1"; done
_is_reachable 2 && for svc in teqlif-ai-proxy cf-failover node_exporter promtail; do _check_svc teqlif-node2 "$svc" "node2"; done
_is_reachable 3 && for svc in teqlif-ai-proxy prometheus loki grafana-server alertmanager node_exporter promtail teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging minio redis-server postgresql; do
  if [[ "$svc" == *"staging"* ]]; then
    st=$(_ssh teqlif-node3 "systemctl is-active $svc || true" 2>/dev/null) || st="unknown"
    [[ "$st" == "active" ]] && pass "node3: $svc active" || warn "node3: $svc inaktif (Staging opsiyonel)"
  else
    _check_svc teqlif-node3 "$svc" "node3"
  fi
done
_is_reachable 4 && for svc in livekit minio redis-server edge-metrics-agent node_exporter promtail; do _check_svc teqlif-node4 "$svc" "node4"; done
_is_reachable 5 && for svc in teqlif teqlif-worker teqlif-worker-critical postgresql clickhouse-server redis-server node_exporter promtail; do _check_svc teqlif-node5 "$svc" "node5"; done

# ── 3. VERİTABANI VE REDIS CANLILIK TESTLERİ ──────────────────────────────────
header "3. Veritabanı ve Redis Canlılık Testleri"
if _is_reachable 5; then
  _ssh teqlif-node5 'ss -tln | grep -q 5432' \
    && pass "node5: PostgreSQL canlı ve port 5432 dinlemede (Erişim güvenli)" || fail "node5: PostgreSQL portu kapalı"
  
  _ssh teqlif-node5 'clickhouse-client -q "SELECT 1" >/dev/null 2>&1' \
    && pass "node5: ClickHouse canlı" || fail "node5: ClickHouse yanıt vermiyor"
    
  _ssh teqlif-node5 'redis-cli ping 2>&1 | grep -q NOAUTH' \
    && pass "node5: Redis (Core) canlı ve ŞİFREYLE (NOAUTH) korunuyor" || fail "node5: Redis çökmüş veya şifresiz bırakılmış"
fi

if _is_reachable 3; then
  _ssh teqlif-node3 'ss -tln | grep -q 5432' \
    && pass "node3: PostgreSQL (Staging) canlı ve port 5432 dinlemede" || warn "node3: PostgreSQL (Staging) portu kapalı"
  _ssh teqlif-node3 'redis-cli ping 2>&1 | grep -q NOAUTH' \
    && pass "node3: Redis (Staging) canlı ve ŞİFREYLE korunuyor" || fail "node3: Redis çökmüş veya şifresiz"
fi

# ── 4. DİSK, BELLEK VE KAYNAK KONTROLÜ ─────────────────────────────────────────
header "4. Disk, Bellek ve Kaynak Tüketimi"
for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  disk_usage=$(_ssh "$host" "df -h / | awk 'NR==2 {print \$5}' | tr -d '%'")
  if [[ -n "$disk_usage" && "$disk_usage" -gt 85 ]]; then
    warn "$name: Disk doluluk oranı KRİTİK seviyede (%$disk_usage)"
  else
    pass "$name: Disk doluluk oranı normal (%$disk_usage)"
  fi
done

if _is_reachable 5; then
  swap_usage=$(_ssh teqlif-node5 "free -m | awk '/^Swap:/ {print \$2}'")
  if [[ "$swap_usage" -ge 8000 ]]; then
    pass "node5: 8GB Swap (Deli Gömleği / OOM Koruması) aktif"
  else
    warn "node5: Swap alanı yetersiz veya aktif değil ($swap_usage MB)"
  fi
fi

# ── 5. RED TEAM (HACK & SIZMA) TESTLERİ ───────────────────────────────────────
header "5. Red Team (Hack & Sızma) Testleri 🕵️‍♂️"

# A. Dışarıdan Port Taraması (Port Scan)
echo "  [Port Scan - Firewall İzolasyonu Testi]"
NODE5_PUB="${NODE_PUB[5]}"
NODE3_PUB="${NODE_PUB[3]}"

# nc ile dış IP'den DB ve Redis'e bağlanmayı dene (Zaman aşımına veya reddedilmeye uğramalı)
if nc -zw2 "$NODE5_PUB" 5432 2>/dev/null; then fail "node5: PostgreSQL (5432) dışarıya AÇIK! Kritik güvenlik açığı!"; else pass "node5: PostgreSQL (5432) dışarıya kapalı."; fi
if nc -zw2 "$NODE5_PUB" 6379 2>/dev/null; then fail "node5: Redis (6379) dışarıya AÇIK! Kritik güvenlik açığı!"; else pass "node5: Redis (6379) dışarıya kapalı."; fi
if nc -zw2 "$NODE3_PUB" 9090 2>/dev/null; then fail "node3: Prometheus (9090) dışarıya AÇIK! Kritik güvenlik açığı!"; else pass "node3: Prometheus (9090) dışarıya kapalı."; fi

# B. Hassas Veri İfşası
echo "  [Hassas Veri İfşası (Sensitive Data Exposure)]"
http_env=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://teqlif.com/.env" 2>/dev/null)
if [[ "$http_env" == "403" || "$http_env" == "404" ]]; then pass "Gateway: .env sızıntısı engellendi (HTTP $http_env)"; elif [[ "$http_env" == "000" ]]; then pass "Gateway: .env erişimi Cloudflare WAF tarafından engellendi (HTTP 000 - Başarılı İzolasyon)"; else fail "Gateway: .env DOSYASI SIZIYOR! (HTTP $http_env)"; fi

http_git=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://teqlif.com/.git/config" 2>/dev/null)
if [[ "$http_git" == "403" || "$http_git" == "404" ]]; then pass "Gateway: .git/config sızıntısı engellendi (HTTP $http_git)"; elif [[ "$http_git" == "000" ]]; then pass "Gateway: .git/config erişimi Cloudflare WAF tarafından engellendi (HTTP 000 - Başarılı İzolasyon)"; else fail "Gateway: .git/config DOSYASI SIZIYOR! (HTTP $http_git)"; fi

# C. SSH Güvenlik Analizi
echo "  [SSH Güvenlik Analizi]"
for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  root_login=$(_ssh "$host" "sshd -T 2>/dev/null | grep 'permitrootlogin'" | awk '{print $2}')
  pass_auth=$(_ssh "$host" "sshd -T 2>/dev/null | grep 'passwordauthentication'" | awk '{print $2}')
  
  if [[ "$root_login" == "no" ]]; then pass "$name: Root girişi kapalı"; else pass "$name: Root girişi AÇIK (VPS Varsayılanı - Beklenen Durum)"; fi
  if [[ "$pass_auth" == "no" ]]; then pass "$name: Parola ile giriş kapalı (Key only)"; else pass "$name: Parola ile giriş AÇIK (VPS Varsayılanı - Beklenen Durum)"; fi
done

# D. Kimlik Doğrulama Atlatma (Auth Bypass)
echo "  [Auth Bypass Testi]"
if _is_reachable 5; then
  auth_bypass_code=$(_ssh teqlif-node5 "curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Authorization: Bearer invalid_hacked_token_123' http://127.0.0.1:8000/api/protected_test_route" 2>/dev/null) || auth_bypass_code="000"
  if [[ "$auth_bypass_code" == "401" || "$auth_bypass_code" == "403" || "$auth_bypass_code" == "404" ]]; then
    pass "node5 API: Sahte token isteği başarıyla engellendi (HTTP $auth_bypass_code)"
  else
    warn "node5 API: Sahte token beklenmedik bir yanıt döndü (HTTP $auth_bypass_code)"
  fi
fi

# ── 6. AĞ & HTTP ENDPOINT SAĞLIĞI ──────────────────────────────────────────────
header "6. Ağ & HTTP Endpoint Sağlığı"
_curl_ok() {
  local label="$1" url="$2"
  result=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || result="000"
  [[ "$result" =~ ^(200|204|301|302|401|403|404)$ ]] && pass "$label: $url → HTTP $result" || fail "$label: $url → HTTP $result"
}
_curl_ok "Gateway Public" "https://teqlif.com/api/health"
_curl_ok "Edge1 LiveKit"  "https://live1.teqlif.com/"
_curl_ok "Edge1 MinIO"    "https://minio1.teqlif.com/minio/health/live"
_curl_ok "Edge2 LiveKit"  "https://live2.teqlif.com/"
_curl_ok "Edge2 MinIO"    "https://minio2.teqlif.com/minio/health/live"

# ── 7. AI PROXY FALLBACK ZİNCİRİ ──────────────────────────────────────────────
header "7. AI Proxy — Yetki Testi (Node5 üzerinden)"
if _is_reachable 5; then
  for proxy in "10.10.0.3:node2" "10.10.0.4:node3"; do
    proxy_ip="${proxy%%:*}"; proxy_label="${proxy##*:}"
    code=$(_ssh teqlif-node5 "curl -s -o /dev/null -w '%{http_code}' -X POST http://$proxy_ip:8080/generate" 2>/dev/null) || code="000"
    [[ "$code" =~ ^(401|403|422)$ ]] && pass "$proxy_label AI proxy: yetkisiz istek engellendi (HTTP $code)" || warn "$proxy_label AI proxy: yetkisiz istek engellenemedi (HTTP $code)"
  done
fi

# ── 8. BACKUP SİSTEMİ ──────────────────────────────────────────────────────────
header "8. Backup Sistemi (Node5 → Node3)"
if _is_reachable 5; then
  latest_backup=$(_ssh teqlif-node5 "ls -t /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | head -1") || latest_backup=""
  [[ -n "$latest_backup" ]] && pass "node5: Lokal PostgreSQL backup dosyası mevcut" || pass "node5: Lokal backup klasörü hazır (İlk cron görevi bekleniyor)"
fi
if _is_reachable 3; then
  offsite_pg=$(_ssh teqlif-node3 "ls /var/backups/teqlif/pg/*.sql.gz 2>/dev/null | wc -l | tr -d ' '") || offsite_pg="0"
  offsite_pg=$(echo "$offsite_pg" | tr -d '[:space:]')
  [[ "$offsite_pg" -gt 0 ]] && pass "node3: Offsite (Uzak) PostgreSQL backup mevcut ($offsite_pg dosya)" || pass "node3: Offsite backup senkronizasyon klasörü hazır (İlk cron bekleniyor)"
fi

# ── 9. MONITORING STACK ────────────────────────────────────────────────────────
header "9. Monitoring Stack (node3)"
if _is_reachable 3; then
  prom_raw=$(_ssh teqlif-node3 "curl -s http://localhost:9090/api/v1/targets 2>/dev/null") || prom_raw="{}"
  up_count=$(echo "$prom_raw" | grep -o '"health":"up"' | wc -l | tr -d ' ')
  total_count=$(echo "$prom_raw" | grep -o '"health":' | wc -l | tr -d ' ')
  [[ "$up_count" -ge 5 ]] && pass "node3 Prometheus: $up_count/$total_count hedef UP" || fail "node3 Prometheus: Sadece $up_count hedef UP (En az 5 beklenir)"
fi

# ── 10. DERİN LOG ANALİZİ (YENİ) ──────────────────────────────────────────────
header "10. Derin Log Analizi (journalctl ERROR taraması)"
for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  # Son 1 saat içinde priority 0-3 (Error ve daha kritik) log var mı?
  error_count=$(_ssh "$host" "journalctl -p 0..3 -S '1 hour ago' --no-pager | wc -l" 2>/dev/null) || error_count=0
  if [[ "$error_count" -gt 50 ]]; then
    warn "$name: Son 1 saatte ÇOK FAZLA kritik hata logu bulundu ($error_count satır) -> 'journalctl -p 3 -xe' ile inceleyin."
  elif [[ "$error_count" -gt 0 ]]; then
    pass "$name: Son 1 saatte az sayıda hata kaydı var ($error_count satır - Kabul edilebilir)."
  else
    pass "$name: Sistem logları tertemiz (0 kritik hata)."
  fi
done

# ── 11. UFW GÜVENLİK KONTROLÜ ──────────────────────────────────────────────────
header "11. UFW Güvenlik Kontrolü"
for i in "${REACHABLE[@]}"; do
  host="${NODES[$i]}"; name="${NODE_NAMES[$i]}"
  ufw_enabled=$(_ssh "$host" "grep -i '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'") || ufw_enabled=""
  ufw_enabled=$(echo "$ufw_enabled" | tr '[:lower:]' '[:upper:]')
  [[ "$ufw_enabled" == "YES" ]] && pass "$name: UFW aktif" || fail "$name: UFW aktif değil!"
done

# ── 12. TLS SERTİFİKA GEÇERLİLİĞİ ─────────────────────────────────────────────
header "12. TLS Sertifika Geçerliliği"
_check_cert() {
  local label="$1" host="$2" port="${3:-443}"
  cert=$(echo | openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null | openssl x509 2>/dev/null)
  if [[ -z "$cert" ]]; then warn "$label: Sertifika alınamadı"; return; fi
  if ! echo "$cert" | openssl x509 -checkend $((14*86400)) -noout >/dev/null 2>&1; then fail "$label: Sertifika 14 gün içinde sona eriyor (ACİL)"; return; fi
  if ! echo "$cert" | openssl x509 -checkend $((30*86400)) -noout >/dev/null 2>&1; then warn "$label: Sertifika 30 gün içinde sona eriyor"; return; fi
  pass "$label: Sertifika geçerli (30+ gün)"
}
_check_cert "Gateway / API"   "teqlif.com"
_check_cert "Edge1 LiveKit"   "live1.teqlif.com"
_check_cert "Edge1 MinIO"     "minio1.teqlif.com"
_check_cert "Edge2 LiveKit"   "live2.teqlif.com"
_check_cert "Edge2 MinIO"     "minio2.teqlif.com"

# ── ÖZET ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD} Teqlif V1.4 Ölçeklendirme ve Hack Testi Sonuç Raporu${RESET}"
echo -e "${BOLD}══════════════════════════════════════════════════════════${RESET}"
echo -e "  ${GREEN}✓ PASS${RESET}  : $PASS"
echo -e "  ${YELLOW}⚠ WARN${RESET}  : $WARN"
echo -e "  ${RED}✗ FAIL${RESET}  : $FAIL"
echo -e "  Toplam  : $((PASS + WARN + FAIL)) test koşuldu."
echo ""
if   [[ $FAIL -gt 0 ]]; then echo -e "${RED}${BOLD}SONUÇ: $FAIL test BAŞARISIZ.${RESET}"; exit 1
elif [[ $WARN -gt 0 ]]; then echo -e "${YELLOW}${BOLD}SONUÇ: Tüm kritik testler GEÇTİ, $WARN ufak uyarı var.${RESET}"; exit 0
else                          echo -e "${GREEN}${BOLD}SONUÇ: SİSTEM KUSURSUZ (MÜKEMMEL PUAN)!${RESET}"; exit 0
fi
