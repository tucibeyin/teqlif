"""
feed:recent Redis ZSET'ini aktif ilanlarla yeniden oluşturur.

Servis başlangıcında (ExecStartPre / sync_main.py) çalışır.
Her seferinde ZSET'i sıfırdan inşa eder: DEL + ZADD ile DB'deki tüm
active listing ID'lerini yükler. Bu sayede stale entry kalmaz.

Kural: ZSET her zaman yalnızca status='active' ilan ID'lerini içerir.
Score = listing.id → ID sırasına göre sıralama = oluşturulma sırasına göre sıralama.
"""
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

_ZSET_KEY    = "feed:recent"
_MAX_ENTRIES = 2000


async def warm_feed_cache() -> None:
    """feed:recent ZSET'ini DB'den sıfırdan yeniden inşa eder."""
    redis = await get_redis()
    old_size = await redis.zcard(_ZSET_KEY)

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
        print("[sync_feed_cache] DB'de aktif ilan yok, ZSET doldurulmadı.")
        return

    await redis.delete(_ZSET_KEY)
    mapping = {str(lid): lid for lid in ids}
    await redis.zadd(_ZSET_KEY, mapping)
    print(f"[sync_feed_cache] feed:recent yenilendi: {len(ids)} item (önceki: {old_size}).")


if __name__ == "__main__":
    import asyncio
    asyncio.run(warm_feed_cache())
