"""
feed:recent Redis ZSET'ini aktif ilanlarla doldurur.

Servis başlangıcında (ExecStartPre / sync_main.py) çalışır.
ZSET boş veya eksikse DB'deki tüm active listing ID'lerini yükler.
ZSET zaten doluysa dokunmaz — idempotent.

Kural: ZSET her zaman yalnızca status='active' ilan ID'lerini içerir.
Score = listing.id → ID sırasına göre sıralama = oluşturulma sırasına göre sıralama.
"""
import logging
import os
import sys

from dotenv import load_dotenv

backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(backend_dir)
_env_file = os.environ.get("TEQLIF_ENV_FILE", "")
load_dotenv(_env_file, override=False)

import sqlalchemy as sa

from app.database import AsyncSessionLocal
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

_ZSET_KEY       = "feed:recent"
_MAX_ENTRIES    = 2000
_WARM_THRESHOLD = 50   # Bu sayının altındaysa yeniden doldur


async def warm_feed_cache() -> None:
    """feed:recent ZSET'ini DB'den doldurur (yalnızca eksikse)."""
    redis = await get_redis()

    current_size = await redis.zcard(_ZSET_KEY)
    if current_size >= _WARM_THRESHOLD:
        logger.info("[sync_feed_cache] feed:recent zaten dolu (%d item), atlandı.", current_size)
        return

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            sa.text(
                "SELECT id FROM listings WHERE status = 'active' "
                "ORDER BY id DESC LIMIT :lim"
            ),
            {"lim": _MAX_ENTRIES},
        )
        ids = [row.id for row in result]

    if not ids:
        logger.info("[sync_feed_cache] DB'de aktif ilan yok, ZSET doldurulmadı.")
        return

    mapping = {str(lid): lid for lid in ids}
    await redis.zadd(_ZSET_KEY, mapping)
    logger.info(
        "[sync_feed_cache] feed:recent dolduruldu: %d item (önceki: %d).",
        len(ids), current_size,
    )


if __name__ == "__main__":
    import asyncio
    logging.basicConfig(level=logging.INFO)
    asyncio.run(warm_feed_cache())
