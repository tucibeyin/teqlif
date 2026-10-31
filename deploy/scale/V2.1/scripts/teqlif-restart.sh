#!/bin/bash
# /usr/local/sbin/teqlif-restart
#
# Her node'da ne yapılır:
#   node1  — git pull → pip sync → servis güncelle → alembic + sync → teqlif + workers restart
#   node2  — git pull (backup node, uygulama yok)
#   node3  — git pull; --livekit ile LiveKit restart (aktif yayınları keser)
#   node4  — git pull; --livekit ile LiveKit restart (aktif yayınları keser)
#   node5  — git pull → pip sync → servis güncelle → alembic + sync → teqlif-staging + workers restart
#   node6  — git pull → teqlif-ai-proxy restart
#
# Kullanım:
#   sudo teqlif-restart              # normal restart
#   sudo teqlif-restart --livekit    # node3/node4'te LiveKit'i de restart et

set -uo pipefail

REPO=/var/www/teqlif.com
NODE=$(hostname -s)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}▶ [teqlif-restart]${NC} $*"; }
warn() { echo -e "${YELLOW}⚠ [teqlif-restart]${NC} $*"; }
err()  { echo -e "${RED}✖ [teqlif-restart]${NC} $*" >&2; exit 1; }

RESTART_LIVEKIT=false
FORCE_AGENT_SYNC=false
for arg in "$@"; do
  case $arg in
    --livekit)           RESTART_LIVEKIT=true ;;
    --force-agent-sync)  FORCE_AGENT_SYNC=true ;;
    *) err "Bilinmeyen flag: $arg  (kullanım: teqlif-restart [--livekit] [--force-agent-sync])" ;;
  esac
done

