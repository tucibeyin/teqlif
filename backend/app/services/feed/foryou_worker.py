import logging
import json
from sqlalchemy import select
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.enums import UserStatus
from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

_FORYOU_TTL = 3600        # 1 saat — saat başı cron ile yenilenir
_POOL_SIZE   = 500        # BPR + recent birleşiminden alınan max ilan
_MAX_FEED    = 500        # Redis list max uzunluğu
_MAX_PER_SUBCAT = 2       # Greedy diversity


async def populate_foryou_feed_task(ctx: dict) -> None:
    """
    Her aktif kullanıcının ilgi alanlarını ve BPR verilerini değerlendirip
    'Sana Özel' Redis listesini (feed:{user_id}:foryou) baştan doldurur.

    Saatte bir cron job ile çalışır. Her listenin TTL'i _FORYOU_TTL ile sınırlıdır;
    cron tetiklenmese bile bayat veri gösterilmez.
    """
    try:
        redis = await get_redis()

        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(User.id).where(User.status == UserStatus.ACTIVE)
            )
            users = result.scalars().all()

        # recent feed'i bir kez çek — tüm kullanıcılar için paylaşımlı havuz
        recent_raw = await redis.zrevrange("feed:recent", 0, _POOL_SIZE - 1)
        recent_listings = [int(lid) for lid in recent_raw]

        # Aktif listing meta-verilerini toplu çek
        if recent_listings:
            listing_keys = [f"listing:{lid}" for lid in recent_listings]
            listing_metas_raw = await redis.mget(*listing_keys)
            listing_meta: dict[int, dict] = {}
            for lid, raw in zip(recent_listings, listing_metas_raw):
                if raw:
                    try:
                        listing_meta[lid] = json.loads(raw)
                    except Exception:
                        pass
        else:
            listing_meta = {}

        for uid in users:
            bpr_data = await redis.get(f"bpr:rec:{uid}")
            bpr_listings = json.loads(bpr_data) if bpr_data else []

            # BPR öncelikli + recent birleşimi (duplicate yok)
            seen: set[int] = set()
            combined_pool: list[int] = []
            for lid in bpr_listings:
                if lid not in seen:
                    seen.add(lid)
                    combined_pool.append(lid)
            for lid in recent_listings:
                if lid not in seen:
                    seen.add(lid)
                    combined_pool.append(lid)

            # Greedy diversity
            final_feed: list[int] = []
            subcat_counts: dict[str, int] = {}

            for lid in combined_pool:
                if len(final_feed) >= _MAX_FEED:
                    break
                meta = listing_meta.get(lid)
                if not meta or meta.get("status") != "active":
                    continue
                subcat = meta.get("subcategory")
                if subcat:
                    if subcat_counts.get(subcat, 0) >= _MAX_PER_SUBCAT:
                        continue
                    subcat_counts[subcat] = subcat_counts.get(subcat, 0) + 1
                final_feed.append(lid)

            foryou_key = f"feed:{uid}:foryou"
            if final_feed:
                pipe = redis.pipeline()
                pipe.delete(foryou_key)
                pipe.rpush(foryou_key, *final_feed)
                pipe.expire(foryou_key, _FORYOU_TTL)
                await pipe.execute()
            else:
                await redis.delete(foryou_key)

        logger.info("[ForYouWorker] Sana Özel feed'leri %d kullanıcı için yenilendi.", len(users))
    except Exception as e:
        logger.error("[ForYouWorker] Hata: %s", e, exc_info=True)
        raise
