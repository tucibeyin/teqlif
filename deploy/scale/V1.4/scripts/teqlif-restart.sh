#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/teqlif-restart.sh
set -euo pipefail

# ── Renkler ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

SEP="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Repo Dizini ──
REPO_DIR="/var/www/teqlif.com"

# ── Node Rolleri ──
declare -A NODE_ROLES
NODE_ROLES=(
  ["gateway"]="EDGE PROXY"
  ["node1"]="EDGE 1"
  ["node2"]="AI PROXY 1"
  ["node3"]="MONITOR & STAGING"
  ["node4"]="EDGE 2"
  ["node5"]="CORE"
)

# ── Topoloji (Hardcoded Services) ──
declare -A NODE_SERVICES
NODE_SERVICES=(
    # Sıralama prensibi: veri katmanı → medya/depolama → uygulama → izleme → exporter
    ["gateway"]="nginx node_exporter promtail"
    ["node1"]="redis-server livekit minio edge-metrics-agent node_exporter promtail"
    ["node2"]="teqlif-ai-proxy cf-failover node_exporter promtail"
    ["node3"]="postgresql redis-server clickhouse-server livekit minio edge-metrics-agent teqlif-ai-proxy teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging prometheus loki grafana-server alertmanager node_exporter promtail"
    ["node4"]="redis-server livekit minio edge-metrics-agent node_exporter promtail"
    ["node5"]="postgresql redis-server clickhouse-server teqlif teqlif-worker teqlif-worker-critical node_exporter promtail"
)

# ── Production'da restart edilmeyecek servisler (durum tablosunda görünür) ──
# Node5: redis-server/minio/livekit uçuşta olduğundan restart skip edilir.
# Node3: monitoring stack restart edilirse sistem kısa süre kör kalır; skip edilir.
declare -A NODE_SKIP_RESTART
NODE_SKIP_RESTART=(
    ["node1"]="minio livekit"
    ["node4"]="minio livekit"
    ["node5"]="redis-server minio livekit"
    ["node3"]="prometheus loki grafana-server alertmanager"
)

is_skip_restart() {
    local svc="$1"
    local skip_list="${NODE_SKIP_RESTART[$NODE]:-}"
    [[ -z "$skip_list" ]] && return 1
    for s in $skip_list; do
        [[ "$s" == "$svc" ]] && return 0
    done
    return 1
}

# ── Node Tespiti ──
detect_node() {
    local wg_ip
    if wg_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)10\.10\.0\.\d+'); then
        case "$wg_ip" in
            "10.10.0.2") echo "gateway"; return 0 ;;
            "10.10.0.1") echo "node1"; return 0 ;;
            "10.10.0.3") echo "node2"; return 0 ;;
            "10.10.0.4") echo "node3"; return 0 ;;
            "10.10.0.5") echo "node5"; return 0 ;;
            "10.10.0.6") echo "node4"; return 0 ;;
        esac
    fi
    if systemctl is-active nginx &>/dev/null && ! ip link show wg0 &>/dev/null; then
        echo "gateway"; return 0
    fi
    echo "unknown"
}

NODE=$(detect_node)

if [[ "$NODE" == "unknown" ]]; then
    echo -e "${RED}${BOLD}Hata: Bu sunucunun V1.4 rolü tespit edilemedi.${RESET}" >&2
    exit 1
fi

SERVICES_LIST=${NODE_SERVICES[$NODE]:-}
if [[ -z "$SERVICES_LIST" ]]; then
    echo -e "${RED}${BOLD}Hata: $NODE için servis tanımı bulunamadı.${RESET}" >&2
    exit 1
fi

NODE_ROLE="${NODE_ROLES[$NODE]:-$NODE}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── format_uptime ──
format_uptime() {
  local start_time=$1
  [[ -z "$start_time" || "$start_time" == "N/A" ]] && echo "-" && return
  local start_epoch
  start_epoch=$(date -d "$start_time" +%s 2>/dev/null) || start_epoch=""
  [[ -z "$start_epoch" ]] && echo "-" && return
  local diff=$(( $(date +%s) - start_epoch ))
  [[ $diff -lt 0 ]] && echo "-" && return
  local d=$((diff / 86400))
  local h=$(( (diff % 86400) / 3600 ))
  local m=$(( (diff % 3600) / 60 ))
  local s=$((diff % 60))
  if [[ $d -gt 0 ]]; then   printf "%dd %02dh %02dm" $d $h $m
  elif [[ $h -gt 0 ]]; then printf "%dh %02dm %02ds" $h $m $s
  else                       printf "%02dm %02ds" $m $s
  fi
}

# ════════════════════════════════════════════════════════════════
# Header
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "$SEP"
echo -e "${BOLD}${CYAN}  ${NODE}  ·  ${NODE_ROLE}  ·  ${TIMESTAMP}${RESET}"
echo -e "$SEP"
echo ""

