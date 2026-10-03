#!/usr/bin/env bash
# teqlif-agent kurulum scripti
# Kullanım: sudo bash setup_node.sh <node_id>
# Örnek:    sudo bash setup_node.sh node1
set -euo pipefail

NODE_ID="${1:?'Kullanım: sudo bash setup_node.sh <node_id>'}"
AGENT_DIR="/opt/teqlif-agent"
DATA_DIR="/var/lib/teqlif-agent"
LOG_DIR="/var/log/teqlif-agent"
CFG_DIR="/etc/teqlif-agent"
REC_DIR="/var/recordings"
AGENT_USER="teqlif-agent"
REPO_AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> teqlif-agent kurulum: $NODE_ID"

# ── 1. Kullanıcı ──────────────────────────────────────────────────────────────
if ! id "$AGENT_USER" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$AGENT_USER"
    echo "    Kullanıcı oluşturuldu: $AGENT_USER"
fi

# ── 2. Dizinler ───────────────────────────────────────────────────────────────
mkdir -p "$AGENT_DIR" "$DATA_DIR" "$LOG_DIR" "$CFG_DIR" "$REC_DIR/raw" "$REC_DIR/encoded"
chown "$AGENT_USER:$AGENT_USER" "$DATA_DIR" "$LOG_DIR" "$REC_DIR/raw" "$REC_DIR/encoded"
chmod 750 "$CFG_DIR"

# ── 3. Python venv ────────────────────────────────────────────────────────────
if [ ! -f "$AGENT_DIR/venv/bin/python" ]; then
    python3 -m venv "$AGENT_DIR/venv"
    echo "    venv oluşturuldu."
fi
"$AGENT_DIR/venv/bin/pip" install --quiet --upgrade pip
"$AGENT_DIR/venv/bin/pip" install --quiet \
    aiohttp aiosqlite pyyaml asyncpg aioredis

echo "    Python bağımlılıkları kuruldu."

# ── 4. Kod kopyalama ──────────────────────────────────────────────────────────
rsync -a --exclude '__pycache__' --exclude '*.pyc' \
    --exclude 'configs/' --exclude 'setup/' \
    "$REPO_AGENT_DIR/" "$AGENT_DIR/"
chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_DIR"
echo "    Kod kopyalandı: $AGENT_DIR"

# ── 5. Config ─────────────────────────────────────────────────────────────────
CFG_SRC="$REPO_AGENT_DIR/configs/${NODE_ID}.yaml"
if [ ! -f "$CFG_SRC" ]; then
    echo "HATA: Config bulunamadı: $CFG_SRC"
    exit 1
fi

install -m 640 -o "$AGENT_USER" -g "$AGENT_USER" "$CFG_SRC" "$CFG_DIR/config.yaml"
echo "    Config kuruldu: $CFG_DIR/config.yaml"

# ── 6. env dosyası (Telegram + PG DSN) ───────────────────────────────────────
if [ ! -f "$CFG_DIR/env" ]; then
    cat > "$CFG_DIR/env" << 'ENV'
# teqlif-agent ortam değişkenleri
# Bu dosyayı doldur: AGENT_CONFIG, PG_DSN, TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
AGENT_CONFIG=/etc/teqlif-agent/config.yaml
PG_DSN=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
ENV
    chmod 640 "$CFG_DIR/env"
    chown "$AGENT_USER:$AGENT_USER" "$CFG_DIR/env"
    echo "    env şablonu oluşturuldu: $CFG_DIR/env — lütfen doldur!"
else
    echo "    env zaten mevcut, dokunulmadı."
fi

# ── 7. Sudo kuralı (systemd kontrol) ─────────────────────────────────────────
SUDOERS_FILE="/etc/sudoers.d/teqlif-agent"
if [ ! -f "$SUDOERS_FILE" ]; then
    cat > "$SUDOERS_FILE" << 'SUDOERS'
# teqlif-agent self-healer: sadece teqlif servislerini kontrol edebilir
teqlif-agent ALL=(ALL) NOPASSWD: \
    /bin/systemctl start teqlif-*, \
    /bin/systemctl restart teqlif-*, \
    /bin/systemctl reset-failed teqlif-*, \
    /bin/systemctl start livekit, \
    /bin/systemctl restart livekit, \
    /bin/systemctl reset-failed livekit
SUDOERS
    chmod 440 "$SUDOERS_FILE"
    echo "    Sudoers kuralı eklendi."
fi

# ── 8. Systemd servis ─────────────────────────────────────────────────────────
install -m 644 "$REPO_AGENT_DIR/setup/teqlif-agent.service" \
    /etc/systemd/system/teqlif-agent.service
systemctl daemon-reload
systemctl enable teqlif-agent
echo "    Systemd servisi kuruldu ve etkinleştirildi."

# ── 9. Başlat ─────────────────────────────────────────────────────────────────
systemctl restart teqlif-agent
sleep 2
if systemctl is-active --quiet teqlif-agent; then
    echo ""
    echo "✅ teqlif-agent çalışıyor — $NODE_ID"
    echo "   Log: journalctl -u teqlif-agent -f"
else
    echo ""
    echo "❌ teqlif-agent başlatılamadı!"
    journalctl -u teqlif-agent -n 20 --no-pager
    exit 1
fi

echo ""
echo "Son adım: $CFG_DIR/env içine PG_DSN ve Telegram bilgilerini ekle."
echo "  nano $CFG_DIR/env && systemctl restart teqlif-agent"
