"""
İlan servisi — iş mantığını router'dan ayırır.

ListingService sınıfı; ilan listeleme, detay, oluşturma, aktif/pasif
geçişi ve silme işlemlerini yönetir.

Dependency Injection:
    db: AsyncSession — constructor üzerinden alınır (FastAPI Depends ile inject edilir)

Hata Yönetimi:
    DB yazma hataları → logger.error + capture_exception → DatabaseException (500)
    İş kuralları      → BadRequest / NotFound / TooManyRequests / Conflict
"""
import json
import calendar
from typing import Optional
from datetime import datetime, timezone, date

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, delete, text as sql_text

from app.models.enums import ListingStatus, SearchAlertStatus
from app.models.listing import Listing
from app.models.listing_offer import ListingOffer
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.models.listing_impression import ListingImpression
from app.models.tuci_transaction import TuciTransaction
from app.services.like_service import LikeService
from app.schemas.stream import VALID_CATEGORIES
from app.core.exceptions import (
    NotFoundException,
    BadRequestException,
    ContentPolicyException,
    TooManyRequestsException,
    ConflictException,
    DatabaseException,
)
from app.core.action_guard import check_user_action_rate, acquire_action_lock, release_action_lock
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)

# ── İlan Reaktivasyon Kredisi (PRO) ──────────────────────────────────────────
_REACTIVATION_FREE_MONTHLY = 5   # PRO: ayda 5 ücretsiz reaktivasyon
_REACTIVATION_COST_TUCI    = 10  # Hak bitince veya normal kullanıcı: 10 TUCi


def _reactivation_billing_start(premium_since: datetime) -> date:
    today = date.today()
    day   = premium_since.day
    last_this = calendar.monthrange(today.year, today.month)[1]
    ann_this  = date(today.year, today.month, min(day, last_this))
    if today >= ann_this:
        return ann_this
    prev_m = today.month - 1 if today.month > 1 else 12
    prev_y = today.year if today.month > 1 else today.year - 1
    return date(prev_y, prev_m, min(day, calendar.monthrange(prev_y, prev_m)[1]))


def _reactivation_next_billing(premium_since: datetime) -> date:
    p   = _reactivation_billing_start(premium_since)
    day = premium_since.day
    nm  = p.month + 1 if p.month < 12 else 1
    ny  = p.year if p.month < 12 else p.year + 1
    return date(ny, nm, min(day, calendar.monthrange(ny, nm)[1]))


def _reactivation_redis_key(user_id: int, premium_since: datetime | None = None) -> str:
    if premium_since:
        period = _reactivation_billing_start(premium_since)
        return f"reactivation_credits:{user_id}:{period.isoformat()}"
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    return f"reactivation_credits:{user_id}:{month}"


async def _get_reactivation_used(user_id: int, premium_since: datetime | None = None) -> int:
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        val = await redis.get(_reactivation_redis_key(user_id, premium_since))
        return int(val) if val else 0
    except Exception:
        return 0


async def _increment_reactivation(user_id: int, premium_since: datetime | None = None) -> None:
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        key   = _reactivation_redis_key(user_id, premium_since)
        count = await redis.incr(key)
        if count == 1:
            now = datetime.now(timezone.utc)
            if premium_since:
                nxt    = _reactivation_next_billing(premium_since)
                end_dt = datetime(nxt.year, nxt.month, nxt.day, 0, 0, 0, tzinfo=timezone.utc)
            else:
                last_day = calendar.monthrange(now.year, now.month)[1]
                end_dt   = now.replace(day=last_day, hour=23, minute=59, second=59)
            ttl = int((end_dt - now).total_seconds()) + 1
            await redis.expire(key, ttl)
    except Exception:
        pass


