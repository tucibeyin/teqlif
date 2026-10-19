#!/bin/bash
# pg_wal_cleanup — pg_archivecleanup ile PITR zincirini koruyarak WAL temizler.
# En eski basebackup'ın başlangıç WAL segment'ini referans alır; ondan öncekini siler.
# Günlük 05:30 UTC'de çalışır.
set -euo pipefail

WAL_DIR=/project/teqlif/backups/pg_wal
BASEBACKUP_DIR=/project/teqlif/backups/pg_basebackup
LOGFILE=/project/teqlif/logs/pg_wal_cleanup.log

exec >> "${LOGFILE}" 2>&1

if [ ! -d "${WAL_DIR}" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: ${WAL_DIR} yok, atlanıyor"
    exit 0
fi

# En eski basebackup'tan START WAL segment adını çıkar
oldest_backup=$(ls -1dt "${BASEBACKUP_DIR}"/[0-9]* 2>/dev/null | sort | tail -1)
if [ -z "${oldest_backup}" ] || [ ! -f "${oldest_backup}/base.tar.gz" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: basebackup bulunamadı, atlanıyor"
    exit 0
fi

start_wal=$(tar -xzf "${oldest_backup}/base.tar.gz" -O backup_label 2>/dev/null \
    | grep "^START WAL LOCATION:" \
    | sed 's/.*file \([0-9A-F]*\).*/\1/')

if [ -z "${start_wal}" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: backup_label'dan START WAL okunamadı, atlanıyor"
    exit 0
fi

before=$(find "${WAL_DIR}" -maxdepth 1 -type f | wc -l)
/usr/bin/pg_archivecleanup "${WAL_DIR}" "${start_wal}" 2>&1
after=$(find "${WAL_DIR}" -maxdepth 1 -type f | wc -l)
size=$(du -sh "${WAL_DIR}" 2>/dev/null | cut -f1)
deleted=$(( before - after ))

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) pg_wal_cleanup: ${deleted} segment silindi, kalan ${after} (${size}) — referans: ${start_wal}"
logger "teqlif pg_wal_cleanup: ${deleted} silindi, kalan ${after} (${size})"
