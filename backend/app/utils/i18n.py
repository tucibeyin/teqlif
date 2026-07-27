"""
app/utils/i18n.py
─────────────────
Merkezi çeviri (ARB) yardımcısı.

_get_t(lang) fonksiyonu ilgili dile ait app_<lang>.arb dosyasını
okur ve bir dict olarak döner.  Dosyanın mtime'ı her çağrıda
kontrol edilir; değişmişse cache otomatik yenilenir — sunucu
restart gerektirmez.
"""

import json
import time
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

_MEMORY_CACHE: Dict[str, Dict[str, str]] = {}
_CACHE_TIME: Dict[str, float] = {}
_CACHE_TTL = 300.0  # 5 dakika TTL
_SUPPORTED = {"tr", "en", "ar", "ru"}


def _get_t(lang: str) -> dict:
    """
    Belirtilen dil için çeviri sözlüğünü döner.
    
    * Disk (ARB) okuması yapmaz.
    * Bellekteki TTL ön belleği (300 saniye) geçerliyse doğrudan oradan döner.
    * Süre dolmuşsa veya bellek boşsa senkron Redis / DB sorgusuyla belleği tazeleyip döner.
    """
    now = time.time()
    if lang in _MEMORY_CACHE and (now - _CACHE_TIME.get(lang, 0.0)) < _CACHE_TTL:
        return _MEMORY_CACHE[lang]

    # 1. Redis'ten senkron okumayı dene
    try:
        from app.config import settings
        import redis as sync_redis
        r = sync_redis.Redis.from_url(
            settings.redis_url, 
            decode_responses=True, 
            socket_timeout=2.0, 
            socket_connect_timeout=2.0
        )
        cached_str = r.get(f"i18n:{lang}")
        if cached_str:
            data = json.loads(cached_str)
            _MEMORY_CACHE[lang] = data
            _CACHE_TIME[lang] = now
            return data
    except Exception as e:
        logger.debug("[i18n._get_t] Redis senkron okuma hatası (%s): %s", lang, e)

    # 2. Redis'te yoksa Veritabanından (translations tablosu) senkron okumayı dene
    try:
        from sqlalchemy import create_engine, text
        from app.config import settings
        sync_db_url = settings.database_url.replace("+asyncpg", "").replace("+aiosqlite", "")
        engine = create_engine(sync_db_url, pool_pre_ping=True, connect_args={"connect_timeout": 3})
        with engine.connect() as conn:
            res = conn.execute(text("SELECT key, value FROM translations WHERE lang = :lang"), {"lang": lang})
            data = {row.key: row.value for row in res}
            if data:
                _MEMORY_CACHE[lang] = data
                _CACHE_TIME[lang] = now
                # Redis'i de güncelleyelim
                try:
                    import redis as sync_redis
                    r = sync_redis.Redis.from_url(settings.redis_url, decode_responses=True, socket_timeout=2.0)
                    r.set(f"i18n:{lang}", json.dumps(data, ensure_ascii=False), ex=3600)
                except Exception:
                    pass
                return data
    except Exception as e:
        logger.debug("[i18n._get_t] DB senkron okuma hatası (%s): %s", lang, e)

    # 3. Her iki kaynak da başarısız olursa elimizdeki süresi dolmuş eski belleği dön (Stale-while-error)
    if lang in _MEMORY_CACHE and _MEMORY_CACHE[lang]:
        return _MEMORY_CACHE[lang]

    # 4. Hiçbir şey yoksa ve dil tr değilse Türkçe'ye (tr) fallback yap
    if lang != "tr":
        return _get_t("tr")
    return {}


async def preload_i18n_cache() -> None:
    """
    Uygulama açılışında (FastAPI startup / lifespan) çağrılır.
    Tüm desteklenen dilleri (tr, en, ar, ru) asenkron olarak Redis/DB üzerinden belleğe yükler.
    Böylece ilk isteklerde (cold start) senkron DB/Redis I/O gecikmesi yaşanmaz.
    """
    logger.info("[i18n] Tüm diller için bellek ön belleği (pre-load) başlatılıyor...")
    now = time.time()
    try:
        from app.utils.redis_client import get_redis
        from app.database import AsyncSessionLocal
        from sqlalchemy import text

        redis = await get_redis()
        async with AsyncSessionLocal() as db:
            for lang in _SUPPORTED:
                try:
                    cached_str = await redis.get(f"i18n:{lang}")
                    if cached_str:
                        _MEMORY_CACHE[lang] = json.loads(cached_str)
                        _CACHE_TIME[lang] = now
                        logger.debug("[i18n] %s dili Redis'ten belleğe yüklendi (%d key)", lang, len(_MEMORY_CACHE[lang]))
                        continue

                    # Redis'te yoksa DB'den çek
                    res = await db.execute(
                        text("SELECT key, value FROM translations WHERE lang = :lang"),
                        {"lang": lang}
                    )
                    data = {row.key: row.value for row in res}
                    if data:
                        _MEMORY_CACHE[lang] = data
                        _CACHE_TIME[lang] = now
                        await redis.set(f"i18n:{lang}", json.dumps(data, ensure_ascii=False), ex=3600)
                        logger.debug("[i18n] %s dili DB'den belleğe ve Redis'e yüklendi (%d key)", lang, len(data))
                except Exception as e_lang:
                    logger.warning("[i18n] %s dili pre-load edilemedi: %s", lang, e_lang)
        logger.info("[i18n] Pre-load tamamlandı. Bellek durumu: %s", {k: len(v) for k, v in _MEMORY_CACHE.items()})
    except Exception as e:
        logger.error("[i18n] Pre-load genel hatası: %s", e)


_SUPPORTED = {"tr", "en", "ar", "ru"}

def get_locale(user=None, request=None, default: str = "tr") -> str:
    """
    Öncelik: Accept-Language header > user.locale (DB) > default.

    Request header önce gelir çünkü kullanıcının o andaki uygulama
    dilini yansıtır; DB değeri senkronizasyon gecikmesinden etkilenebilir.
    """
    if request is not None:
        al = request.headers.get("accept-language", "")
        for part in al.replace(",", ";").split(";"):
            lang = part.strip()[:2].lower()
            if lang in _SUPPORTED:
                return lang
    if user:
        loc = getattr(user, "locale", None)
        if loc and loc in _SUPPORTED:
            return loc
    return default

def _msg(request, data, key: str, default: str) -> str:
    lang = getattr(data, 'lang', None) if data else None
    if not lang and request:
        lang = get_locale(request=request)
    if not lang:
        lang = "tr"
    return _get_t(lang).get(key, default)
