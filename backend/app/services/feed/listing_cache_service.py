import json
import logging
from datetime import datetime
from typing import Optional

from app.models.listing import Listing
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

LISTING_CACHE_PREFIX = "listing:"
LISTING_CACHE_TTL = 7 * 86400  # 7 gün (Pasif veya eski ilanlar otomatik temizlensin)

def _serialize_datetime(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None

def _parse_image_urls(image_urls_raw) -> list:
    if image_urls_raw is None:
        return []
    if isinstance(image_urls_raw, list):
        return image_urls_raw
    try:
        parsed = json.loads(image_urls_raw)
        return parsed if isinstance(parsed, list) else []
    except (json.JSONDecodeError, TypeError):
        return []

def build_listing_snapshot(listing: Listing) -> dict:
    """
    ORM objesinden plain dict oluşturur.
    Session açıkken (commit öncesi) çağrılmalı — asyncio.create_task'a geçmeden önce.
    """
    return {
        "id": listing.id,
        "user_id": listing.user_id,
        "title": listing.title,
        "description": listing.description,
        "price": float(listing.price) if listing.price is not None else None,
        "category": listing.category,
        "subcategory": listing.subcategory,
        "brand": listing.brand,
        "condition": listing.condition,
        "extra_fields": listing.extra_fields,
        "image_url": listing.image_url,
        "image_urls": _parse_image_urls(listing.image_urls),
        "thumbnail_url": listing.thumbnail_url,
        "video_url": listing.video_url,
        "location": listing.location,
        "status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status),
        "created_at": _serialize_datetime(listing.created_at),
        "updated_at": _serialize_datetime(listing.updated_at),
        "deactivated_at": _serialize_datetime(listing.deactivated_at),
        "expires_at": _serialize_datetime(listing.expires_at),
        "is_highlight": listing.is_highlight,
        "buy_it_now_price": float(listing.buy_it_now_price) if listing.buy_it_now_price is not None else None,
    }


async def cache_listing(listing: Listing) -> None:
    """Session içinde await ile çağrılacaksa kullanılabilir (create_task için DEĞİL)."""
    await cache_listing_snapshot(build_listing_snapshot(listing))


async def cache_listing_snapshot(data: dict) -> None:
    """
    Plain dict'i Redis'e yazar. create_task için güvenli — ORM erişimi yok.
    """
    try:
        redis = await get_redis()
        key = f"{LISTING_CACHE_PREFIX}{data['id']}"
        await redis.setex(key, LISTING_CACHE_TTL, json.dumps(data))
        logger.debug("[ListingCacheService] İlan Redis'e yazıldı: %s", key)
    except Exception as e:
        logger.error("[ListingCacheService] İlan cache'lenirken hata: %s", e, exc_info=True)


async def invalidate_listing(listing_id: int) -> None:
    """
    İlan silindiğinde, askıya alındığında veya durumu güncellendiğinde cache'i temizler.
    """
    try:
        redis = await get_redis()
        key = f"{LISTING_CACHE_PREFIX}{listing_id}"
        await redis.delete(key)
        
        # Ayrıca recent feed'den de çıkaralım
        await remove_from_recent_feed_cache(listing_id)
        
        logger.debug("[ListingCacheService] İlan Redis'ten silindi: %s", key)
    except Exception as e:
        logger.error("[ListingCacheService] İlan cache'den silinirken hata: %s", e, exc_info=True)


async def push_to_recent_feed_cache(listing_id: int) -> None:
    """
    Yeni eklenen ilanı (id'sini) feed:recent ZSET yapısına yazar. Score olarak ID'si kullanılır.
    Bu sayede since_id ve max_id tabanlı (id büyüklüğüne göre) paginasyon yapılabilir.
    Ayrıca ZSET'in çok büyümemesi için maksimum 2000 eleman tutar.
    """
    try:
        redis = await get_redis()
        score = listing_id

        await redis.zadd("feed:recent", {str(listing_id): score})

        # Sadece son 2000 ilanı tutalım (performans için yeterli)
        # 0'dan başlayıp -2001'inci elemana kadar olanları siliyoruz (en düşük score'lar silinir)
        card = await redis.zcard("feed:recent")
        if card > 2000:
            await redis.zremrangebyrank("feed:recent", 0, -2001)

        logger.debug("[ListingCacheService] İlan feed:recent'a eklendi: %d", listing_id)
    except Exception as e:
        logger.error("[ListingCacheService] İlan feed:recent'a eklenirken hata: %s", e, exc_info=True)


async def remove_from_recent_feed_cache(listing_id: int) -> None:
    """
    Silinen veya pasife alınan ilanı feed:recent listesinden temizler.
    """
    try:
        redis = await get_redis()
        await redis.zrem("feed:recent", str(listing_id))
    except Exception as e:
        logger.error("[ListingCacheService] İlan feed:recent'tan silinirken hata: %s", e, exc_info=True)
