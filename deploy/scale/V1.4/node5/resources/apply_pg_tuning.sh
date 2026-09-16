#!/usr/bin/env bash
# deploy/scale/V1.4/node5/resources/apply_pg_tuning.sh
# node5 PostgreSQL performans tuning — ALTER SYSTEM parametreleri
# ZAP-Hosting Donanımı: 4 Core EPYC, 7.8 GB RAM (NVMe)
# 
# RAM'in ~%25'i shared_buffers, ~%75'i effective_cache_size olarak ayarlandı.
set -euo pipefail

echo "==> PostgreSQL tuning uygulanıyor (Node5 - 7.8GB RAM Profil)..."
sudo -u postgres psql <<'SQL'
ALTER SYSTEM SET listen_addresses           = 'localhost, 10.10.0.5';
ALTER SYSTEM SET max_connections            = '200';
ALTER SYSTEM SET shared_buffers             = '2GB';
ALTER SYSTEM SET effective_cache_size       = '6GB';
ALTER SYSTEM SET work_mem                   = '16MB';
ALTER SYSTEM SET maintenance_work_mem       = '512MB';
ALTER SYSTEM SET wal_buffers                = '32MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET random_page_cost           = 1.1;
ALTER SYSTEM SET effective_io_concurrency   = 200;
SQL

echo "==> PostgreSQL yeniden başlatılıyor..."
sudo systemctl restart postgresql

echo "Tuning tamamlandı. (max_connections ve shared_buffers aktif)"
