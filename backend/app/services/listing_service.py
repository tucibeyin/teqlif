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
from sqlalchemy import select

from app.models.listing import Listing
from app.models.user import User
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
def _row_dict(listing: Listing, user: User) -> dict:
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
        "created_at": listing.created_at.isoformat() if listing.created_at else None,
        "is_active": listing.is_active,
        "user": {"id": user.id, "username": user.username, "full_name": user.full_name},
    }


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

    # ── İlan Listele ─────────────────────────────────────────────────────────
    async def get_listings(
        self,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        location: Optional[str] = None,
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
        q = q.order_by(Listing.created_at.desc())
        result = await self.db.execute(q)
        return [_row_dict(l, u) for l, u in result.all()]

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
        return [_row_dict(l, u) for l, u in result.all()]

    # ── İlan Detayı ──────────────────────────────────────────────────────────
    async def get_listing(self, listing_id: int) -> dict:
        result = await self.db.execute(
            select(Listing, User)
            .join(User, User.id == Listing.user_id)
            .where(Listing.id == listing_id, Listing.is_deleted == False)  # noqa: E712
        )
        row = result.first()
        if not row:
            raise NotFoundException("İlan bulunamadı")
        return _row_dict(row[0], row[1])

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

        # Takipçilere new_listing bildirimi (non-blocking, fire-and-forget)
        import asyncio as _asyncio
        from app.models.follow import Follow
        from app.routers.notifications import push_notification

        async def _notify_followers():
            try:
                followers = await self.db.scalars(
                    select(Follow.follower_id).where(Follow.followed_id == uid)
                )
                for follower_id in followers:
                    _asyncio.create_task(push_notification(
                        user_id=follower_id,
                        notif={
                            "type": "new_listing",
                            "title": f"@{current_user.username} yeni ilan ekledi",
                            "body": listing.title or None,
                            "related_id": listing.id,
                        },
                        pref_key="new_listing",
                    ))
            except Exception as exc:
                logger.error("[LISTINGS] Takipçi bildirimi gönderilemedi | user_id=%s | %s", uid, exc)

        _asyncio.create_task(_notify_followers())
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

        return {"ok": True}
