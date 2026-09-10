#!/usr/bin/env bash
# deploy/scale/resources/apply_pg_tuning.sh
# node1'de çalıştır — PostgreSQL tuning parametrelerini ALTER SYSTEM ile uygular.
# Idempotent: tekrar çalıştırmak güvenli.
set -euo pipefail

echo "==> PostgreSQL tuning uygulanıyor (ALTER SYSTEM)..."

sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
-- Bellek
ALTER SYSTEM SET shared_buffers            = '2GB';
ALTER SYSTEM SET effective_cache_size      = '6GB';
ALTER SYSTEM SET work_mem                  = '16MB';
ALTER SYSTEM SET maintenance_work_mem      = '256MB';

-- WAL & Checkpoint
ALTER SYSTEM SET wal_buffers               = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- Depolama (NVMe)
ALTER SYSTEM SET random_page_cost          = 1.1;
ALTER SYSTEM SET effective_io_concurrency  = 200;
SQL

echo "==> postgresql yeniden başlatılıyor..."
sudo systemctl restart postgresql

echo "==> Teqlif servisleri yeniden başlatılıyor..."
sudo systemctl restart teqlif teqlif-staging teqlif-worker teqlif-worker-critical

echo ""
echo "PostgreSQL tuning tamamlandı."
echo "Doğrulama: sudo -u postgres psql -c 'SHOW shared_buffers;'"
