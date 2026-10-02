#!/bin/bash
# Stalwart Mail Server — node2 kurulum scripti
# Çalıştırma: sudo bash setup.sh
# İdempotent: birden fazla kez çalıştırılabilir
set -euo pipefail

STALWART_VERSION="0.11.8"
BINARY_URL="https://github.com/stalwartlabs/mail-server/releases/download/v${STALWART_VERSION}/stalwart-mail-x86_64-unknown-linux-musl.tar.gz"
BINARY=/usr/local/bin/stalwart-mail
CLI=/usr/local/bin/stalwart-cli
CONFIG_DIR=/project/teqlif/config/stalwart
DATA_DIR=/project/teqlif/data/mail
REPO_DIR=/var/www/teqlif.com/deploy/scale/V2.1/node2/resources

echo "=== Stalwart Mail Server kurulumu başlıyor ==="

# ── 1. Sistem kullanıcısı ──────────────────────────────────────────────────────
if ! id stalwart &>/dev/null; then
    useradd --system --no-create-home --shell /sbin/nologin stalwart
    echo "[OK] stalwart kullanıcısı oluşturuldu"
fi

# ── 2. Dizinler ────────────────────────────────────────────────────────────────
install -d -o stalwart -g stalwart -m 750 \
    "${CONFIG_DIR}" \
    "${CONFIG_DIR}/acme" \
    "${CONFIG_DIR}/dkim" \
    "${DATA_DIR}/db" \
    "${DATA_DIR}/blobs"
echo "[OK] Dizinler hazır"

# ── 3. Binary kurulumu ─────────────────────────────────────────────────────────
if [[ ! -f "${BINARY}" ]] || ! "${BINARY}" --version 2>/dev/null | grep -q "${STALWART_VERSION}"; then
    TMP=$(mktemp -d)
    curl -fsSL "${BINARY_URL}" | tar -xz -C "${TMP}"
    install -m 755 "${TMP}/stalwart-mail" "${BINARY}"
    # stalwart-cli aynı arşivde
    [[ -f "${TMP}/stalwart-cli" ]] && install -m 755 "${TMP}/stalwart-cli" "${CLI}"
    rm -rf "${TMP}"
    echo "[OK] stalwart-mail v${STALWART_VERSION} kuruldu"
else
    echo "[SKIP] stalwart-mail zaten kurulu (v${STALWART_VERSION})"
fi

# stalwart-mail'e port bağlama yetkisi (root olmadan 25, 465, 587, 993, 443)
setcap 'cap_net_bind_service=+eip' "${BINARY}"
echo "[OK] CAP_NET_BIND_SERVICE ayarlandı"

# ── 4. Config dosyası ──────────────────────────────────────────────────────────
if [[ ! -f "${CONFIG_DIR}/config.toml" ]]; then
    cp "${REPO_DIR}/stalwart/config.toml" "${CONFIG_DIR}/config.toml"
    chown stalwart:stalwart "${CONFIG_DIR}/config.toml"
    chmod 640 "${CONFIG_DIR}/config.toml"
    echo "[OK] Config şablonu kopyalandı → ${CONFIG_DIR}/config.toml"
else
    echo "[SKIP] Config zaten mevcut — değiştirilmedi"
fi

# ── 5. .env.mail ──────────────────────────────────────────────────────────────
if [[ ! -f /project/teqlif/config/.env.mail ]]; then
    cp "${REPO_DIR}/stalwart/env.mail.template" /project/teqlif/config/.env.mail
    chown root:stalwart /project/teqlif/config/.env.mail
    chmod 640 /project/teqlif/config/.env.mail
    echo ""
    echo "!!! /project/teqlif/config/.env.mail oluşturuldu"
    echo "!!! STALWART_ADMIN_SECRET ve MAIL_HOSTNAME değerlerini doldurun, ardından devam edin."
    echo ""
fi

# ── 6. Systemd ────────────────────────────────────────────────────────────────
install -m 644 "${REPO_DIR}/systemd/stalwart-mail.service" \
    /etc/systemd/system/stalwart-mail.service
systemctl daemon-reload
echo "[OK] systemd unit yüklendi"

# ── 7. UFW ────────────────────────────────────────────────────────────────────
for PORT in 25 443 465 587 993; do
    ufw allow "${PORT}/tcp" comment "stalwart-mail" >/dev/null
done
echo "[OK] UFW kuralları eklendi: 25, 443, 465, 587, 993"

# ── 8. Fail2ban ───────────────────────────────────────────────────────────────
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

# Fail2ban filter: SMTP AUTH başarısız
cat > /etc/fail2ban/filter.d/stalwart-smtp.conf <<'EOF'
[Definition]
failregex = Authentication failed.*from=<HOST>
            Rejecting.*from=<HOST>.*Too many
EOF

# Fail2ban filter: IMAP login başarısız
cat > /etc/fail2ban/filter.d/stalwart-imap.conf <<'EOF'
[Definition]
failregex = IMAP.*Authentication failed.*ip=<HOST>
            Too many authentication.*<HOST>
EOF

systemctl reload fail2ban 2>/dev/null || systemctl restart fail2ban 2>/dev/null || true
echo "[OK] Fail2ban kuralları eklendi"

# ── 9. Mail backup timer ──────────────────────────────────────────────────────
install -m 644 "${REPO_DIR}/systemd/teqlif-mail-backup.service" \
    /etc/systemd/system/teqlif-mail-backup.service
install -m 644 "${REPO_DIR}/systemd/teqlif-mail-backup.timer" \
    /etc/systemd/system/teqlif-mail-backup.timer
install -m 755 "${REPO_DIR}/scripts/mail_backup.sh" \
    /project/teqlif/scripts/mail_backup.sh 2>/dev/null || true
systemctl daemon-reload
systemctl enable --now teqlif-mail-backup.timer
echo "[OK] Backup timer etkinleştirildi"

# ── Sonraki adımlar ───────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "Kurulum tamamlandı. Sonraki adımlar:"
echo ""
echo "1. .env.mail dosyasını düzenle:"
echo "   nano /project/teqlif/config/.env.mail"
echo ""
echo "2. DNS kayıtlarını ekle (bkz. 03_mail_server.md §DNS):"
echo "   MX  teqlif.com  →  mail.teqlif.com  (prio 10)"
echo "   A   mail        →  135.125.223.43"
echo "   OVH panelinden PTR: 135.125.223.43 → mail.teqlif.com"
echo ""
echo "3. Servisi başlat:"
echo "   systemctl enable --now stalwart-mail"
echo ""
echo "4. Domain ve hesap ekle:"
echo "   export STALWART_URL=http://10.10.0.2:8080"
echo "   export STALWART_CREDENTIALS='admin:<SIFRE>'"
echo "   stalwart-cli domain create teqlif.com"
echo "   stalwart-cli account create info@teqlif.com --name 'Info'"
echo "   stalwart-cli dkim generate rsa teqlif.com mail"
echo ""
echo "5. DKIM TXT kaydını DNS'e ekle (stalwart-cli dkim list ile al)"
echo "============================================================"
