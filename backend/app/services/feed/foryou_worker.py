import logging
import json
from datetime import datetime, timezone, timedelta
from sqlalchemy import select, or_
from app.database import AsyncSessionLocal
from app.models.user import User
from app.models.enums import UserStatus
from app.utils.redis_client import get_redis
from app.schedule_loader import get_ttl

logger = logging.getLogger(__name__)

_FORYOU_TTL     = get_ttl("foryou_feed_seconds", default=86400)  # schedule.yaml ttl.foryou_feed_seconds
_POOL_SIZE      = 500        # BPR + recent birleşiminden alınan max ilan
_MAX_FEED       = 500        # Redis list max uzunluğu
_MAX_PER_SUBCAT = 2          # Greedy diversity
_CHUNK_SIZE     = 500        # mget / pipeline batch büyüklüğü
_ACTIVE_DAYS    = 7          # Son N gün içinde giriş yapmayan kullanıcılar atlanır


async def populate_foryou_feed_task(ctx: dict) -> None:
    """
    Her aktif kullanıcının ilgi alanlarını ve BPR verilerini değerlendirip
    'Sana Özel' Redis string'ini (feed:foryou:{user_id}) baştan doldurur.

    Günde 4x cron job ile çalışır (00:20, 06:20, 12:20, 18:20).
    """
    try:
        redis = await get_redis()

        # Hayalet kullanıcıları atla: son 7 gün içinde giriş yok ve last_active_at dolu
        cutoff = datetime.now(timezone.utc) - timedelta(days=_ACTIVE_DAYS)
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(User.id).where(
                    User.status == UserStatus.ACTIVE,
                    or_(
                        User.last_active_at.is_(None),
                        User.last_active_at >= cutoff,
                    ),
                )
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

        # Kullanıcıları 500'lük chunk'lara böl: mget + pipeline ile N+1 önlenir
        for i in range(0, len(users), _CHUNK_SIZE):
            chunk = users[i : i + _CHUNK_SIZE]

            bpr_keys = [f"bpr:rec:{uid}" for uid in chunk]
            bpr_raws = await redis.mget(*bpr_keys)

            writes: list[tuple[int, str | None]] = []
            for uid, bpr_raw in zip(chunk, bpr_raws):
                bpr_listings = json.loads(bpr_raw) if bpr_raw else []

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

                writes.append((uid, json.dumps(final_feed) if final_feed else None))

            async with redis.pipeline(transaction=False) as pipe:
                for uid, feed_data in writes:
                    foryou_key = f"feed:foryou:{uid}"
                    if feed_data is not None:
                        pipe.set(foryou_key, feed_data, ex=_FORYOU_TTL)
                    else:
                        pipe.delete(foryou_key)
                await pipe.execute()

        logger.info("[ForYouWorker] Sana Özel feed'leri %d kullanıcı için yenilendi.", len(users))
        from app.worker import _agent_ok
        await _agent_ok(ctx, "populate_foryou_feed_task")
    except Exception as e:
        logger.error("[ForYouWorker] Hata: %s", e, exc_info=True)
        raise
