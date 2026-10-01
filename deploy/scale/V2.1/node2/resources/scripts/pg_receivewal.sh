#!/bin/bash
# pg_receivewal — node1'den sürekli WAL stream alır
# systemd tarafından restart=always ile çalıştırılır
set -euo pipefail

WAL_DIR=/project/teqlif/backups/pg_wal
PGHOST=10.10.0.1
PGPORT=5432
PGUSER=teqlif_repl
export PGPASSWORD="${REPL_PASSWORD:?REPL_PASSWORD env değişkeni tanımlı değil}"

install -d "${WAL_DIR}"
exec pg_receivewal \
    -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" \
    --directory="${WAL_DIR}" \
    --slot=node2_receivewal \
    --no-sync
