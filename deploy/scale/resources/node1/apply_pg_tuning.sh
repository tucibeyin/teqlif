#!/usr/bin/env bash
# deploy/scale/resources/node1/apply_pg_tuning.sh
# node1 PostgreSQL performans tuning — ALTER SYSTEM parametreleri (8GB RAM, SSD varsayımı)
# Önemli: Parametreler hemen etkili olur ama shared_buffers için restart gerekir.
set -euo pipefail

echo "==> PostgreSQL tuning uygulanıyor..."
sudo -u postgres psql <<'SQL'
ALTER SYSTEM SET shared_buffers             = '2GB';
ALTER SYSTEM SET effective_cache_size       = '6GB';
ALTER SYSTEM SET work_mem                   = '16MB';
ALTER SYSTEM SET maintenance_work_mem       = '256MB';
ALTER SYSTEM SET wal_buffers                = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET random_page_cost           = 1.1;
ALTER SYSTEM SET effective_io_concurrency   = 200;
SQL

echo "==> PostgreSQL yeniden başlatılıyor..."
sudo systemctl restart postgresql

echo "==> Teqlif servisleri yeniden başlatılıyor..."
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

echo "Tuning tamamlandı."
