#!/usr/bin/env bash
# deploy/scale/V1.4/scripts/teqlif-restart.sh
# teqlif-restart — Endüstri standardında gelişmiş servis yönetim ve raporlama aracı.

set -euo pipefail

# ── 1. Renkler ve Biçimlendirme ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── 2. Topoloji (Hardcoded Services) ──
# Her node için yönetilecek servislerin tam listesi. Yeni bir servis eklendiğinde buraya eklenmelidir.
declare -A NODE_SERVICES
NODE_SERVICES=(
    ["gateway"]="nginx node_exporter promtail"
    ["node1"]="livekit minio redis-server edge-metrics-agent node_exporter promtail"
    ["node2"]="teqlif-ai-proxy cf-failover node_exporter promtail"
    ["node3"]="teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging minio teqlif-ai-proxy prometheus loki grafana-server alertmanager node_exporter promtail redis-server postgresql"
    ["node4"]="livekit minio redis-server edge-metrics-agent node_exporter promtail"
    ["node5"]="teqlif teqlif-worker teqlif-worker-critical postgresql clickhouse-server redis-server node_exporter promtail"
)

# ── 3. Node Tespiti ──
detect_node() {
    local wg_ip
    if wg_ip=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)10\.10\.0\.\d+'); then
        case "$wg_ip" in
            "10.10.0.1") echo "node1" ; return 0 ;;
            "10.10.0.3") echo "node2" ; return 0 ;;
            "10.10.0.4") echo "node3" ; return 0 ;;
            "10.10.0.5") echo "node5" ; return 0 ;;
            "10.10.0.6") echo "node4" ; return 0 ;;
        esac
    fi

    # Gateway kontrolü
    if systemctl is-active nginx &>/dev/null && ! ip link show wg0 &>/dev/null; then
        echo "gateway"
        return 0
    fi

    echo "unknown"
}

NODE=$(detect_node)

if [[ "$NODE" == "unknown" ]]; then
    echo -e "${RED}${BOLD}Hata: Bu sunucunun V1.4 rolü (Node1-5 veya Gateway) tespit edilemedi.${RESET}" >&2
    exit 1
fi

SERVICES_LIST=${NODE_SERVICES[$NODE]:-}

if [[ -z "$SERVICES_LIST" ]]; then
    echo -e "${RED}${BOLD}Hata: $NODE için herhangi bir servis tanımı bulunamadı.${RESET}" >&2
    exit 1
fi

