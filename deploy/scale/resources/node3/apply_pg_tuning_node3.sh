#!/usr/bin/env bash
# deploy/scale/resources/node3/apply_pg_tuning_node3.sh
# node3 PostgreSQL staging tuning — ALTER SYSTEM parametreleri (4 GB RAM, SSD)
# max_connections ve shared_buffers için PostgreSQL restart gerekir.
#
# Bağlantı havuzu hesabı (neden max_connections=100):
#   2 uvicorn worker × (pool_size=20 + max_overflow=10) = 60 app bağlantısı
#   alembic migration / psql admin / postgres_exporter  = ~20 ek bağlantı
#   Toplam ihtiyaç ~80 → 100 ile güvenli marj
set -euo pipefail

echo "==> PostgreSQL staging tuning uygulanıyor..."
sudo -u postgres psql <<'SQL'
ALTER SYSTEM SET max_connections            = '100';
ALTER SYSTEM SET shared_buffers             = '1GB';
ALTER SYSTEM SET effective_cache_size       = '3GB';
ALTER SYSTEM SET work_mem                   = '16MB';
ALTER SYSTEM SET maintenance_work_mem       = '256MB';
ALTER SYSTEM SET wal_buffers                = '16MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET random_page_cost           = 1.1;
ALTER SYSTEM SET effective_io_concurrency   = 200;
SQL

echo "==> PostgreSQL yeniden başlatılıyor (max_connections + shared_buffers için zorunlu)..."
sudo systemctl restart postgresql

echo "==> Staging servisleri yeniden başlatılıyor..."
sudo systemctl restart teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging

echo "Tuning tamamlandı."
