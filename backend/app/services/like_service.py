"""
Like (Beğeni) servisi — Listing, Story ve LiveStream için.

Kural Özeti:
  Listing  → toggle  (beğenilmemişse ekle, beğenilmişse kaldır)
  Story    → toggle  (aynı kural)
  Stream   → add-only (art arda kalp — uniqueness kısıtı yoktur)

Stream Beğenisi WebSocket Broadcast:
  Beğeni eklendiğinde ws_manager üzerinden o anki tüm yayın izleyicilerine
  `{"type": "stream_like", "user_id": ..., "username": ...}` sinyali gönderilir.
  chat_broadcast kanalı kullanılır (mevcut Redis pub/sub altyapısı).

Hata Yönetimi:
  DB hataları  → logger.error + capture_exception → DatabaseException (500)
  Bulunamayan  → NotFoundException (404)
"""
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.like import ListingLike, StoryLike, StreamLike
from app.models.listing import Listing
from app.models.story import Story
from app.models.stream import LiveStream
from app.core.exceptions import NotFoundException, DatabaseException
from app.core.logger import get_logger, capture_exception

logger = get_logger(__name__)


class LikeService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # ── İlan Beğeni Toggle ────────────────────────────────────────────────────

    async def toggle_listing_like(self, listing_id: int, user_id: int) -> dict:
        """
        İlanı beğen / beğeniyi kaldır (toggle).
        İlan soft-deleted veya yoksa 404 döner.
        Güncel `likes_count` ve `is_liked` durumu döner.
        """
        # İlan kontrolü
        listing_exists = await self.db.scalar(
            select(Listing.id).where(
                Listing.id == listing_id, Listing.is_deleted == False  # noqa: E712
            )
        )
        if not listing_exists:
            raise NotFoundException("İlan bulunamadı")

        # Mevcut beğeni var mı?
        existing = await self.db.scalar(
            select(ListingLike).where(
                ListingLike.listing_id == listing_id,
                ListingLike.user_id == user_id,
            )
        )

        try:
            if existing:
                await self.db.delete(existing)
                is_liked = False
                action = "kaldırıldı"
            else:
                self.db.add(ListingLike(listing_id=listing_id, user_id=user_id))
                is_liked = True
                action = "eklendi"
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LIKES] İlan beğeni DB hatası | listing_id=%s user_id=%s | %s",
                listing_id, user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Beğeni işlemi gerçekleştirilemedi")

        count = await self.db.scalar(
            select(func.count(ListingLike.id)).where(ListingLike.listing_id == listing_id)
        ) or 0

        logger.info(
            "[LIKES] İlan beğeni %s | listing_id=%s user_id=%s likes_count=%s",
            action, listing_id, user_id, count,
        )
        return {"likes_count": count, "is_liked": is_liked}

    # ── Hikaye Beğeni Toggle ──────────────────────────────────────────────────

    async def toggle_story_like(self, story_id: int, user_id: int) -> dict:
        """
        Hikayeyi beğen / beğeniyi kaldır (toggle).
        Güncel `likes_count` ve `is_liked` durumu döner.
        """
        # Hikaye kontrolü
        story_exists = await self.db.scalar(
            select(Story.id).where(
                Story.id == story_id, Story.expires_at > func.now()
            )
        )
        if not story_exists:
            raise NotFoundException("Hikaye bulunamadı veya süresi dolmuş")

        existing = await self.db.scalar(
            select(StoryLike).where(
                StoryLike.story_id == story_id,
                StoryLike.user_id == user_id,
            )
        )

        try:
            if existing:
                await self.db.delete(existing)
                is_liked = False
                action = "kaldırıldı"
            else:
                self.db.add(StoryLike(story_id=story_id, user_id=user_id))
                is_liked = True
                action = "eklendi"
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LIKES] Hikaye beğeni DB hatası | story_id=%s user_id=%s | %s",
                story_id, user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Beğeni işlemi gerçekleştirilemedi")

        count = await self.db.scalar(
            select(func.count(StoryLike.id)).where(StoryLike.story_id == story_id)
        ) or 0

        logger.info(
            "[LIKES] Hikaye beğeni %s | story_id=%s user_id=%s likes_count=%s",
            action, story_id, user_id, count,
        )
        return {"likes_count": count, "is_liked": is_liked}

    # ── Canlı Yayın Kalp (Add-Only) ───────────────────────────────────────────

    async def add_stream_like(
        self,
        stream_id: int,
        user_id: int,
        username: str,
    ) -> dict:
        """
        Canlı yayına kalp gönder (art arda gönderilebilir, toggle yok).

        Beğeni kaydedildikten sonra o yayındaki tüm izleyicilere
        `{"type": "stream_like", ...}` WebSocket sinyali yayımlanır.
        Yayın aktif değilse 404 döner.
        """
        stream_exists = await self.db.scalar(
            select(LiveStream.id).where(
                LiveStream.id == stream_id, LiveStream.is_live == True  # noqa: E712
            )
        )
        if not stream_exists:
            raise NotFoundException("Aktif yayın bulunamadı")

        try:
            self.db.add(StreamLike(stream_id=stream_id, user_id=user_id))
            await self.db.commit()
        except Exception as exc:
            await self.db.rollback()
            logger.error(
                "[LIKES] Stream beğeni DB hatası | stream_id=%s user_id=%s | %s",
                stream_id, user_id, exc, exc_info=True,
            )
            capture_exception(exc)
            raise DatabaseException("Beğeni gönderilemedi")

        # WebSocket broadcast — non-critical (hata yayını engellemesin)
        try:
            from app.services.chat_service import publish_chat
            await publish_chat(stream_id, {
                "type": "stream_like",
                "user_id": user_id,
                "username": username,
            })
        except Exception as exc:
            logger.warning(
                "[LIKES] Stream like WS broadcast başarısız | stream_id=%s | %s",
                stream_id, exc,
            )

        logger.info(
            "[LIKES] Yayın kalbi gönderildi | stream_id=%s user_id=%s",
            stream_id, user_id,
        )
        return {"ok": True}

    # ── Yardımcı: Batch Likes Count ───────────────────────────────────────────

    @staticmethod
    async def batch_listing_likes(
        db: AsyncSession,
        listing_ids: list[int],
        current_user_id: Optional[int] = None,
    ) -> tuple[dict[int, int], set[int]]:
        """
        Verilen ilan ID listesi için tek sorguda tüm beğeni sayılarını ve
        giriş yapan kullanıcının beğenilerini döner.

        Returns:
            counts   : {listing_id: count}
            liked_set: {listing_id} — kullanıcının beğendiği ilan ID'leri
        """
        if not listing_ids:
            return {}, set()

        count_rows = await db.execute(
            select(ListingLike.listing_id, func.count(ListingLike.id).label("cnt"))
            .where(ListingLike.listing_id.in_(listing_ids))
            .group_by(ListingLike.listing_id)
        )
        counts = {row.listing_id: row.cnt for row in count_rows}

        liked_set: set[int] = set()
        if current_user_id:
            liked_rows = await db.execute(
                select(ListingLike.listing_id).where(
                    ListingLike.listing_id.in_(listing_ids),
                    ListingLike.user_id == current_user_id,
                )
            )
            liked_set = {row.listing_id for row in liked_rows}

        return counts, liked_set

    @staticmethod
    async def batch_story_likes(
        db: AsyncSession,
        story_ids: list[int],
        current_user_id: Optional[int] = None,
    ) -> tuple[dict[int, int], set[int]]:
        """
        Verilen hikaye ID listesi için tek sorguda beğeni sayılarını ve
        giriş yapan kullanıcının beğenilerini döner.
        """
        if not story_ids:
            return {}, set()

        count_rows = await db.execute(
            select(StoryLike.story_id, func.count(StoryLike.id).label("cnt"))
            .where(StoryLike.story_id.in_(story_ids))
            .group_by(StoryLike.story_id)
        )
        counts = {row.story_id: row.cnt for row in count_rows}

        liked_set: set[int] = set()
        if current_user_id:
            liked_rows = await db.execute(
                select(StoryLike.story_id).where(
                    StoryLike.story_id.in_(story_ids),
                    StoryLike.user_id == current_user_id,
                )
            )
            liked_set = {row.story_id for row in liked_rows}

        return counts, liked_set

    @staticmethod
    async def batch_stream_likes(
        db: AsyncSession,
        stream_ids: list[int],
    ) -> dict[int, int]:
        """Verilen yayın ID listesi için toplam beğeni sayılarını döner."""
        if not stream_ids:
            return {}

        rows = await db.execute(
            select(StreamLike.stream_id, func.count(StreamLike.id).label("cnt"))
            .where(StreamLike.stream_id.in_(stream_ids))
            .group_by(StreamLike.stream_id)
        )
        return {row.stream_id: row.cnt for row in rows}
