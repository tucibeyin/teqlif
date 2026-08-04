"""
Schema-versioned cache utilities for fastapi-cache.

Schema-driven statik endpoint'ler (catalog, cities, field_config) bu modülü
kullanarak versiyon-isimli cache key'leri üretir.

Mekanizma:
    1. Migration çalışır → bump_schema_version() → Redis'te schema:static_version artar
    2. Servis restart → init_schema_version() yeni versiyonu memory'ye yükler
    3. Yeni istekler  → "teqlif:cache:schema:v2:/api/catalog" key'ini arar (yok)
    4. DB'den taze veri çekilir, yeni key altında cache'lenir
    5. Eski "teqlif:cache:schema:v1:/api/catalog" key'i TTL (86400s) dolunca silinir

Bkz: documents/architectural_decisions.md — ADR #9
"""
import logging
from typing import Optional

from fastapi import Request, Response

from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

SCHEMA_VERSION_KEY = "schema:static_version"

# Modül düzeyinde tek seferlik cache — startup'ta init_schema_version() ile doldurulur.
# Her request'te Redis'e gitmez; servis restart ile güncellenir.
_cached_version: str = "1"


async def init_schema_version() -> None:
    """
    Mevcut şema versiyonunu Redis'ten okur ve memory'de cache'ler.
    Uygulama startup'ında (lifespan içinde) bir kez çağrılır.
    """
    global _cached_version
    try:
        redis = await get_redis()
        v = await redis.get(SCHEMA_VERSION_KEY)
        if v:
            _cached_version = str(v)
            logger.info("[schema_cache] Şema versiyonu yüklendi: v%s", _cached_version)
        else:
            # İlk kurulumda key henüz yoktur; varsayılan "1" geçerlidir.
            logger.info(
                "[schema_cache] schema:static_version Redis'te bulunamadı, varsayılan: v%s",
                _cached_version,
            )
    except Exception as exc:
        logger.warning(
            "[schema_cache] Redis'e bağlanılamadı, v%s ile devam: %s",
            _cached_version, exc,
        )


def static_schema_key_builder(
    func,
    namespace: Optional[str] = "",
    *,
    request: Optional[Request] = None,
    response: Optional[Response] = None,
    args: Optional[tuple] = (),
    kwargs: Optional[dict] = None,
) -> str:
    """
    Schema-driven statik endpoint'ler için versiyon-isimli cache key üretici.

    Key formatı:  schema:v{version}:{url_path}[?{query}]

    FastAPICache prefix'i ("teqlif:cache") ile birleşince Redis'teki tam key:
        teqlif:cache:schema:v2:/api/catalog
        teqlif:cache:schema:v2:/api/cities
        teqlif:cache:schema:v2:/api/field-config/automobile

    Şema versiyonu arttığında:
    - Eski key'ler (v1) yetim kalır → 86400s TTL dolunca Redis'ten silinir
    - Yeni istekler cache miss alır → DB'den taze veri → yeni key altında cache'lenir
    """
    path = request.url.path if request else func.__name__
    query = f"?{request.url.query}" if request and request.url.query else ""
    return f"schema:v{_cached_version}:{path}{query}"
