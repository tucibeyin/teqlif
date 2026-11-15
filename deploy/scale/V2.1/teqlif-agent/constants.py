"""teqlif-agent — Paylaşımlı sabitler.

Birden fazla modülün kullandığı sabitler buradan import edilir.
Modül iç sabitleri (_UNDERSCORE) yerine buradan almak cross-module
bağımlılığı kaldırır.
"""
from __future__ import annotations

# Gossip /cmd + polkit (50-teqlif-agent.rules) üzerinden
# yeniden başlatılabilecek servisler — tek kaynak.
RESTARTABLE_SVCS: frozenset[str] = frozenset({
    "teqlif",
    "teqlif-worker",
    "teqlif-worker-critical",
    "teqlif-worker-video",
    "teqlif-ai-proxy",
    "teqlif-livekit",
    "teqlif-agent",
    "teqlif-staging",
    "teqlif-worker-staging",
    "teqlif-worker-critical-staging",
})

# Uyarıları staging Telegram kanalına yönlendirilen servisler
STAGING_SERVICES: frozenset[str] = frozenset({
    "teqlif-staging",
    "teqlif-worker-staging",
    "teqlif-worker-critical-staging",
    "teqlif-worker-video-staging",
    "teqlif-ai-proxy-staging",
    "teqlif-redis-staging",
    "teqlif-livekit-staging",
})

# Yedek türü → maksimum kabul edilebilir yaş (dakika)
BACKUP_MAX_MIN: dict[str, int] = {
    "pg_backup":                  25 * 60,
    "minio_backup":               25 * 60,
    "redis_backup":               25 * 60,
    "loki_backup":                25 * 60,
    "uptime_kuma_backup":         25 * 60,
    "nodemonitor_config_backup":  25 * 60,
    "mail_backup":                25 * 60,
    "clickhouse_backup":          25 * 60,
    "cluster_secrets_backup":     25 * 60,
    "pg_basebackup":               7 * 24 * 60,
    "offsite_sync":               25 * 60,
    "offsite_wal_sync":           90,
    "pg_wal_cleanup":             25 * 60,
}

# Yedek türü → insan okunabilir etiket
BACKUP_LABELS: dict[str, str] = {
    "pg_backup":                "PG dump",
    "minio_backup":             "MinIO",
    "redis_backup":             "Redis",
    "clickhouse_backup":        "ClickHouse",
    "loki_backup":              "Loki",
    "uptime_kuma_backup":       "Uptime Kuma",
    "nodemonitor_config_backup":"nodeMonitor config",
    "mail_backup":              "Stalwart Mail",
    "cluster_secrets_backup":   "Cluster sırlar",
    "pg_basebackup":            "PG base backup",
    "offsite_sync":             "Offsite sync",
    "offsite_wal_sync":         "WAL sync",
    "pg_wal_cleanup":           "WAL temizliği",
}
