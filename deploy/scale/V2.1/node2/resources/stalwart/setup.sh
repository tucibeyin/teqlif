#!/bin/bash
# Stalwart Mail Server — node2 kurulum scripti
# Çalıştırma: sudo bash setup.sh
# İdempotent: birden fazla kez çalıştırılabilir
#
# Tüm projelerden bağımsız izole dizin yapısı:
#   /project/mail/config/   secrets + ACME cache + DKIM
#   /project/mail/data/     RocksDB + blobs
#   /project/mail/backups/  günlük yedekler
#   Kullanıcı: stalwart (teqlif kullanıcısından bağımsız)
set -euo pipefail

STALWART_VERSION="0.11.8"
BINARY_URL="https://github.com/stalwartlabs/mail-server/releases/download/v${STALWART_VERSION}/stalwart-mail-x86_64-unknown-linux-musl.tar.gz"
BINARY=/usr/local/bin/stalwart-mail
CLI=/usr/local/bin/stalwart-cli
MAIL_BASE=/project/mail
CONFIG_DIR=${MAIL_BASE}/config
DATA_DIR=${MAIL_BASE}/data
BACKUP_DIR=${MAIL_BASE}/backups
LOG_DIR=${MAIL_BASE}/logs
REPO_DIR=/var/www/teqlif.com/deploy/scale/V2.1/node2/resources

echo "=== Stalwart Mail Server kurulumu başlıyor ==="

# ── 1. Sistem kullanıcısı ──────────────────────────────────────────────────────
if ! id stalwart &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin stalwart
    echo "[OK] stalwart kullanıcısı oluşturuldu"
else
    echo "[SKIP] stalwart kullanıcısı zaten mevcut"
fi

# ── 2. Dizinler ────────────────────────────────────────────────────────────────
install -d -o stalwart -g stalwart -m 750 \
    "${CONFIG_DIR}" \
    "${CONFIG_DIR}/acme" \
    "${CONFIG_DIR}/dkim" \
    "${DATA_DIR}/db" \
    "${DATA_DIR}/blobs" \
    "${BACKUP_DIR}" \
    "${LOG_DIR}"
echo "[OK] Dizinler hazır: ${MAIL_BASE}/"

# ── 3. Binary kurulumu ─────────────────────────────────────────────────────────
if [[ ! -f "${BINARY}" ]] || ! "${BINARY}" --version 2>/dev/null | grep -q "${STALWART_VERSION}"; then
    TMP=$(mktemp -d)
    curl -fsSL "${BINARY_URL}" | tar -xz -C "${TMP}"
    install -m 755 "${TMP}/stalwart-mail" "${BINARY}"
    [[ -f "${TMP}/stalwart-cli" ]] && install -m 755 "${TMP}/stalwart-cli" "${CLI}"
    rm -rf "${TMP}"
    echo "[OK] stalwart-mail v${STALWART_VERSION} kuruldu"
else
    echo "[SKIP] stalwart-mail zaten kurulu (v${STALWART_VERSION})"
fi

# port 25/443/465/587/993 bağlama yetkisi (root gerektirmez)
setcap 'cap_net_bind_service=+eip' "${BINARY}"
echo "[OK] CAP_NET_BIND_SERVICE ayarlandı"

# ── 4. Config dosyası ──────────────────────────────────────────────────────────
if [[ ! -f "${CONFIG_DIR}/config.toml" ]]; then
    cp "${REPO_DIR}/stalwart/config.toml" "${CONFIG_DIR}/config.toml"
    chown stalwart:stalwart "${CONFIG_DIR}/config.toml"
    chmod 640 "${CONFIG_DIR}/config.toml"
    echo "[OK] Config şablonu kopyalandı → ${CONFIG_DIR}/config.toml"
else
    echo "[SKIP] Config zaten mevcut"
fi

# ── 5. .env.mail ──────────────────────────────────────────────────────────────
if [[ ! -f "${CONFIG_DIR}/.env.mail" ]]; then
    cp "${REPO_DIR}/stalwart/env.mail.template" "${CONFIG_DIR}/.env.mail"
    chown root:stalwart "${CONFIG_DIR}/.env.mail"
    chmod 640 "${CONFIG_DIR}/.env.mail"
    echo ""
    echo "!!! ${CONFIG_DIR}/.env.mail oluşturuldu"
    echo "!!! STALWART_ADMIN_SECRET değerini doldurun:"
    echo "!!!   openssl rand -base64 32"
    echo "!!!   nano ${CONFIG_DIR}/.env.mail"
    echo ""
