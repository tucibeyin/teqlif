#!/usr/bin/env bash
# deploy/scale/V1.4/node2/resources/bootstrap_node2.sh
# node2 (AI Proxy 1)
# Idempotent: tekrar çalıştırmak güvenli. V1.4 Generic Pathing kuralına uyar.
set -euo pipefail

RESOURCES_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$RESOURCES_DIR/../../../../.." && pwd)"
VENV="$REPO/venv"
NODE_EXPORTER_VERSION="1.8.2"
PROMTAIL_VERSION="3.0.0"

echo "==> REPO Root: $REPO"
# ── Repo Sahipliği Düzeltmesi ────────────────────────────────────────────────
# sudo ile çalıştırıldığında repo dosyaları root'a geçebilir; tümünü düzelt.
REPO_OWNER=$(stat -c '%U' "$(dirname "$REPO")" 2>/dev/null || echo "tucibeyin")
if [[ "$(stat -c '%U' "$REPO" 2>/dev/null)" == "root" ]]; then
  echo "==> Repo dizin sahipliği $REPO_OWNER'a düzeltiliyor..."
  sudo chown -R "$REPO_OWNER:$REPO_OWNER" "$REPO"
fi

echo "==> apt paketleri..."
sudo apt update -q
sudo apt install -y ufw python3.13-venv wireguard unzip rsync fail2ban build-essential ffmpeg

echo "==> Grup üyelikleri..."
sudo usermod -aG systemd-journal tucibeyin 2>/dev/null || true
sudo usermod -aG adm tucibeyin 2>/dev/null || true

# ── WireGuard (Mesh Network) ──────────────────────────────────────────────────
echo "==> WireGuard ağı (Mesh) yapılandırılıyor..."
if [[ -f "$RESOURCES_DIR/wg0.conf" ]]; then
  sudo mkdir -p /etc/wireguard
  if [[ ! -f "/etc/wireguard/wg0.conf" ]]; then
    if [[ ! -f "/etc/wireguard/wg0.conf" ]]; then sudo cp "$RESOURCES_DIR/wg0.conf" /etc/wireguard/wg0.conf; else echo "Mevcut wg0.conf korundu."; fi
    sudo chmod 600 /etc/wireguard/wg0.conf
  else
    echo "==> Mevcut wg0.conf bulundu, üzerine yazılmıyor (Private Key korundu)."
  fi
  
  if grep -q "<NODE2_PRIVATE_KEY>" /etc/wireguard/wg0.conf; then
    echo "==> Otomatik WireGuard Anahtarı Üretiliyor..."
    sudo apt-get install -y -q wireguard-tools
    PRIV_KEY=$(wg genkey)
    PUB_KEY=$(echo "$PRIV_KEY" | wg pubkey)
    sudo sed -i "s|<NODE2_PRIVATE_KEY>|$PRIV_KEY|" /etc/wireguard/wg0.conf
    echo "=================================================================="
    echo " 🚨 DİKKAT: Node2 için YENİ WireGuard Public Key üretildi! 🚨"
    echo " PUBLIC KEY: \"$PUB_KEY\""
    echo " Lütfen bu anahtarı diğer sunucularda wg0.conf içindeki Node2 [Peer] kısmına kopyalayın!"
    echo "=================================================================="
  fi
  
  sudo systemctl enable --now wg-quick@wg0 || echo "Uyarı: WireGuard başlatılamadı."
else
  echo "Uyarı: wg0.conf bulunamadı, WireGuard ağı kurulamadı!"
fi

echo "==> UFW (Güvenlik Duvarı) Worker kuralları uygulanıyor..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 51820/udp    # WireGuard (Mesh)
sudo ufw allow in on wg0 to any 2>/dev/null || echo "Uyarı: wg0 henüz aktif olmayabilir."
sudo ufw --force enable

echo "==> Python venv @ $VENV..."
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install --upgrade pip -q
"$VENV/bin/pip" install torch --index-url https://download.pytorch.org/whl/cpu -q
"$VENV/bin/pip" install -r "$RESOURCES_DIR/node2_production_requirements.txt"

echo "==> Log dizinleri..."
sudo mkdir -p /var/log/teqlif /var/lib/promtail
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" /var/log/teqlif /var/lib/promtail
if [[ ! -L "$REPO/logs" ]]; then
  ln -s /var/log/teqlif "$REPO/logs"
fi

echo "==> node_exporter & promtail..."
if ! /usr/local/bin/node_exporter --version 2>&1 | grep -q "$NODE_EXPORTER_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | tar xz -C "$TMP"
  sudo mv "$TMP/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf "$TMP"
fi

if ! /usr/local/bin/promtail --version 2>&1 | grep -q "$PROMTAIL_VERSION" 2>/dev/null; then
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/promtail.zip" "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
  unzip -q "$TMP/promtail.zip" -d "$TMP"
  sudo mv "$TMP/promtail-linux-amd64" /usr/local/bin/promtail
  sudo chmod +x /usr/local/bin/promtail
  rm -rf "$TMP"
fi

echo "==> systemd servisleri (V1.4)..."
SERVICES=(teqlif-ai-proxy cf-failover node_exporter promtail)

for svc in "${SERVICES[@]}"; do
  if [[ -f "$REPO/deploy/scale/V1.4/node2/systemd/${svc}.service" ]]; then
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$REPO/backend/.env.production|g" \
      "$REPO/deploy/scale/V1.4/node2/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  elif [[ -f "$REPO/deploy/scale/V1.4/node1/systemd/${svc}.service" ]]; then
    sudo sed "s|EnvironmentFile=.*|EnvironmentFile=$REPO/backend/.env.production|g" \
      "$REPO/deploy/scale/V1.4/node1/systemd/${svc}.service" > "/tmp/${svc}.service"
    sudo mv "/tmp/${svc}.service" /etc/systemd/system/
  fi
done

sudo systemctl daemon-reload
for svc in "${SERVICES[@]}"; do
  sudo systemctl enable "$svc" 2>/dev/null || true
done

# ── Otomatik .env Şablonu ─────────────────────────────────────────────────────
echo "==> .env.production şablonu kopyalanıyor..."
mkdir -p "$REPO/backend"
if [[ ! -f "$REPO/backend/.env.production" ]]; then
  cp "$RESOURCES_DIR/.env.production.template" "$REPO/backend/.env.production"
fi

# ── Temizlik (Clean State) ────────────────────────────────────────────────────
echo "==> Kurulum artıkları ve önbellek temizleniyor..."
sudo install -m 755 "$REPO/deploy/scale/V1.4/scripts/teqlif-restart.sh" /usr/local/bin/teqlif-restart
sudo apt-get autoremove -y -q
sudo apt-get clean -q
"$VENV/bin/pip" cache purge 2>/dev/null || true

echo "=============================================="
echo " Node2 (AI Proxy 1) Bootstrap Tamamlandı!"
echo " Lütfen .env.production dosyasını API anahtarlarıyla (GROQ, GEMINI) doldurun."
echo "=============================================="

echo " "
echo "==> Servis Durumları (Son Kontrol):"
bash "$RESOURCES_DIR/node2_services.sh" status || true
echo " "