# ── 4. Yeniden Başlatma İşlemi ──
echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD} 🚀 TEQLIF RESTART — $NODE Servisleri Yeniden Başlatılıyor ${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════${RESET}\n"

for svc in $SERVICES_LIST; do
    echo -ne "  ${YELLOW}↻${RESET} ${BOLD}$svc${RESET} yeniden başlatılıyor... "
    if sudo systemctl restart "$svc" 2>/dev/null; then
        echo -e "${GREEN}BAŞARILI${RESET}"
    else
        echo -e "${RED}BAŞARISIZ${RESET} (journalctl -u $svc ile logları inceleyin)"
    fi
done

# Servislerin oturması için dinamik bekleme (En fazla 10 saniye)
echo -ne "\n  ${CYAN}Tüm servislerin hazır duruma gelmesi bekleniyor... ${RESET}"
for i in {1..10}; do
    activating=0
    for svc in $SERVICES_LIST; do
        state=$(systemctl show -p ActiveState "$svc" | cut -d= -f2)
        if [[ "$state" == "activating" ]]; then
            activating=1
            break
        fi
    done
    if [[ $activating -eq 0 ]]; then
        break
    fi
    echo -ne "."
    sleep 1
done
echo -e " Bitti."

# ── 5. Gelişmiş Raporlama (Dashboard) ──
echo -e "\n${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD} 📊 $NODE SERVİS DURUM RAPORU (DASHBOARD) ${RESET}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════════════${RESET}"
printf " ${BOLD}%-32s %-12s %-8s %-10s %s${RESET}\n" "SERVİS ADI" "DURUM" "PID" "RAM" "UPTIME"
echo -e " ──────────────────────────────────────────────────────────────────────"

# Süre formatlama (ActiveEnterTimestamp'tan uptime hesaplamak için)
format_uptime() {
    local start_time=$1
    if [[ -z "$start_time" || "$start_time" == "N/A" ]]; then
        echo "-"
        return
    fi
    
    local start_epoch
    start_epoch=$(date -d "$start_time" +%s 2>/dev/null) || start_epoch=""
    if [[ -z "$start_epoch" ]]; then
        echo "-"
        return
    fi
    
    local now_epoch
    now_epoch=$(date +%s)
    local diff=$((now_epoch - start_epoch))
    
    if [[ $diff -lt 0 ]]; then
        echo "-"
        return
    fi
    
    local d=$((diff / 86400))
    local h=$(( (diff % 86400) / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    local s=$((diff % 60))
    
    if [[ $d -gt 0 ]]; then
        printf "%dd %02dh %02dm" $d $h $m
    elif [[ $h -gt 0 ]]; then
        printf "%dh %02dm %02ds" $h $m $s
    else
        printf "%02dm %02ds" $m $s
    fi
}

for svc in $SERVICES_LIST; do
    # systemctl üzerinden verileri çek
    raw_status=$(systemctl show -p ActiveState,MainPID,MemoryCurrent,ActiveEnterTimestamp "$svc" 2>/dev/null)
    
    active_state=$(echo "$raw_status" | grep "^ActiveState=" | cut -d= -f2)
    main_pid=$(echo "$raw_status" | grep "^MainPID=" | cut -d= -f2)
    mem_current=$(echo "$raw_status" | grep "^MemoryCurrent=" | cut -d= -f2)
    start_timestamp=$(echo "$raw_status" | grep "^ActiveEnterTimestamp=" | cut -d= -f2-)
    
    # Varsayılan değerler
    display_status="${YELLOW}○ BİLİNMİYOR${RESET}"
    display_pid="-"
    display_mem="-"
    display_uptime="-"
    
    # Durum (Status)
    if [[ "$active_state" == "active" ]]; then
        display_status="${GREEN}● ACTIVE${RESET}  "
    elif [[ "$active_state" == "failed" ]]; then
        display_status="${RED}○ FAILED${RESET}  "
    elif [[ "$active_state" == "inactive" ]]; then
        display_status="${YELLOW}○ INACTIVE${RESET}"
    elif [[ "$active_state" == "activating" ]]; then
        display_status="${CYAN}↻ STARTING${RESET}"
    fi
    
    # PID
    if [[ "$main_pid" != "0" && -n "$main_pid" ]]; then
        display_pid="$main_pid"
    fi
    
    # Bellek (Memory)
    if [[ "$mem_current" != "[not set]" && -n "$mem_current" && "$mem_current" =~ ^[0-9]+$ ]]; then
        # Byte'ı MB'a çevir (tam sayı)
        mem_mb=$((mem_current / 1024 / 1024))
        display_mem="${mem_mb} MB"
    fi
    
    # Uptime
    if [[ "$active_state" == "active" ]]; then
        display_uptime=$(format_uptime "$start_timestamp")
    fi
    
    # Satırı bas (Hizalama ANSI renk kodlarından etkilenmemesi için durum alanı ayrı parametre olarak beslenir)
    if [[ "$active_state" == "active" ]]; then
        printf " %-32s ${GREEN}%-12s${RESET} %-8s %-10s %s\n" "$svc" "● ACTIVE" "$display_pid" "$display_mem" "$display_uptime"
    elif [[ "$active_state" == "failed" ]]; then
        printf " %-32s ${RED}%-12s${RESET} %-8s %-10s %s\n" "$svc" "○ FAILED" "$display_pid" "$display_mem" "$display_uptime"
    elif [[ "$active_state" == "inactive" ]]; then
        printf " %-32s ${YELLOW}%-12s${RESET} %-8s %-10s %s\n" "$svc" "○ INACTIVE" "$display_pid" "$display_mem" "$display_uptime"
    elif [[ "$active_state" == "activating" ]]; then
        printf " %-32s ${CYAN}%-12s${RESET} %-8s %-10s %s\n" "$svc" "↻ STARTING" "$display_pid" "$display_mem" "$display_uptime"
    else
        printf " %-32s ${YELLOW}%-12s${RESET} %-8s %-10s %s\n" "$svc" "○ UNKNOWN" "$display_pid" "$display_mem" "$display_uptime"
    fi

done

echo -e " ──────────────────────────────────────────────────────────────────────\n"

# Genel kontrol
if systemctl is-failed $SERVICES_LIST &>/dev/null; then
    echo -e "${RED}${BOLD} ⚠ DİKKAT: Bazı servisler başlatılamadı veya hatalı (FAILED). Tabloyu inceleyin.${RESET}\n"
else
    echo -e "${GREEN}${BOLD} ✓ Tüm servisler başarıyla çalışıyor.${RESET}\n"
fi