# ── Yardımcı: model → dict dönüşümü ─────────────────────────────────────────
async def _fetch_seller_meta(
    user_ids: list[int],
) -> tuple[dict[int, str | None], set[str], set[int], dict[int, int | None], dict[int, int | None]]:
    """
    Batch olarak Redis'ten seller_badge, trending kategoriler, trending listing ID'leri,
    trust_score ve influence_rank çeker.
    Döner: (badge_map, trending_categories, trending_listing_ids, trust_map, influence_map)
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        badge_keys     = [f"seller:badge:{uid}"   for uid in user_ids]
        trust_keys     = [f"trust_score:{uid}"     for uid in user_ids]
        influence_keys = [f"influence_rank:{uid}"  for uid in user_ids]
        all_keys = badge_keys + trust_keys + influence_keys
        all_vals = await redis.mget(*all_keys) if all_keys else []
        n = len(user_ids)
        badge_vals, trust_vals, inf_vals = all_vals[:n], all_vals[n:2*n], all_vals[2*n:]
        badge_map    = {uid: (val or None) for uid, val in zip(user_ids, badge_vals)}
        trust_map    = {uid: (int(val) if val is not None else None) for uid, val in zip(user_ids, trust_vals)}
        influence_map= {uid: (int(val) if val is not None else None) for uid, val in zip(user_ids, inf_vals)}
        trending_cats = set(await redis.smembers("trending:categories") or [])
        trending_listing_ids = {int(v) for v in (await redis.smembers("trending:listings") or [])}
        return badge_map, trending_cats, trending_listing_ids, trust_map, influence_map
    except Exception as exc:
        logger.warning("[SellerMeta] Redis fetch başarısız — badge/trending boş dönüyor: %s", exc)
        return {}, set(), set(), {}, {}


def _row_dict(
    listing: Listing,
    user: User,
    likes_count: int = 0,
    is_liked: bool = False,
    is_sponsored: bool = False,
    campaign_id: Optional[int] = None,
    seller_badge: str | None = None,
    is_trending: bool = False,
    impression_count: Optional[int] = None,
    seller_trust_score: int | None = None,
    seller_influence_rank: int | None = None,
) -> dict:
    return {
        "id": listing.id,
        "title": listing.title,
        "description": listing.description,
        "price": listing.price,
        "category": listing.category,
        "location": listing.location,
        "image_url": listing.image_url,
        "image_urls": json.loads(listing.image_urls) if listing.image_urls else [],
        "thumbnail_url": listing.thumbnail_url,
        "video_url": listing.video_url,
        "created_at": listing.created_at.isoformat() if listing.created_at else None,
        "status": (listing.status == ListingStatus.ACTIVE).value,
        "user": {
            "id": user.id,
            "username": user.username,
            "full_name": user.full_name,
            "trust_score": seller_trust_score,
            "influence_rank": seller_influence_rank,
        },
        "likes_count": likes_count,
        "is_liked": is_liked,
        "is_sponsored": is_sponsored,
        "campaign_id": campaign_id,
        "seller_is_premium": user.is_premium,
        "seller_badge": seller_badge,
        "is_trending": is_trending,
        "impression_count": impression_count,
        "is_highlight": listing.is_highlight,
        "active_room_id": listing.active_room_id,
    }


async def _trigger_search_alerts(listing_id: int, category: Optional[str], price: Optional[float]) -> None:
    """
    Yeni ilan oluşturulduğunda eşleşen arama alarmlarına push bildirimi gönderir.
    Fire-and-forget — hata olursa loglanır, akışı durdurmaz.
    """
    try:
        from app.database import AsyncSessionLocal
        from app.models.search_alert import SearchAlert
        from app.routers.notifications import push_notification

        async with AsyncSessionLocal() as db:
            q = select(SearchAlert).where(SearchAlert.status == SearchAlertStatus.ACTIVE)  # noqa: E712
            if category:
                q = q.where((SearchAlert.category == category) | (SearchAlert.category.is_(None)))
            if price is not None:
                q = q.where((SearchAlert.max_price >= price) | (SearchAlert.max_price.is_(None)))
            result = await db.execute(q.limit(200))
            alerts = result.scalars().all()

        _cat_key = f"cat_{category}" if category else "cat_diger"
        import asyncio as _aio
        async def _send(a: SearchAlert) -> None:
            try:
                await push_notification(
                    user_id=a.user_id,
                    notif={
                        "type": "search_alert",
                        "i18n": {
                            "title_key": "notifSearchAlert",
                            "body_key": "notifSearchAlertBody",
                            "body_params": {"category": _cat_key},
                        },
                        "related_id": listing_id,
                    },
                    pref_key="search_alert",
                )
            except Exception:
                pass

        for i in range(0, len(alerts), 20):
            await _aio.gather(*[_send(a) for a in alerts[i:i + 20]])
    except Exception as exc:
        logger.warning("[SearchAlert] Trigger başarısız | listing_id=%s | %s", listing_id, exc)


# ── Servis sınıfı ────────────────────────────────────────────────────────────
class ListingService:
    """
    Tüm ilan iş mantığını barındıran servis sınıfı.

    Kullanım:
        svc = ListingService(db)
        listings = await svc.get_listings(user_id=1, category="elektronik")
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    @staticmethod
    async def _fetch_unique_reach(db: AsyncSession, impression_map: dict[int, int], listing_ids: list[int]) -> None:
        """listing_impressions tablosundan her ilanı kaç farklı kişinin gördüğünü döndürür (unique reach)."""
        if not listing_ids:
            return
        try:
            result = await db.execute(
                select(ListingImpression.listing_id, func.count(func.distinct(ListingImpression.user_id)))
                .where(ListingImpression.listing_id.in_(listing_ids))
                .group_by(ListingImpression.listing_id)
            )
            for lid, count in result.all():
                impression_map[lid] = count
        except Exception as e:
            logger.warning("[ListingService] Unique reach fetch failed: %s", e)

    # ── İlan Listele ─────────────────────────────────────────────────────────
    async def get_listings(
        self,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        location: Optional[str] = None,
        q: Optional[str] = None,
        current_user_id: Optional[int] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list:
        q_stmt = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.status == ListingStatus.ACTIVE,    # noqa: E712
                Listing.status != ListingStatus.DELETED,  # noqa: E712
                or_(Listing.expires_at == None, Listing.expires_at > datetime.now(timezone.utc)),  # noqa: E711
            )
        )
        if user_id:
            q_stmt = q_stmt.where(Listing.user_id == user_id)
        if category:
            q_stmt = q_stmt.where(Listing.category == category)
        if location:
            q_stmt = q_stmt.where(Listing.location.ilike(f"%{location}%"))
        
        if q:
            # Using basic substring search (ilike) alongside pg_trgm for typo-tolerance
            search_term = f"%{q}%"
            q_stmt = q_stmt.where(
                or_(
                    Listing.title.ilike(search_term),
                    Listing.description.ilike(search_term),
                    Listing.title.op('%')(q),
                    func.similarity(Listing.title, q) > 0.15,
                    func.similarity(Listing.description, q) > 0.15
                )
            )
            # Order by similarity if query is provided, and then by other heuristics
            q_stmt = q_stmt.order_by(
                func.greatest(
                    func.similarity(Listing.title, q),
                    func.similarity(Listing.description, q)
                ).desc(),
                User.is_premium.desc(), 
                Listing.created_at.desc()
            ).limit(limit).offset(offset)
        else:
            q_stmt = q_stmt.order_by(User.is_premium.desc(), Listing.created_at.desc()).limit(limit).offset(offset)
            
        result = await self.db.execute(q_stmt)
        rows = result.all()

        listing_ids = [listing.id for listing, _ in rows]
        user_ids = list({user.id for _, user in rows})
        counts, liked_set = await LikeService.batch_listing_likes(
            self.db, listing_ids, current_user_id
        )
        campaign_map: dict[int, int] = {}
        if listing_ids:
            camp_result = await self.db.execute(
                select(AdCampaign.listing_id, AdCampaign.id)
                .where(
                    AdCampaign.listing_id.in_(listing_ids),
                    AdCampaign.status.in_(["active", "paused"]),
                )
            )
            for lid, cid in camp_result.all():
                campaign_map.setdefault(lid, cid)
        badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta(user_ids)

        # Sadece mevcut kullanıcıya ait olan ilanların görüntülenmelerini çek
        impression_map: dict[int, int] = {}
        if current_user_id and listing_ids:
            my_listing_ids = [l.id for l, u in rows if u.id == current_user_id]
            if my_listing_ids:
                await self._fetch_unique_reach(self.db, impression_map, my_listing_ids)

        return [
            _row_dict(
                listing, user,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=listing.id in campaign_map,
                campaign_id=campaign_map.get(listing.id),
                seller_badge=badge_map.get(user.id),
                is_trending=listing.category in trending_cats or listing.id in trending_lids,
                impression_count=impression_map.get(listing.id, 0) if user.id == current_user_id else None,
                seller_trust_score=trust_map.get(user.id),
                seller_influence_rank=influence_map.get(user.id),
            )
            for listing, user in rows
        ]

    # ── Kendi İlanlarım ──────────────────────────────────────────────────────
    async def get_my_listings(self, current_user: User, active: Optional[bool] = None, q: Optional[str] = None, category: Optional[str] = None, limit: int = 50, offset: int = 0, start_date: Optional[str] = None, end_date: Optional[str] = None) -> list:
        query = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.user_id == current_user.id, Listing.status != ListingStatus.DELETED)  # noqa: E712
        )
        if active is not None:
            query = query.where(Listing.status == ListingStatus.ACTIVE if active else Listing.status != ListingStatus.ACTIVE)  # noqa: E712
        if category:
            query = query.where(Listing.category == category)
        if q:
            query = query.where(Listing.title.ilike(f"%{q}%"))
        if start_date:
            from datetime import datetime
            try:
                sd = datetime.strptime(start_date, '%Y-%m-%d')
                query = query.where(Listing.created_at >= sd)
            except ValueError:
                pass
        if end_date:
            from datetime import datetime, timedelta
            try:
                ed = datetime.strptime(end_date, '%Y-%m-%d') + timedelta(days=1)
                query = query.where(Listing.created_at < ed)
            except ValueError:
                pass

        query = query.order_by(Listing.created_at.desc()).limit(limit).offset(offset)
        result = await self.db.execute(query)
        rows = result.all()

        listing_ids = [listing.id for listing, _ in rows]
        counts, liked_set = await LikeService.batch_listing_likes(
            self.db, listing_ids, current_user.id
        )
        campaign_map: dict[int, int] = {}
        if listing_ids:
            camp_result = await self.db.execute(
                select(AdCampaign.listing_id, AdCampaign.id)
                .where(
                    AdCampaign.listing_id.in_(listing_ids),
                    AdCampaign.status.in_(["active", "paused"]),
                )
            )
            for lid, cid in camp_result.all():
                campaign_map.setdefault(lid, cid)
        badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta([current_user.id])

        impression_map: dict[int, int] = {}
        if listing_ids:
            await self._fetch_unique_reach(self.db, impression_map, listing_ids)

        return [
            _row_dict(
                listing, user,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=listing.id in campaign_map,
                campaign_id=campaign_map.get(listing.id),
                seller_badge=badge_map.get(user.id),
                is_trending=listing.category in trending_cats or listing.id in trending_lids,
                impression_count=impression_map.get(listing.id, 0),
                seller_trust_score=trust_map.get(user.id),
                seller_influence_rank=influence_map.get(user.id),
            )
            for listing, user in rows
        ]

    # ── İlan Detayı ──────────────────────────────────────────────────────────
    async def get_listing(
        self, listing_id: int, current_user_id: Optional[int] = None
    ) -> dict:
        result = await self.db.execute(
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED)  # noqa: E712
        )
        row = result.first()
        if not row:
            raise NotFoundException("İlan bulunamadı")
        listing, user = row
        counts, liked_set = await LikeService.batch_listing_likes(
            self.db, [listing.id], current_user_id
        )
        camp_result = await self.db.execute(
            select(AdCampaign.id)
            .where(
                AdCampaign.listing_id == listing.id,
                AdCampaign.status.in_(["active", "paused"]),
            )
            .limit(1)
        )
        campaign_id = camp_result.scalar_one_or_none()
        badge_map, trending_cats, trending_lids, trust_map, influence_map = await _fetch_seller_meta([user.id])
        impression_count: Optional[int] = None
        if current_user_id == listing.user_id:
            imp_map = {}
            await self._fetch_unique_reach(self.db, imp_map, [listing.id])
            impression_count = imp_map.get(listing.id, 0)

        return _row_dict(
            listing, user,
            counts.get(listing.id, 0), listing.id in liked_set,
            is_sponsored=campaign_id is not None,
            campaign_id=campaign_id,
            seller_badge=badge_map.get(user.id),
            is_trending=listing.category in trending_cats or listing.id in trending_lids,
            impression_count=impression_count,
            seller_trust_score=trust_map.get(user.id),
            seller_influence_rank=influence_map.get(user.id),
        )

    # ── İlan Oluştur ─────────────────────────────────────────────────────────
    async def create_listing(self, payload: dict, current_user: User) -> dict:
        uid = current_user.id

        # 1. Kullanıcı bazlı hız sınırı: dakikada 1 ilan
        allowed, retry_after = await check_user_action_rate(uid, "listing_create", limit=1, window=60)
        if not allowed:
            logger.warning("[LISTINGS] Hız sınırı aşıldı | user_id=%s | retry_after=%s", uid, retry_after)
            raise TooManyRequestsException(
                "Dakikada en fazla 1 ilan oluşturabilirsiniz. Lütfen bekleyin.",
                retry_after=retry_after,
            )

        # 2. Idempotency kilidi: 3 saniyelik race condition koruması
        if not await acquire_action_lock(uid, "listing_create", ttl=3):
            logger.warning("[LISTINGS] Çift istek engellendi | user_id=%s", uid)
            raise ConflictException("İsteğiniz zaten işleniyor. Lütfen bekleyin.")

        # Profanity kontrolü: title + description
        from app.core.auto_mod import analyze_listing_text
        _title = (payload.get("title") or "").strip()
        _desc = (payload.get("description") or "").strip()
        if analyze_listing_text(_title, _desc):
            await release_action_lock(uid, "listing_create")
            raise ContentPolicyException()

        category = (payload.get("category") or "diger").strip().lower()
        if category not in VALID_CATEGORIES:
            await release_action_lock(uid, "listing_create")
            raise BadRequestException(f"Geçersiz kategori: {category}")

        listing = Listing(
            user_id=uid,
            title=payload.get("title", ""),
            description=payload.get("description"),
            price=payload.get("price"),
            category=category,
            location=payload.get("location"),
            image_url=payload.get("image_url"),
            image_urls=json.dumps(payload.get("image_urls") or []),
            thumbnail_url=payload.get("thumbnail_url"),
            video_url=payload.get("video_url"),
        )
        self.db.add(listing)
        try:
            await self.db.commit()
            await self.db.refresh(listing)
        except Exception as exc:
            await self.db.rollback()
            await release_action_lock(uid, "listing_create")
            logger.error(
                "[LISTINGS] İlan DB'ye kaydedilemedi | user_id=%s | %s",
                uid, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("İlan oluşturulamadı")

        # Commit başarılı — kilidi serbest bırak
        await release_action_lock(uid, "listing_create")
        logger.info("[LISTINGS] İlan oluşturuldu | user_id=%s listing_id=%s", uid, listing.id)

        import asyncio as _asyncio2
        from app.database_clickhouse import track_user_event
        _asyncio2.create_task(track_user_event(
            event_type="listing_created",
            item_id=listing.id,
            item_type="listing",
            user_id=uid,
            price_point=float(listing.price) if listing.price is not None else None,
        ))

        # search_vector doldur (FTS için)
        try:
            from sqlalchemy import text as _text
            await self.db.execute(_text("""
                UPDATE listings SET search_vector =
                    to_tsvector('turkish',
                        coalesce(title, '') || ' ' || coalesce(description, ''))
                WHERE id = :lid
            """), {"lid": listing.id})
            await self.db.commit()
        except Exception:
            pass

        # Takipçilere new_listing bildirimi (non-blocking, fire-and-forget)
        # Follower ID'leri commit sonrası burada çekiliyor; background task session'a dokunmuyor.
        import asyncio as _asyncio
        from app.models.follow import Follow
        from app.routers.notifications import push_notification

        try:
            follower_ids = list(await self.db.scalars(
                select(Follow.follower_id).where(Follow.followed_id == uid)
            ))
        except Exception:
            follower_ids = []

        notif_payload = {
            "type": "new_listing",
            "i18n": {
                "title_key": "notifNewListing",
                "title_params": {"username": current_user.username},
            },
            "body": listing.title or None,
            "related_id": listing.id,
            "listing_id": listing.id,
        }

        async def _notify_followers():
            for follower_id in follower_ids:
                try:
                    await push_notification(
                        user_id=follower_id,
                        notif=notif_payload,
                        pref_key="new_listing",
                    )
                except Exception as exc:
                    logger.error("[LISTINGS] Takipçi bildirimi gönderilemedi | user_id=%s", follower_id, exc_info=True)
                    capture_exception(exc)

        _asyncio.create_task(_notify_followers())

        # Budget-match bildirimi: 3 dk sonra çalışır (embedding worker için süre tanır)
        try:
            from app.utils.arq_pool import get_arq_pool
            arq_pool = await get_arq_pool()
            await arq_pool.enqueue_job(
                "send_budget_match_notifications_task",
                listing.id,
                _defer_by=180,  # 3 dakika
                _queue_name="critical",
            )
        except Exception as exc:
            logger.warning("[LISTINGS] budget_match enqueue başarısız | listing_id=%s | %s", listing.id, exc)

        # Görsel moderasyon: pHash (kopya tespit) + NSFW kontrolü
        if listing.image_url:
            try:
                from app.utils.arq_pool import get_arq_pool as _get_arq
                _arq = await _get_arq()
                await _arq.enqueue_job("compute_listing_phash_task", listing.id, listing.image_url)
                await _arq.enqueue_job("nsfw_check_task", listing.id)
            except Exception as exc:
                logger.warning("[LISTINGS] Görsel moderasyon enqueue başarısız | listing_id=%s | %s", listing.id, exc)

        # Arama alarmı eşleşmeleri — anlık tetikle
        _asyncio.create_task(_trigger_search_alerts(listing.id, listing.category, listing.price))

        return {"id": listing.id}

    # ── İlan Güncelle ────────────────────────────────────────────────────────
    async def update_listing(self, listing_id: int, payload: dict, current_user: User) -> dict:
        import os
        from datetime import datetime
        import json
        from app.config import settings
        from app.core.exceptions import NotFoundException, BadRequestException, ContentPolicyException, DatabaseException
        from fastapi import HTTPException
        
        result = await self.db.execute(
            select(Listing).where(
                Listing.id == listing_id,
                Listing.status != ListingStatus.DELETED,  # noqa: E712
            )
        )
        listing = result.scalar_one_or_none()
        
        if not listing:
            raise NotFoundException("İlan bulunamadı")
            
        if listing.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Bu ilanı düzenleme yetkiniz yok.")

        # Profanity kontrolü
        from app.core.auto_mod import analyze_listing_text
        _title = (payload.get("title") or listing.title).strip()
        _desc = (payload.get("description") or listing.description or "").strip()
        if analyze_listing_text(_title, _desc):
            raise ContentPolicyException()

        category = (payload.get("category") or listing.category or "diger").strip().lower()
        if category not in VALID_CATEGORIES:
            raise BadRequestException(f"Geçersiz kategori: {category}")

        # Eski medyaları al
        old_image_urls_str = listing.image_urls
        old_images = []
        if old_image_urls_str:
            try:
                old_images = json.loads(old_image_urls_str)
            except Exception:
                old_images = []
        old_video = listing.video_url

        # Yeni medyalar
        new_images = payload.get("image_urls")
        new_video = payload.get("video_url")

        # Güncellemeleri uygula
        listing.title = payload.get("title", listing.title)
        listing.description = payload.get("description", listing.description)
        listing.price = payload.get("price", listing.price)
        listing.category = category
        listing.location = payload.get("location", listing.location)
        listing.updated_at = datetime.utcnow()

        # Medya GC (Resource Management)
        if new_images is not None:
            listing.image_urls = json.dumps(new_images)
            listing.image_url = new_images[0] if new_images else None
            listing.thumbnail_url = payload.get("thumbnail_url", listing.thumbnail_url)
            
            from app.services import storage_service as storage
            for old_img in old_images:
                if old_img not in new_images:
                    filename = old_img.split("/")[-1]
                    base, ext = os.path.splitext(filename)
                    thumb_ext = ".jpg" if ext.lower() in (".jpg", ".webp", ".gif") else ".png"
                    storage.delete_object(filename)
                    storage.delete_object(f"{base}_thumb{thumb_ext}")

        if "video_url" in payload:
            listing.video_url = new_video
            if old_video and old_video != new_video:
                from app.services import storage_service as storage
                filename = old_video.split("/")[-1]
                base, _ = os.path.splitext(filename)
                storage.delete_object(filename)
                storage.delete_object(f"{base}_vthumb.jpg")

        try:
            await self.db.commit()
            await self.db.refresh(listing)
        except Exception as exc:
            await self.db.rollback()
            logger.error("[LISTINGS] İlan güncellenemedi | user_id=%s | %s", current_user.id, exc)
            capture_exception(exc)
            raise DatabaseException("İlan güncellenemedi")

        logger.info("[LISTINGS] İlan güncellendi | user_id=%s listing_id=%s", current_user.id, listing.id)

        # Embedding & Search Vector güncellemesi
        from app.core.task_queue import get_pool
        pool = get_pool()
        if pool:
            import asyncio
            asyncio.create_task(pool.enqueue_job("generate_listing_embedding_task", listing.id))
            
        try:
            from sqlalchemy import text as _text
            await self.db.execute(_text("""
                UPDATE listings SET search_vector =
                    to_tsvector('turkish',
                        coalesce(title, '') || ' ' || coalesce(description, ''))
                WHERE id = :lid
            """), {"lid": listing.id})
            await self.db.commit()
        except Exception:
            pass

        return {"id": listing.id}

    # ── Aktif/Pasif Geçiş ────────────────────────────────────────────────────
    async def toggle_listing(self, listing_id: int, current_user: User) -> dict:
        from fastapi import HTTPException
        from datetime import datetime, timezone, timedelta
        
        result = await self.db.execute(
            select(Listing).where(
                Listing.id == listing_id,
                Listing.user_id == current_user.id,
                Listing.status != ListingStatus.DELETED,  # noqa: E712
            )
        )
        listing = result.scalar_one_or_none()
        if not listing:
            raise NotFoundException("İlan bulunamadı")

        reactivating = listing.status != ListingStatus.ACTIVE  # pasif → aktif geçişi mi?

        is_free = False
        is_free_due_to_window = False

        if reactivating:
            # ── 30 Günlük Ücretsiz Pencere Kontrolü ─────────────────────────
            created_at = listing.created_at
            if created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=timezone.utc)
            within_window = created_at > (datetime.now(timezone.utc) - timedelta(days=30))
            
            if within_window:
                is_free = True
                is_free_due_to_window = True
            else:
                # ── Reaktivasyon ücret kontrolü ─────────────────────────────────
                if current_user.is_premium:
                    used = await _get_reactivation_used(current_user.id, current_user.premium_since)
                    is_free = used < _REACTIVATION_FREE_MONTHLY

                if not is_free:
                    if current_user.tuci_balance < _REACTIVATION_COST_TUCI:
                        raise HTTPException(
                            status_code=402,
                            detail={
                                "code": "insufficient_balance",
                                "balance": current_user.tuci_balance,
                                "cost": _REACTIVATION_COST_TUCI,
                            },
                        )

            listing.status = ListingStatus.ACTIVE
            if not is_free_due_to_window:
                listing.created_at = datetime.now(timezone.utc)
            listing.deactivated_at = None

        else:
            # ── Pasife alma: kampanya + izlenim temizliği (rozet korunur) ──
            listing.status = ListingStatus.PASSIVE

        try:
            if reactivating and not is_free:
                # TUCi düş + işlem kaydet
                await self.db.execute(
                    sql_text("UPDATE users SET tuci_balance = GREATEST(0, tuci_balance - :cost) WHERE id = :uid"),
                    {"cost": _REACTIVATION_COST_TUCI, "uid": current_user.id},
                )
                self.db.add(TuciTransaction(
                    user_id=current_user.id,
                    amount=-_REACTIVATION_COST_TUCI,
                    transaction_type="spend_reactivation",
                    reference_id=listing_id,
                    reference_type="listing",
                ))

            if not reactivating:
                # AdCampaign'leri komple sil
                await self.db.execute(
                    delete(AdCampaign).where(AdCampaign.listing_id == listing_id)
                )

            # İzlenimler temizle (hem aktifleştirme hem pasife alma sonrası fresh start)
            await self.db.execute(
                delete(ListingImpression).where(ListingImpression.listing_id == listing_id)
            )

            await self.db.commit()
        except HTTPException:
            raise
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LISTINGS] Toggle DB hatası | listing_id=%s | %s",
                listing_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("İlan güncellenemedi")

        # Redis ALS vektörünü temizle
        try:
            from app.utils.listing_cleanup import cleanup_listing_redis
            import asyncio as _asyncio_t
            _asyncio_t.create_task(cleanup_listing_redis(listing_id))
        except Exception:
            pass

        # AdCampaign Redis cache'ini güncelle (pasife almada kampanyalar silindi)
        if not reactivating:
            try:
                from app.services.ad_service import load_active_campaigns_to_redis
                import asyncio as _asyncio_t2
                _asyncio_t2.create_task(load_active_campaigns_to_redis())
            except Exception:
                pass

        # Ücretsiz reaktivasyon hakkı kullanıldıysa sayacı artır
        if reactivating and is_free and not is_free_due_to_window:
            await _increment_reactivation(current_user.id, current_user.premium_since)

        return {"status": listing.status.value}

    # ── İlan Sil (soft delete) ───────────────────────────────────────────────
    async def delete_listing(self, listing_id: int, current_user: User) -> dict:
        result = await self.db.execute(
            select(Listing).where(
                Listing.id == listing_id,
                Listing.user_id == current_user.id,
            )
        )
        listing = result.scalar_one_or_none()
        if not listing:
            raise NotFoundException("İlan bulunamadı")

        # Commit öncesi medya URL'lerini kaydet (session commit sonrası erişilebilir olmayabilir)
        _image_url    = listing.image_url
        _image_urls   = listing.image_urls
        _thumbnail    = listing.thumbnail_url
        _video_url    = listing.video_url
        _owner_id     = listing.user_id

        listing.status = ListingStatus.DELETED
        listing.status = ListingStatus.PASSIVE
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LISTINGS] Silme DB hatası | listing_id=%s | %s",
                listing_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("İlan silinemedi")

        # Commit sonrası: tüm kaynakları temizle (fire-and-forget)
        import asyncio as _asyncio3
        from app.database_clickhouse import track_user_event
        from app.utils.listing_cleanup import cleanup_listing_resources
        _asyncio3.create_task(track_user_event(
            event_type="listing_deleted",
            item_id=listing_id,
            item_type="listing",
            user_id=_owner_id,
        ))
        _asyncio3.create_task(cleanup_listing_resources(
            listing_id, _image_url, _image_urls, _thumbnail, _video_url,
        ))

        return {"ok": True}

    # ── Teklif Ver ───────────────────────────────────────────────────────────
    async def create_offer(self, listing_id: int, current_user: User, amount: float) -> dict:
        # İlanın var olduğunu doğrula
        result = await self.db.execute(
            select(Listing).where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED)  # noqa: E712
        )
        listing = result.scalar_one_or_none()
        if not listing:
            raise NotFoundException("İlan bulunamadı")

        # Kendi ilanına teklif verme kuralı
        if listing.user_id == current_user.id:
            raise BadRequestException("Kendi ilanınıza teklif veremezsiniz")

        offer = ListingOffer(
            listing_id=listing_id,
            user_id=current_user.id,
            amount=amount,
        )
        self.db.add(offer)
        try:
            await self.db.commit()
            await self.db.refresh(offer)
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[OFFERS] Teklif DB'ye kaydedilemedi | listing_id=%s user_id=%s | %s",
                listing_id, current_user.id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Teklif oluşturulamadı")

        logger.info(
            "[OFFERS] Teklif verildi | listing_id=%s user_id=%s amount=%s",
            listing_id, current_user.id, amount,
        )
        return {"id": offer.id, "amount": offer.amount}

    # ── Canlı Yayın Swipe Feed — Video VEYA Fotoğraflı İlanlar ─────────────
    async def get_swipe_feed(self, limit: int = 10) -> list:
        """Videolu ya da fotoğraflı tüm aktif ilanları rastgele döndürür (swipe feed için)."""
        result = await self.db.execute(
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.status == ListingStatus.ACTIVE,    # noqa: E712
                Listing.status != ListingStatus.DELETED,  # noqa: E712
                (Listing.video_url.isnot(None)) | (Listing.image_url.isnot(None)),
            )
            .order_by(func.random())
            .limit(limit)
        )
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "location": listing.location,
                "video_url": listing.video_url,
                "thumbnail_url": listing.thumbnail_url,
                "image_url": listing.image_url,
                "user": {"id": user.id, "username": user.username},
            }
            for listing, user in result.all()
        ]

    # ── Canlı Yayın Feed — Sadece Videolu İlanlar ───────────────────────────
    async def get_video_feed(self, limit: int = 8) -> list:
        """Videosu olan aktif ilanları rastgele döndürür (canlı yayın swipe feed'i için)."""
        result = await self.db.execute(
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(
                Listing.status == ListingStatus.ACTIVE,     # noqa: E712
                Listing.status != ListingStatus.DELETED,   # noqa: E712
                Listing.video_url.isnot(None),
            )
            .order_by(func.random())
            .limit(limit)
        )
        return [
            {
                "id": listing.id,
                "title": listing.title,
                "price": listing.price,
                "category": listing.category,
                "location": listing.location,
                "video_url": listing.video_url,
                "thumbnail_url": listing.thumbnail_url,
                "image_url": listing.image_url,
                "user": {"id": user.id, "username": user.username},
            }
            for listing, user in result.all()
        ]

    # ── Teklifleri Listele ───────────────────────────────────────────────────
    async def get_listing_offers(self, listing_id: int) -> list:
        # İlanın varlığını kontrol et
        listing_exists = await self.db.execute(
            select(Listing.id).where(Listing.id == listing_id, Listing.status != ListingStatus.DELETED)  # noqa: E712
        )
        if not listing_exists.scalar_one_or_none():
            raise NotFoundException("İlan bulunamadı")

        result = await self.db.execute(
            select(ListingOffer, User)
            .join(User, User.id == ListingOffer.user_id)
            .where(ListingOffer.listing_id == listing_id)
            .order_by(ListingOffer.amount.desc())
        )
        return [
            {
                "id": o.id,
                "listing_id": o.listing_id,
                "amount": o.amount,
                "created_at": o.created_at.isoformat() if o.created_at else None,
                "user_id": u.id,
                "username": u.username,
                "profile_image_url": u.profile_image_url,
            }
            for o, u in result.all()
        ]
