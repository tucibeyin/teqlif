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
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.listing import Listing
from app.models.listing_offer import ListingOffer
from app.models.user import User
from app.models.ad_campaign import AdCampaign
from app.models.listing_impression import ListingImpression
from app.services.like_service import LikeService
from app.schemas.stream import VALID_CATEGORIES
from app.core.exceptions import (
    NotFoundException,
    BadRequestException,
    TooManyRequestsException,
    ConflictException,
    DatabaseException,
)
from app.core.action_guard import check_user_action_rate, acquire_action_lock, release_action_lock
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


# ── Yardımcı: model → dict dönüşümü ─────────────────────────────────────────
async def _fetch_seller_meta(user_ids: list[int]) -> tuple[dict[int, str | None], set[str]]:
    """
    Batch olarak Redis'ten seller_badge ve trending kategorileri çeker.
    Döner: (badge_map {user_id: badge}, trending_categories set)
    """
    try:
        from app.utils.redis_client import get_redis
        redis = await get_redis()
        badge_keys = [f"seller:badge:{uid}" for uid in user_ids]
        results = await redis.mget(*badge_keys) if badge_keys else []
        badge_map = {uid: (val or None) for uid, val in zip(user_ids, results)}
        trending_cats = set(await redis.smembers("trending:categories") or [])
        return badge_map, trending_cats
    except Exception:
        return {}, set()


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
        "is_active": listing.is_active,
        "user": {"id": user.id, "username": user.username, "full_name": user.full_name},
        "likes_count": likes_count,
        "is_liked": is_liked,
        "is_sponsored": is_sponsored,
        "campaign_id": campaign_id,
        "seller_is_premium": user.is_premium,
        "seller_badge": seller_badge,
        "is_trending": is_trending,
        "impression_count": impression_count,
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
            q = select(SearchAlert).where(SearchAlert.is_active == True)  # noqa: E712
            if category:
                q = q.where((SearchAlert.category == category) | (SearchAlert.category.is_(None)))
            if price is not None:
                q = q.where((SearchAlert.max_price >= price) | (SearchAlert.max_price.is_(None)))
            result = await db.execute(q.limit(200))
            alerts = result.scalars().all()

        import asyncio as _aio
        async def _send(a: SearchAlert) -> None:
            try:
                await push_notification(
                    user_id=a.user_id,
                    notif={
                        "type": "search_alert",
                        "title": "Arama alarmı: yeni ilan",
                        "body": f"{category or 'İlan'} kategorisinde yeni ürün eklendi",
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
    async def _add_ad_impressions(db: AsyncSession, impression_map: dict[int, int], my_listing_ids: list[int]) -> None:
        """Kendi ilanlarımızın gösterim sayısına ClickHouse'daki reklam gösterimlerini (varsa) ekler."""
        if not my_listing_ids:
            return
        
        try:
            camp_result = await db.execute(
                select(AdCampaign.listing_id, AdCampaign.id)
                .where(AdCampaign.listing_id.in_(my_listing_ids))
            )
            all_camp_map = {}
            for lid, cid in camp_result.all():
                all_camp_map.setdefault(lid, []).append(cid)
                
            if not all_camp_map:
                return

            all_cids = [cid for cids in all_camp_map.values() for cid in cids]

            from app.database_clickhouse import get_clickhouse_client
            ch = await get_clickhouse_client()
            camp_ids_str = ",".join(map(str, all_cids))
            ch_query = f"""
                SELECT item_id, count()
                FROM user_events
                WHERE item_id IN ({camp_ids_str})
                  AND item_type = 'ad_campaign'
                  AND event_type = 'ad_impression'
                GROUP BY item_id
            """
            ch_res = await ch.query(ch_query)
            if ch_res and ch_res.result_rows:
                ad_imp_map = {int(row[0]): int(row[1]) for row in ch_res.result_rows}
                for lid, cids in all_camp_map.items():
                    total_ad_imp = sum(ad_imp_map.get(cid, 0) for cid in cids)
                    if total_ad_imp > 0:
                        impression_map[lid] = impression_map.get(lid, 0) + total_ad_imp
        except Exception as e:
            logger.warning("[ListingService] ClickHouse ad_impression fetch failed: %s", e)

    # ── İlan Listele ─────────────────────────────────────────────────────────
    async def get_listings(
        self,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        location: Optional[str] = None,
        current_user_id: Optional[int] = None,
    ) -> list:
        q = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.is_active == True, Listing.is_deleted == False)  # noqa: E712
        )
        if user_id:
            q = q.where(Listing.user_id == user_id)
        if category:
            q = q.where(Listing.category == category)
        if location:
            q = q.where(Listing.location == location)
        q = q.order_by(User.is_premium.desc(), Listing.created_at.desc())
        result = await self.db.execute(q)
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
        badge_map, trending_cats = await _fetch_seller_meta(user_ids)

        # Sadece mevcut kullanıcıya ait olan ilanların görüntülenmelerini çek
        impression_map: dict[int, int] = {}
        if current_user_id and listing_ids:
            my_listing_ids = [l.id for l, u in rows if u.id == current_user_id]
            if my_listing_ids:
                imp_result = await self.db.execute(
                    select(ListingImpression.listing_id, func.count())
                    .select_from(ListingImpression)
                    .where(ListingImpression.listing_id.in_(my_listing_ids))
                    .group_by(ListingImpression.listing_id)
                )
                for lid, imp_count in imp_result.all():
                    impression_map[lid] = imp_count
                await self._add_ad_impressions(self.db, impression_map, my_listing_ids)

        return [
            _row_dict(
                listing, user,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=listing.id in campaign_map,
                campaign_id=campaign_map.get(listing.id),
                seller_badge=badge_map.get(user.id),
                is_trending=listing.category in trending_cats,
                impression_count=impression_map.get(listing.id, 0) if user.id == current_user_id else None,
            )
            for listing, user in rows
        ]

    # ── Kendi İlanlarım ──────────────────────────────────────────────────────
    async def get_my_listings(self, current_user: User, active: Optional[bool] = None) -> list:
        q = (
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.user_id == current_user.id, Listing.is_deleted == False)  # noqa: E712
        )
        if active is not None:
            q = q.where(Listing.is_active == active)  # noqa: E712
        q = q.order_by(Listing.created_at.desc())
        result = await self.db.execute(q)
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
        badge_map, trending_cats = await _fetch_seller_meta([current_user.id])

        # Kullanıcının kendi ilanları olduğu için her birinin impression_count'unu al
        impression_map: dict[int, int] = {}
        if listing_ids:
            imp_result = await self.db.execute(
                select(ListingImpression.listing_id, func.count())
                .select_from(ListingImpression)
                .where(ListingImpression.listing_id.in_(listing_ids))
                .group_by(ListingImpression.listing_id)
            )
            for lid, imp_count in imp_result.all():
                impression_map[lid] = imp_count
            await self._add_ad_impressions(self.db, impression_map, listing_ids)

        return [
            _row_dict(
                listing, user,
                counts.get(listing.id, 0), listing.id in liked_set,
                is_sponsored=listing.id in campaign_map,
                campaign_id=campaign_map.get(listing.id),
                seller_badge=badge_map.get(user.id),
                is_trending=listing.category in trending_cats,
                impression_count=impression_map.get(listing.id, 0),
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
            .where(Listing.id == listing_id, Listing.is_deleted == False)  # noqa: E712
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
        badge_map, trending_cats = await _fetch_seller_meta([user.id])
        # İlan sahibi görüntüleme sayısını talep ediyorsa (kendi ilanı)
        impression_count: Optional[int] = None
        if current_user_id == listing.user_id:
            imp_result = await self.db.execute(
                select(func.count()).select_from(ListingImpression).where(
                    ListingImpression.listing_id == listing.id
                )
            )
            impression_count = imp_result.scalar() or 0
            
            all_camps = await self.db.execute(
                select(AdCampaign.id).where(AdCampaign.listing_id == listing.id)
            )
            all_cids = [r for r, in all_camps.all()]
            
            if all_cids:
                try:
                    from app.database_clickhouse import get_clickhouse_client
                    ch = await get_clickhouse_client()
                    camp_ids_str = ",".join(map(str, all_cids))
                    ch_query = f"""
                        SELECT count()
                        FROM user_events
                        WHERE item_id IN ({camp_ids_str})
                          AND item_type = 'ad_campaign'
                          AND event_type = 'ad_impression'
                    """
                    ch_res = await ch.query(ch_query)
                    if ch_res and ch_res.result_rows:
                        impression_count += int(ch_res.result_rows[0][0])
                except Exception as e:
                    logger.warning("[ListingService] ClickHouse ad_impression fetch failed in get_listing: %s", e)
        
        logger.info("[DEBUG-LOG] İlan Detayları -> listing_id: %s, toplam_gosterim: %s", listing.id, impression_count)
        
        return _row_dict(
            listing, user,
            counts.get(listing.id, 0), listing.id in liked_set,
            is_sponsored=campaign_id is not None,
            campaign_id=campaign_id,
            seller_badge=badge_map.get(user.id),
            is_trending=listing.category in trending_cats,
            impression_count=impression_count,
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
            "title": f"@{current_user.username} yeni ilan ekledi",
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
            )
        except Exception as exc:
            logger.warning("[LISTINGS] budget_match enqueue başarısız | listing_id=%s | %s", listing.id, exc)

        # Arama alarmı eşleşmeleri — anlık tetikle
        _asyncio.create_task(_trigger_search_alerts(listing.id, listing.category, listing.price))

        return {"id": listing.id}

    # ── Aktif/Pasif Geçiş ────────────────────────────────────────────────────
    async def toggle_listing(self, listing_id: int, current_user: User) -> dict:
        result = await self.db.execute(
            select(Listing).where(
                Listing.id == listing_id,
                Listing.user_id == current_user.id,
                Listing.is_deleted == False,  # noqa: E712
            )
        )
        listing = result.scalar_one_or_none()
        if not listing:
            raise NotFoundException("İlan bulunamadı")

        listing.is_active = not listing.is_active
        try:
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LISTINGS] Toggle DB hatası | listing_id=%s | %s",
                listing_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("İlan güncellenemedi")

        return {"is_active": listing.is_active}

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

        listing.is_deleted = True
        listing.is_active = False
        _owner_id = listing.user_id
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

        import asyncio as _asyncio3
        from app.database_clickhouse import track_user_event
        _asyncio3.create_task(track_user_event(
            event_type="listing_deleted",
            item_id=listing_id,
            item_type="listing",
            user_id=_owner_id,
        ))

        return {"ok": True}

    # ── Teklif Ver ───────────────────────────────────────────────────────────
    async def create_offer(self, listing_id: int, current_user: User, amount: float) -> dict:
        # İlanın var olduğunu doğrula
        result = await self.db.execute(
            select(Listing).where(Listing.id == listing_id, Listing.is_deleted == False)  # noqa: E712
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
                Listing.is_active == True,    # noqa: E712
                Listing.is_deleted == False,  # noqa: E712
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
                Listing.is_active == True,     # noqa: E712
                Listing.is_deleted == False,   # noqa: E712
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
            select(Listing.id).where(Listing.id == listing_id, Listing.is_deleted == False)  # noqa: E712
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
