#!/usr/bin/env bash
# deploy/scale/resources/node1/apply_pg_tuning.sh
# node1 PostgreSQL performans tuning — ALTER SYSTEM parametreleri (12 GB RAM, NVMe SSD)
# max_connections ve shared_buffers için PostgreSQL restart gerekir.
#
# Bağlantı havuzu hesabı (neden max_connections=200):
#   4 uvicorn worker × (pool_size=20 + max_overflow=10) = 120 app bağlantısı
#   alembic migration / psql admin / postgres_exporter  = ~30 ek bağlantı
#   Toplam ihtiyaç ~150 → 200 ile güvenli marj
set -euo pipefail

echo "==> PostgreSQL tuning uygulanıyor..."
sudo -u postgres psql <<'SQL'
ALTER SYSTEM SET listen_addresses           = 'localhost';
ALTER SYSTEM SET max_connections            = '200';
ALTER SYSTEM SET shared_buffers             = '3GB';
ALTER SYSTEM SET effective_cache_size       = '9GB';
ALTER SYSTEM SET work_mem                   = '16MB';
ALTER SYSTEM SET maintenance_work_mem       = '512MB';
ALTER SYSTEM SET wal_buffers                = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET random_page_cost           = 1.1;
ALTER SYSTEM SET effective_io_concurrency   = 200;
SQL

echo "==> PostgreSQL yeniden başlatılıyor (max_connections + shared_buffers için zorunlu)..."
sudo systemctl restart postgresql

echo "==> Teqlif servisleri yeniden başlatılıyor..."
sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical

echo "Tuning tamamlandı."