fi

# ── 6. Eski teqlif dizini kalıntılarını temizle ────────────────────────────────
# setup.sh ilk çalıştığında /project/teqlif/config/stalwart/ oluşmuştu
if [[ -d /project/teqlif/config/stalwart ]]; then
    rm -rf /project/teqlif/config/stalwart
    echo "[OK] Eski teqlif/config/stalwart dizini temizlendi"
fi
if [[ -f /project/teqlif/config/.env.mail ]]; then
    rm -f /project/teqlif/config/.env.mail
    echo "[OK] Eski teqlif/config/.env.mail temizlendi"
fi

# ── 7. Systemd ────────────────────────────────────────────────────────────────
install -m 644 "${REPO_DIR}/systemd/stalwart-mail.service" \
    /etc/systemd/system/stalwart-mail.service
systemctl daemon-reload
echo "[OK] systemd unit yüklendi"

# ── 8. UFW ────────────────────────────────────────────────────────────────────
for PORT in 25 443 465 993; do
    ufw allow "${PORT}/tcp" comment "stalwart-mail" >/dev/null
done
# NOT: 587 (STARTTLS) açılmıyor — iOS STARTTLS portuna SSL bağlantısı deneyince scan-ban tetikler
echo "[OK] UFW kuralları eklendi: 25, 443, 465, 993"

# ── 9. Fail2ban ───────────────────────────────────────────────────────────────
mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d

cat > /etc/fail2ban/jail.d/stalwart.conf <<'EOF'
[stalwart-smtp]
enabled  = true
filter   = stalwart-smtp
port     = smtp,submissions,submission
logpath  = /var/log/syslog
maxretry = 5
bantime  = 3600
findtime = 600

[stalwart-imap]
enabled  = true
filter   = stalwart-imap
port     = imaps
logpath  = /var/log/syslog
maxretry = 5
bantime  = 3600
findtime = 600
EOF

cat > /etc/fail2ban/filter.d/stalwart-smtp.conf <<'EOF'
[Definition]
failregex = Authentication failed.*from=<HOST>
            Rejecting.*from=<HOST>.*Too many
EOF

cat > /etc/fail2ban/filter.d/stalwart-imap.conf <<'EOF'
[Definition]
failregex = IMAP.*Authentication failed.*ip=<HOST>
            Too many authentication.*<HOST>
EOF

systemctl reload fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null || true
echo "[OK] Fail2ban kuralları eklendi"

# ── 10. Mail backup timer ─────────────────────────────────────────────────────
install -m 644 "${REPO_DIR}/systemd/teqlif-mail-backup.service" \
    /etc/systemd/system/teqlif-mail-backup.service
install -m 644 "${REPO_DIR}/systemd/teqlif-mail-backup.timer" \
    /etc/systemd/system/teqlif-mail-backup.timer
systemctl daemon-reload
systemctl enable --now teqlif-mail-backup.timer
echo "[OK] Backup timer etkinleştirildi (02:30 UTC)"

# ── Sonraki adımlar ───────────────────────────────────────────────────────────
cat <<EOF

============================================================
Kurulum tamamlandı. Sonraki adımlar:

1. Admin şifresini belirle:
   openssl rand -base64 32
   nano ${CONFIG_DIR}/.env.mail

2. DNS kayıtlarını ekle:
   A    mail.teqlif.com → 135.125.223.43  (Cloudflare DNS Only)
   MX   teqlif.com      → mail.teqlif.com  10
   OVH paneli → PTR: 135.125.223.43 → mail.teqlif.com

3. Servisi başlat:
   systemctl enable --now stalwart-mail
   journalctl -u stalwart-mail -f

4. Domain ve hesap ekle (WireGuard üzerinden):
   export STALWART_URL=http://10.10.0.2:8080
   export STALWART_CREDENTIALS='admin:<SIFRE>'
   stalwart-cli domain create teqlif.com
   stalwart-cli account create info@teqlif.com --name 'Info'
   stalwart-cli dkim generate rsa teqlif.com mail

5. DKIM TXT kaydını DNS'e ekle:
   stalwart-cli dkim list
============================================================
EOF
