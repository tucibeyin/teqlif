#!/bin/bash
# /usr/local/sbin/teqlif-restart
#
# Her node'da ne yapılır:
#   node1  — git pull → pip sync → teqlif + workers restart (alembic ExecStartPre'de)
#   node2  — git pull (backup node, uygulama yok)
#   node3  — git pull; --livekit ile LiveKit restart (aktif yayınları keser)
#   node4  — git pull; --livekit ile LiveKit restart (aktif yayınları keser)
#   node5  — git pull → pip sync → teqlif-staging + worker-staging restart
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
for arg in "$@"; do
  case $arg in
    --livekit) RESTART_LIVEKIT=true ;;
    *) err "Bilinmeyen flag: $arg  (kullanım: teqlif-restart [--livekit])" ;;
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
  if [ "$BEFORE" != "$AFTER" ]; then
    git diff --name-only "$BEFORE" "$AFTER" 2>/dev/null \
      | grep -qE '^deploy/scale/V2\.1/(teqlif-agent/|cluster\.yaml)' \
      && changed=true
  fi

  if $changed; then
    log "teqlif-agent kodu güncellendi — /opt/teqlif-agent sync ediliyor..."
    rsync -a --exclude '__pycache__' --exclude '*.pyc' \
          --exclude 'configs/' --exclude 'setup/' \
          "$agent_src/" "$agent_dst/"
    cp "$cluster_src" "$agent_dst/cluster.yaml"
    chown -R teqlif-agent:teqlif-agent "$agent_dst"
    systemctl restart teqlif-agent.service
    log "teqlif-agent yeniden başlatıldı"
  fi
}

# ── 3. node'a göre restart ────────────────────────────────────────────────────
case "$NODE" in

  node1)
    pip_sync
    agent_sync
    log "teqlif.service yeniden başlatılıyor (alembic ExecStartPre'de çalışır)..."
    systemctl restart teqlif.service
    log "teqlif.service aktif — workerlar başlatılıyor..."
    systemctl restart teqlif-worker.service teqlif-worker-critical.service
    log "Tüm servisler hazır"
    echo ""
    log "Son loglar:"
    journalctl -u teqlif.service -n 20 --no-pager
    ;;

  node2)
    agent_sync
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
    log "teqlif-staging.service yeniden başlatılıyor (alembic ExecStartPre'de çalışır)..."
    systemctl restart teqlif-staging.service
    log "teqlif-staging.service aktif — worker başlatılıyor..."
    systemctl restart teqlif-worker-staging.service
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

  *)
    err "Bilinmeyen hostname: $NODE"
    ;;
esac
