#!/bin/bash
# node2 — Snappymail webmail kurulum scripti
# https://webmail.teqlif.com → Cloudflare Proxied → port 80 → nginx → PHP-FPM → Snappymail
#
# Önkoşullar:
#   - nginx kurulu ve aktif
#   - REPO_DIR tanımlı (bootstrap tarafından set edilir)
#
# Cloudflare gereksinimleri (manuelde yapılmalı):
#   1. DNS: A webmail → 135.125.223.43, Proxied
#   2. Configuration Rule: Hostname = webmail.teqlif.com → SSL: Flexible
#   3. Origin Rule: Hostname = webmail.teqlif.com → Destination Port: 80
#
# /etc/hosts gereği:
#   127.0.0.1 mail.teqlif.com
#   (Snappymail → Stalwart loopback bağlantısı için; hairpin NAT önlenir)

set -euo pipefail
REPO_DIR="${REPO_DIR:-/var/www/teqlif.com}"
WEBMAIL_VERSION="2.38.2"
WEBMAIL_URL="https://github.com/the-djmaze/snappymail/releases/download/v${WEBMAIL_VERSION}/snappymail-${WEBMAIL_VERSION}.tar.gz"
WEBMAIL_ROOT="/var/www/webmail"

# ── 1. PHP 8.4 + gerekli extension'lar ───────────────────────────────────────
apt-get install -y php8.4-fpm php8.4-curl php8.4-xml php8.4-mbstring php8.4-zip \
    php8.4-gd php8.4-intl php8.4-pdo php8.4-mysql 2>/dev/null || true
echo "[OK] PHP 8.4 kuruldu"

# ── 2. Snappymail indir ve kur ────────────────────────────────────────────────
mkdir -p "${WEBMAIL_ROOT}"
curl -fsSL "${WEBMAIL_URL}" | tar -xz -C "${WEBMAIL_ROOT}"
chown -R www-data:www-data "${WEBMAIL_ROOT}"
chmod -R 755 "${WEBMAIL_ROOT}"
chmod -R 700 "${WEBMAIL_ROOT}/data"
echo "[OK] Snappymail ${WEBMAIL_VERSION} kuruldu"

# ── 3. nginx config ───────────────────────────────────────────────────────────
install -m 644 "${REPO_DIR}/deploy/scale/V2.1/node2/resources/webmail/nginx-webmail.conf" \
    /etc/nginx/sites-available/webmail
ln -sf /etc/nginx/sites-available/webmail /etc/nginx/sites-enabled/webmail
nginx -t
systemctl reload nginx
echo "[OK] nginx webmail config aktif"

# ── 4. UFW: port 80 ───────────────────────────────────────────────────────────
ufw allow 80/tcp comment "nginx-webmail" >/dev/null
echo "[OK] UFW: port 80 açıldı"

# ── 5. /etc/hosts: loopback IMAP ─────────────────────────────────────────────
if ! grep -q "mail.teqlif.com" /etc/hosts; then
    echo "127.0.0.1 mail.teqlif.com" >> /etc/hosts
    echo "[OK] /etc/hosts: mail.teqlif.com → 127.0.0.1"
else
    echo "[SKIP] /etc/hosts: mail.teqlif.com zaten mevcut"
fi

# ── 6. Snappymail domain config ───────────────────────────────────────────────
DOMAIN_DIR="${WEBMAIL_ROOT}/data/_data_/_default_/domains"
mkdir -p "${DOMAIN_DIR}"
cat > "${DOMAIN_DIR}/teqlif.com.json" << 'EOF'
{
    "IMAP": {
        "host": "mail.teqlif.com",
        "port": 993,
        "type": 1,
        "timeout": 300,
        "shortLogin": false,
        "lowerLogin": true,
        "sasl": ["PLAIN", "LOGIN"],
        "ssl": {
            "verify_peer": true,
            "verify_peer_name": true,
            "allow_self_signed": false,
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        }
    },
    "SMTP": {
        "host": "mail.teqlif.com",
        "port": 465,
        "type": 1,
        "timeout": 60,
        "shortLogin": false,
        "lowerLogin": true,
        "sasl": ["PLAIN", "LOGIN"],
        "ssl": {
            "verify_peer": true,
            "verify_peer_name": true,
            "allow_self_signed": false,
            "SNI_enabled": true,
            "disable_compression": true,
            "security_level": 1
        },
        "useAuth": true,
        "setSender": true,
        "usePhpMail": false
    }
}
EOF
chown www-data:www-data "${DOMAIN_DIR}/teqlif.com.json"
echo "[OK] Snappymail domain config yazıldı (type=1 SSL, NOT STARTTLS)"

systemctl restart php8.4-fpm
echo "[OK] PHP-FPM restart"
echo ""
echo "=== Snappymail kurulum tamamlandı ==="
echo "    URL:  https://webmail.teqlif.com"
echo "    Admin: https://webmail.teqlif.com/?admin"