# ── [1/2] git pull ──
echo -e "${BOLD}[1/2] git pull${RESET}"
if [[ -n "$REPO_DIR" && -d "$REPO_DIR/.git" ]]; then
  REPO_OWNER=$(stat -c '%U' "$REPO_DIR/.git" 2>/dev/null || echo "")
  if [[ -n "$REPO_OWNER" && "$REPO_OWNER" != "root" && "$(id -u)" -eq 0 ]]; then
    git_result=$(sudo -u "$REPO_OWNER" git -C "$REPO_DIR" pull --ff-only 2>&1)
  else
    git_result=$(git -C "$REPO_DIR" pull --ff-only 2>&1)
  fi
  git_exit=$?
  echo -e "  $(echo "$git_result" | tail -1)"
  if [[ $git_exit -ne 0 ]]; then
    echo -e "  ${RED}${BOLD}HATA: git pull başarısız — servisler restart edilmedi.${RESET}" >&2
    echo -e "  ${YELLOW}Manuel düzelt: cd $REPO_DIR && git status${RESET}" >&2
    exit 1
  fi
else
  echo -e "  ${YELLOW}Atlandı — repo dizini tespit edilemedi.${RESET}"
fi
echo ""

# ── [2/2] servisler ──
echo -e "${BOLD}[2/2] servisler yeniden başlatılıyor${RESET}"
for svc in $SERVICES_LIST; do
  printf "  "
  if is_skip_restart "$svc"; then
    echo -e "${YELLOW}⊘${RESET}  ${svc}  ${YELLOW}← SKIP${RESET}"
  elif sudo systemctl restart "$svc" 2>/dev/null; then
    echo -e "${GREEN}✓${RESET}  ${svc}"
  else
    echo -e "${RED}✗${RESET}  ${svc}  ${RED}← journalctl -u ${svc}${RESET}"
  fi
done

# Servislerin oturması için dinamik bekleme (en fazla 10 saniye)
sleep 1
for ((i=1; i<=10; i++)); do
  _waiting=0
  for svc in $SERVICES_LIST; do
    is_skip_restart "$svc" && continue
    _state=$(systemctl show -p ActiveState "$svc" 2>/dev/null | cut -d= -f2)
    if [[ "$_state" != "active" && "$_state" != "failed" ]]; then
      _waiting=1; break
    fi
  done
  [[ $_waiting -eq 0 ]] && break
  sleep 1
done
echo ""

# ════════════════════════════════════════════════════════════════
# Servis Durum Tablosu
# ════════════════════════════════════════════════════════════════
echo -e "$SEP"
echo -e "${BOLD}${CYAN}  SERVİS DURUMU${RESET}"
echo -e "$SEP"
printf "  ${BOLD}%-32s %-12s %-8s %-10s %s${RESET}\n" "SERVİS" "DURUM" "PID" "RAM" "UPTIME"
echo -e "  ─────────────────────────────────────────────────────────────"

for svc in $SERVICES_LIST; do
  target_svc="$svc"
  if [[ "$svc" == "postgresql" ]]; then
    _pg=$(systemctl list-units "postgresql@*" --no-legend --state=active 2>/dev/null | awk '{print $1}' | head -n 1)
    [[ -n "${_pg:-}" ]] && target_svc="$_pg"
  fi

  raw=$(systemctl show -p ActiveState,MainPID,MemoryCurrent,ActiveEnterTimestamp "$target_svc" 2>/dev/null)
  _state=$(echo "$raw" | grep "^ActiveState=" | cut -d= -f2)
  _pid=$(echo "$raw" | grep "^MainPID=" | cut -d= -f2)
  _mem=$(echo "$raw" | grep "^MemoryCurrent=" | cut -d= -f2)
  _ts=$(echo "$raw" | grep "^ActiveEnterTimestamp=" | cut -d= -f2-)

  _dpid="-"; _dmem="-"; _duptime="-"
  [[ "$_pid" != "0" && -n "${_pid:-}" ]] && _dpid="$_pid"
  if [[ "${_mem:-}" != "[not set]" && -n "${_mem:-}" && "${_mem:-}" =~ ^[0-9]+$ ]]; then
    _dmem="$((_mem / 1024 / 1024)) MB"
  fi
  [[ "$_state" == "active" ]] && _duptime=$(format_uptime "${_ts:-}")

  case "$_state" in
    "active")    printf "  %-32s ${GREEN}%-12s${RESET} %-8s %-10s %s\n" "$svc" "● ACTIVE"   "$_dpid" "$_dmem" "$_duptime" ;;
    "failed")    printf "  %-32s ${RED}%-12s${RESET} %-8s %-10s %s\n"   "$svc" "○ FAILED"   "$_dpid" "$_dmem" "$_duptime" ;;
    "inactive")  printf "  %-32s ${YELLOW}%-12s${RESET} %-8s %-10s %s\n" "$svc" "○ INACTIVE" "$_dpid" "$_dmem" "$_duptime" ;;
    "activating") printf "  %-32s ${CYAN}%-12s${RESET} %-8s %-10s %s\n"  "$svc" "↻ STARTING" "$_dpid" "$_dmem" "$_duptime" ;;
    *)           printf "  %-32s ${YELLOW}%-12s${RESET} %-8s %-10s %s\n" "$svc" "○ UNKNOWN"  "$_dpid" "$_dmem" "$_duptime" ;;
  esac
done

echo ""
echo -e "$SEP"
if systemctl is-failed $SERVICES_LIST &>/dev/null; then
  echo -e "${RED}${BOLD}  ✗  Bazı servisler başlatılamadı. Tabloyu inceleyin.${RESET}"
else
  echo -e "${GREEN}${BOLD}  ✓  Tüm servisler aktif.${RESET}"
fi
echo -e "$SEP"
echo ""
