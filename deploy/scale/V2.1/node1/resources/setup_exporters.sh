#!/usr/bin/env bash
# SRE-116: node1 Prometheus exporter kurulum scripti
# Çalıştır: sudo bash deploy/scale/V2.1/node1/resources/setup_exporters.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "=== SRE-116 exporter kurulumu (node1) ==="

# ── 1. Linux prometheus system user ───────────────────────────────────────
if ! id prometheus &>/dev/null; then
  useradd --system --no-create-home --shell /usr/sbin/nologin prometheus
  echo "[OK] Linux user 'prometheus' oluşturuldu"
else
  echo "[SKIP] Linux user 'prometheus' zaten mevcut"
fi

# ── 2. PostgreSQL monitoring user (peer auth) ──────────────────────────────
if sudo -u postgres psql -Atc "SELECT 1 FROM pg_roles WHERE rolname='prometheus'" | grep -q 1; then
  echo "[SKIP] PostgreSQL user 'prometheus' zaten mevcut"
else
  sudo -u postgres psql -c "CREATE USER prometheus WITH LOGIN CONNECTION LIMIT 3 NOSUPERUSER NOCREATEDB NOCREATEROLE;"
  sudo -u postgres psql -c "GRANT pg_monitor TO prometheus;"
  echo "[OK] PostgreSQL user 'prometheus' oluşturuldu, pg_monitor role atandı"
fi

# ── 3. postgres_exporter systemd service ──────────────────────────────────
cp "${SCRIPT_DIR}/../systemd/prometheus-postgres-exporter.service" \
   /etc/systemd/system/prometheus-postgres-exporter.service
echo "[OK] prometheus-postgres-exporter.service kopyalandı"

# ── 4. redis_exporter (apt) ────────────────────────────────────────────────
if ! dpkg -l prometheus-redis-exporter &>/dev/null; then
  apt-get install -y prometheus-redis-exporter
  echo "[OK] prometheus-redis-exporter kuruldu"
else
  echo "[SKIP] prometheus-redis-exporter zaten kurulu"
fi

# Redis şifresini redis.conf'tan oku ve env dosyasına yaz
REDIS_CONF="/project/teqlif/config/redis/redis-core.conf"
REDIS_PASS=$(grep -m1 '^requirepass' "${REDIS_CONF}" 2>/dev/null | awk '{print $2}' || true)
{
  echo "REDIS_ADDR=redis://127.0.0.1:6379"
  echo "REDIS_PASSWORD=${REDIS_PASS}"
  echo "ARGS=--web.listen-address=10.10.0.1:9121"
} > /etc/default/prometheus-redis-exporter
chmod 640 /etc/default/prometheus-redis-exporter
chown root:prometheus /etc/default/prometheus-redis-exporter
echo "[OK] /etc/default/prometheus-redis-exporter yazıldı"

# ── 5. pgbouncer_exporter (apt) ────────────────────────────────────────────
if ! dpkg -l prometheus-pgbouncer-exporter &>/dev/null; then
  apt-get install -y prometheus-pgbouncer-exporter
  echo "[OK] prometheus-pgbouncer-exporter kuruldu"
else
  echo "[SKIP] prometheus-pgbouncer-exporter zaten kurulu"
fi

# pgbouncer stats_users eklenmişse atla
if ! grep -q 'stats_users' /etc/pgbouncer/pgbouncer.ini; then
  # Rastgele 24-char alfanümerik şifre
  PROM_PGBOUNCER_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
  # userlist.txt'ye ekle
  echo "\"prometheus\" \"${PROM_PGBOUNCER_PASS}\"" >> /etc/pgbouncer/userlist.txt
  # pgbouncer.ini [pgbouncer] bölümüne stats_users ekle
  sed -i '/^\[pgbouncer\]/a stats_users = prometheus' /etc/pgbouncer/pgbouncer.ini
  systemctl reload pgbouncer
  # env dosyasına pgbouncer bağlantı bilgilerini yaz
  {
    echo "PGBOUNCER_DSN=postgresql://prometheus:${PROM_PGBOUNCER_PASS}@127.0.0.1:6432/pgbouncer"
    echo "ARGS=--web.listen-address=10.10.0.1:9127"
  } > /etc/default/prometheus-pgbouncer-exporter
  chmod 640 /etc/default/prometheus-pgbouncer-exporter
  chown root:prometheus /etc/default/prometheus-pgbouncer-exporter
  echo "[OK] pgbouncer stats_users = prometheus eklendi, şifre env dosyasına yazıldı"
else
  echo "[SKIP] pgbouncer stats_users zaten tanımlı"
fi

# ── 6. nginx metrics proxy (FastAPI /metrics → 10.10.0.1:9182) ────────────
NGINX_CONF_SRC="${SCRIPT_DIR}/nginx/teqlif-metrics-proxy.conf"
NGINX_CONF_DST="/etc/nginx/conf.d/teqlif-metrics-proxy.conf"
if [ ! -f "${NGINX_CONF_DST}" ]; then
  cp "${NGINX_CONF_SRC}" "${NGINX_CONF_DST}"
  nginx -t && systemctl reload nginx
  echo "[OK] nginx teqlif-metrics-proxy.conf kuruldu, nginx yeniden yüklendi"
else
  echo "[SKIP] nginx teqlif-metrics-proxy.conf zaten mevcut"
fi

# ── 7. systemd reload ve servisleri başlat ─────────────────────────────────
systemctl daemon-reload
systemctl enable --now prometheus-postgres-exporter
systemctl enable --now prometheus-redis-exporter
systemctl enable --now prometheus-pgbouncer-exporter

echo ""
echo "=== Servis durumları ==="
for svc in prometheus-postgres-exporter prometheus-redis-exporter prometheus-pgbouncer-exporter; do
  status=$(systemctl is-active "${svc}" 2>/dev/null || echo "UNKNOWN")
  echo "  ${svc}: ${status}"
done

echo ""
echo "=== Erişilebilirlik testi (nodeMonitor'dan scrape edilebilir portlar) ==="
for port in 9187 9121 9127 9182; do
  if ss -tlnp | grep -q "10.10.0.1:${port}"; then
    echo "  10.10.0.1:${port} — AÇIK"
  else
    echo "  10.10.0.1:${port} — KAPALI"
  fi
done

echo ""
echo "[DONE] SRE-116 exporter kurulumu tamamlandı."
echo "Prometheus yeniden yükle: sudo systemctl reload prometheus"
