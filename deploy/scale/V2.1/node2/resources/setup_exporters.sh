#!/usr/bin/env bash
# node2 Prometheus exporter kurulum scripti (BIZ-04-B)
#
# Kurar:
#   1. prometheus-redis-exporter — Redis replica metrikleri (10.10.0.2:9121)
#   2. ClickHouse Prometheus endpoint config (prometheus.xml → /etc/clickhouse-server/config.d/)
#   3. DMS systemd timer + state dizini
#
# Çalıştır: sudo bash deploy/scale/V2.1/node2/resources/setup_exporters.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
NODE_DIR="${SCRIPT_DIR}/.."

echo "=== BIZ-04-B node2 exporter + DMS kurulumu ==="

# ── 1. prometheus system user ───────────────────────────────────────────────
if ! id prometheus &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
    echo "[OK] Linux user 'prometheus' oluşturuldu"
else
    echo "[SKIP] Linux user 'prometheus' zaten mevcut"
fi

# ── 2. Redis replica exporter (apt) ────────────────────────────────────────
if ! dpkg -l prometheus-redis-exporter &>/dev/null; then
    apt-get install -y prometheus-redis-exporter
    echo "[OK] prometheus-redis-exporter kuruldu"
else
    echo "[SKIP] prometheus-redis-exporter zaten kurulu"
fi

REDIS_CONF="/etc/redis/redis-replica.conf"
REDIS_PASS=$(grep -m1 '^requirepass' "${REDIS_CONF}" 2>/dev/null | awk '{print $2}' || true)

echo "ARGS=--redis.addr=redis://127.0.0.1:6379 --redis.password=${REDIS_PASS} --web.listen-address=10.10.0.2:9121" \
    > /etc/default/prometheus-redis-exporter
chmod 640 /etc/default/prometheus-redis-exporter
chown root:prometheus /etc/default/prometheus-redis-exporter

mkdir -p /etc/systemd/system/prometheus-redis-exporter.service.d
cat > /etc/systemd/system/prometheus-redis-exporter.service.d/override.conf <<'DROPIN'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus-redis-exporter $ARGS
DROPIN
echo "[OK] /etc/default/prometheus-redis-exporter yazıldı (10.10.0.2:9121)"

# ── 3. ClickHouse Prometheus endpoint ──────────────────────────────────────
PROM_XML="${NODE_DIR}/resources/clickhouse/config.d/prometheus.xml"
DEST_XML="/etc/clickhouse-server/config.d/prometheus.xml"
if [ ! -f "${DEST_XML}" ]; then
    cp "${PROM_XML}" "${DEST_XML}"
    chown root:clickhouse "${DEST_XML}"
    chmod 640 "${DEST_XML}"
    echo "[OK] ClickHouse prometheus.xml kopyalandı → ${DEST_XML}"
else
    echo "[SKIP] ${DEST_XML} zaten mevcut"
fi

# ── 4. DMS state dizini ─────────────────────────────────────────────────────
mkdir -p /var/lib/teqlif-dms
chown tucibeyin:tucibeyin /var/lib/teqlif-dms
chmod 700 /var/lib/teqlif-dms
echo "[OK] /var/lib/teqlif-dms hazır"

# ── 5. DMS systemd servisleri ───────────────────────────────────────────────
chmod 755 "${NODE_DIR}/resources/scripts/nodemonitor_dms_check.sh"
cp "${NODE_DIR}/resources/systemd/teqlif-dms.service" /etc/systemd/system/
cp "${NODE_DIR}/resources/systemd/teqlif-dms.timer"   /etc/systemd/system/
echo "[OK] teqlif-dms.service + teqlif-dms.timer kopyalandı"

# ── 6. Servisleri etkinleştir ───────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now prometheus-redis-exporter
systemctl enable --now teqlif-dms.timer

# ClickHouse reload (hata varsa devam et — CH başlamamış olabilir)
if systemctl is-active clickhouse-server &>/dev/null; then
    systemctl reload clickhouse-server 2>/dev/null \
        || systemctl restart clickhouse-server 2>/dev/null \
        || echo "[WARN] ClickHouse reload başarısız — manuel yeniden başlatma gerekebilir"
    echo "[OK] ClickHouse prometheus endpoint aktif (port 9363)"
else
    echo "[INFO] ClickHouse çalışmıyor — başlatıldığında prometheus.xml otomatik yüklenir"
fi

echo ""
echo "=== Doğrulama ==="
for svc in prometheus-redis-exporter teqlif-dms.timer; do
    status=$(systemctl is-active "${svc}" 2>/dev/null || echo "UNKNOWN")
    echo "  ${svc}: ${status}"
done

if ss -tlnp | grep -q "10.10.0.2:9121"; then
    echo "  10.10.0.2:9121 (redis-replica exporter) — AÇIK"
else
    echo "  10.10.0.2:9121 (redis-replica exporter) — KAPALI"
fi

echo ""
echo "[DONE] node2 BIZ-04-B exporter + DMS kurulumu tamamlandı."
echo ""
echo "Kalan manuel adımlar:"
echo "  1. MinIO bearer token: mc admin prometheus generate <alias> cluster > /opt/teqlif-agent/minio_metrics_token"
echo "     (nodeMonitor'da — Prometheus'un okuyacağı yol)"
echo "  2. DMS dry-run: sudo -u tucibeyin /var/www/teqlif.com/deploy/scale/V2.1/node2/resources/scripts/nodemonitor_dms_check.sh"
echo "  3. Prometheus reload (nodeMonitor'da): sudo systemctl reload prometheus"
