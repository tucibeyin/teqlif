"""
Alembic Migration Yardımcı Araçları.

Migration'ların upgrade() / downgrade() fonksiyonlarından çağrılabilen
Redis-taraflı operasyonları içerir (cache invalidasyon vb.).

Kullanım:
    from app.utils.migration_utils import bump_schema_version

    def upgrade() -> None:
        # ... DDL değişiklikleri ...
        bump_schema_version()   # statik cache'leri geçersiz kıl

    def downgrade() -> None:
        # ... DDL geri alma ...
        bump_schema_version()   # downgrade da cache'i geçersiz kılar
"""
import logging
import os

logger = logging.getLogger(__name__)

SCHEMA_VERSION_KEY = "schema:static_version"


def bump_schema_version() -> int:
    """
    Redis'teki schema:static_version sayacını atomik olarak artırır.

    Bu işlem; catalog, states ve field_config endpoint'lerinin cache'lerini
    sonraki servis restart'ında otomatik olarak geçersiz kılar.
    (init_schema_version() yeni versiyonu okur → eski key'ler yetim kalır → TTL ile silinir.)

    Döndürür: Yeni versiyon numarası. Redis erişilemezse -1 (hata kritik değil).
    """
    redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379")
    try:
        import redis as sync_redis  # redis-py sync client
        r = sync_redis.from_url(redis_url, decode_responses=True)
        new_version = r.incr(SCHEMA_VERSION_KEY)
        r.close()
        msg = f"[migration_utils] schema:static_version → v{new_version}"
        logger.info(msg)
        print(msg)
        return new_version
    except Exception as exc:
        msg = f"[migration_utils] UYARI: schema:static_version artırılamadı: {exc}"
        logger.warning(msg)
        print(msg)
        return -1