# ── 1. git pull ───────────────────────────────────────────────────────────────
log "git pull — $REPO"
cd "$REPO"
BEFORE=$(git rev-parse HEAD)
su -s /bin/bash tucibeyin -c "cd $REPO && git pull --ff-only" 2>&1 || err "git pull başarısız — önce merge conflict'i çöz"
AFTER=$(git rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
  log "Kod değişmemiş ($(git rev-parse --short HEAD))"
else
  log "Güncellendi: $(git rev-parse --short "$BEFORE")..$(git rev-parse --short "$AFTER")"
  git log --oneline "$BEFORE..$AFTER"
fi

# ── 2. pip sync (requirements değişmişse) ─────────────────────────────────────
pip_sync() {
  local reqs="$REPO/backend/requirements.txt"
  if [ "$BEFORE" != "$AFTER" ] && git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null | grep -q "requirements.txt"; then
    log "requirements.txt değişti — pip install..."
    "$REPO/.venv/bin/pip" install -q -r "$reqs"
  fi
}

# ── 2b. agent sync (deploy/scale/V2.1/teqlif-agent/ veya cluster.yaml değişmişse) ─
agent_sync() {
  local agent_src="$REPO/deploy/scale/V2.1/teqlif-agent"
  local cluster_src="$REPO/deploy/scale/V2.1/cluster.yaml"
  local agent_dst="/opt/teqlif-agent"

  local changed=false
  if $FORCE_AGENT_SYNC; then
    changed=true
  elif [ "$BEFORE" != "$AFTER" ]; then
    git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null \
      | grep -qE '^deploy/scale/V2\.1/(teqlif-agent/|cluster\.yaml)' \
      && changed=true
  fi
  # Double-pull koruması: BEFORE==AFTER olsa bile deploy hash farklıysa sync yap
  if ! $changed && [ -d "$agent_dst" ]; then
    local deployed_hash=""
    [ -f "$agent_dst/.git_hash" ] && deployed_hash=$(cat "$agent_dst/.git_hash")
    [ "$deployed_hash" != "$AFTER" ] && changed=true
    # Restart script'in kendisi de farklıysa sync gerekir
    local self_src="$REPO/deploy/scale/V2.1/scripts/teqlif-restart.sh"
    if ! diff -q "$self_src" /usr/local/sbin/teqlif-restart >/dev/null 2>&1; then
      changed=true
    fi
  fi

  # schedule.yaml her zaman sync et — code değişikliğinden bağımsız
  local sched_src="$REPO/deploy/scale/V2.1/schedule.yaml"
  if ! diff -q "$sched_src" "$agent_dst/schedule.yaml" >/dev/null 2>&1; then
    cp "$sched_src" "$agent_dst/schedule.yaml"
    chown teqlif-agent:teqlif-agent "$agent_dst/schedule.yaml"
    changed=true
    log "schedule.yaml güncellendi → /opt/teqlif-agent/schedule.yaml"
  fi

  if $changed; then
    log "teqlif-agent kodu güncellendi — /opt/teqlif-agent sync ediliyor..."
    rsync -a --exclude '__pycache__' --exclude '*.pyc' \
          --exclude 'configs/' --exclude 'setup/' \
          "$agent_src/" "$agent_dst/"
    cp "$cluster_src" "$agent_dst/cluster.yaml"
    echo "$AFTER" > "$agent_dst/.git_hash"
    chown -R teqlif-agent:teqlif-agent "$agent_dst"
    systemctl restart teqlif-agent.service
    log "teqlif-agent yeniden başlatıldı"
    # Script kendini de günceller — sonraki çalışmada yeni versiyon kullanılır
    local self_src="$REPO/deploy/scale/V2.1/scripts/teqlif-restart.sh"
    if ! diff -q "$self_src" /usr/local/sbin/teqlif-restart >/dev/null 2>&1; then
      cp "$self_src" /usr/local/sbin/teqlif-restart.new
      chmod 755 /usr/local/sbin/teqlif-restart.new
      mv /usr/local/sbin/teqlif-restart.new /usr/local/sbin/teqlif-restart
      log "teqlif-restart scripti güncellendi (sonraki çalıştırmada aktif)"
    fi
  fi
}

# ── sync_nginx: nginx conf.d dosyaları değiştiyse /etc/nginx/conf.d/ güncelle ─
# nginx -t başarısız olursa backup'tan geri döner, restart iptal edilir.
sync_nginx() {
  local node_dir="$1"
  local conf_dir="$node_dir/resources/nginx/conf.d"
  [ -d "$conf_dir" ] || return 0
  local reloaded=""
  for conf in "$conf_dir"/*.conf; do
    [ -f "$conf" ] || continue
    local fname dst
    fname=$(basename "$conf")
    dst="/etc/nginx/conf.d/$fname"
    if ! diff -q "$conf" "$dst" > /dev/null 2>&1; then
      [ -f "$dst" ] && cp "$dst" "${dst}.bak"
      cp "$conf" "$dst"
      log "Nginx config güncellendi: $fname"
      reloaded="yes"
    fi
  done
  if [ -n "$reloaded" ]; then
    if ! systemctl is-active nginx > /dev/null 2>&1; then
      # nginx durdurulmuş (DR-hazırlık modu) — config kaydedildi, test runbook'a bırakıldı
      log "Nginx config güncellendi (nginx şu an durmuş — test ve reload atlandı)"
    elif nginx -t 2>/dev/null; then
      systemctl reload nginx
      log "nginx reload tamamlandı"
    else
      warn "nginx -t başarısız — backup'tan geri yükleniyor..."
      for conf in "$conf_dir"/*.conf; do
        [ -f "$conf" ] || continue
        local fname dst
        fname=$(basename "$conf")
        dst="/etc/nginx/conf.d/$fname"
        [ -f "${dst}.bak" ] && cp "${dst}.bak" "$dst" || rm -f "$dst"
      done
      nginx -t 2>/dev/null && systemctl reload nginx
      err "Nginx config hatası — restart iptal edildi"
    fi
  fi
  return 0
}

# ── sync_services: servis dosyaları değiştiyse /etc/systemd/system/ güncelle ─
sync_services() {
  local node_dir="$1"
  local reloaded=""
  for svc in "$node_dir/systemd/"*.service; do
    [ -f "$svc" ] || continue
    local fname
    fname=$(basename "$svc")
    if ! diff -q "$svc" "/etc/systemd/system/$fname" > /dev/null 2>&1; then
      cp "$svc" "/etc/systemd/system/$fname"
      log "Servis dosyası güncellendi: $fname"
      reloaded="yes"
    fi
  done
  [ -n "$reloaded" ] && systemctl daemon-reload && log "systemctl daemon-reload tamamlandı"
  return 0
}

# ── sync_scripts: resources/scripts/ altındaki shell scriptleri /usr/local/bin/'e sync et ─
sync_scripts() {
  local node_dir="$1"
  local scripts_dir="$node_dir/resources/scripts"
  [ -d "$scripts_dir" ] || return 0
  for script in "$scripts_dir"/*.sh; do
    [ -f "$script" ] || continue
    local fname dst
    fname=$(basename "$script")
    dst="/usr/local/bin/$fname"
    if ! diff -q "$script" "$dst" > /dev/null 2>&1; then
      cp "$script" "$dst"
      chmod +x "$dst"
      log "Script güncellendi: $fname → /usr/local/bin/"
    fi
  done
  return 0
}

# ── alembic_and_sync: migration + veri sync (deployment anında, her restart'ta değil) ─
alembic_and_sync() {
  local env_file="$1"
  log "alembic upgrade head..."
  systemd-run \
    --uid=tucibeyin --gid=tucibeyin \
    --wait --collect \
    --working-directory="$REPO/backend" \
    --property="EnvironmentFile=$env_file" \
    -- "$REPO/.venv/bin/alembic" upgrade head \
    || err "alembic upgrade başarısız — restart iptal edildi"
  log "sync_main.py (kategori/lokasyon/i18n/feed cache)..."
  systemd-run \
    --uid=tucibeyin --gid=tucibeyin \
    --wait --collect \
    --working-directory="$REPO/backend" \
    --property="EnvironmentFile=$env_file" \
    -- "$REPO/.venv/bin/python" scripts/sync_main.py \
    || warn "sync_main.py hata verdi — devam ediliyor"
}

# ── 3. node'a göre restart ────────────────────────────────────────────────────
case "$NODE" in

  node1)
    pip_sync
    agent_sync
    sync_services "$REPO/deploy/scale/V2.1/node1"
    sync_nginx "$REPO/deploy/scale/V2.1/node1"
    alembic_and_sync /project/teqlif/config/.env.production
    log "teqlif.service yeniden başlatılıyor..."
    systemctl restart teqlif.service
    log "teqlif.service aktif — workerlar başlatılıyor..."
    systemctl restart teqlif-worker.service teqlif-worker-critical.service teqlif-worker-video.service
    log "Tüm servisler hazır"
    echo ""
    log "Son loglar:"
    journalctl -u teqlif.service -n 20 --no-pager
    ;;

  node2)
    agent_sync
    sync_services "$REPO/deploy/scale/V2.1/node2"
    sync_scripts "$REPO/deploy/scale/V2.1/node2"
    log "node2 — backup node, uygulama servisi yok. git pull tamamlandı."
    ;;

  node3|node4)
    agent_sync
    if $RESTART_LIVEKIT; then
      warn "LiveKit yeniden başlatılıyor — aktif yayınlar kesilecek!"
      systemctl restart teqlif-livekit.service
      log "teqlif-livekit.service hazır"
      journalctl -u teqlif-livekit.service -n 20 --no-pager
    else
      log "$NODE — LiveKit restart için: sudo teqlif-restart --livekit"
      log "git pull tamamlandı, servis restart edilmedi."
    fi
    ;;

  node5)
    pip_sync
    agent_sync
    sync_services "$REPO/deploy/scale/V2.1/node5"
    sync_nginx "$REPO/deploy/scale/V2.1/node5"
    alembic_and_sync /project/teqlif/config/.env.staging
    log "teqlif-staging.service yeniden başlatılıyor..."
    systemctl restart teqlif-staging.service
    log "teqlif-staging.service aktif — worker'lar başlatılıyor..."
    systemctl restart teqlif-worker-staging.service teqlif-worker-critical-staging.service teqlif-worker-video-staging.service
    log "Tüm servisler hazır"
    echo ""
    log "Son loglar:"
    journalctl -u teqlif-staging.service -n 20 --no-pager
    ;;

  node6)
    agent_sync
    log "teqlif-ai-proxy.service yeniden başlatılıyor..."
    systemctl restart teqlif-ai-proxy.service
    log "teqlif-ai-proxy.service hazır"
    journalctl -u teqlif-ai-proxy.service -n 20 --no-pager
    ;;

  nodeMonitor)
    agent_sync
    log "nodeMonitor — izleme node'u, uygulama servisi yok. git pull tamamlandı."
    ;;

  *)
    err "Bilinmeyen hostname: $NODE"
    ;;
esac
