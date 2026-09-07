import asyncio
from datetime import datetime, timezone
from sqlalchemy import select, delete as sa_delete, or_, and_
from app.core.uow import AbstractUnitOfWork
from app.core.logger import get_logger
from app.models.message_thread import MessageThread
from app.models.message import DirectMessage
from app.services.relationship_service import RelationshipStateService

logger = get_logger(__name__)


async def _purge_media(urls: list[str]) -> None:
    from app.services import storage_service as storage

    def _sync():
        for url in urls:
            try:
                if storage.is_dm_url(url):
                    storage.delete_object_dm(storage.dm_url_to_key(url))
                else:
                    storage.delete_object(storage.url_to_key(url))
            except Exception as exc:
                logger.error("[DeleteConversation] MinIO silme hatası: url=%s | %s", url, exc)

    await asyncio.to_thread(_sync)


class DeleteConversationCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_user_id: int) -> None:
        user_a_id = min(uid, other_user_id)
        user_b_id = max(uid, other_user_id)
        media_urls: list[str] = []
        rel_state = None

        async with self.uow:
            result = await self.uow.session.execute(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a_id,
                    MessageThread.user_b_id == user_b_id,
                )
            )
            thread = result.scalar_one_or_none()
            if not thread:
                return

            now = datetime.now(timezone.utc)
            if uid == thread.user_a_id:
                thread.deleted_at_a = now
            else:
                thread.deleted_at_b = now

            # Tek taraf sildi: soft-delete yeterli
            if thread.deleted_at_a is None or thread.deleted_at_b is None:
                return

            # ── Her iki taraf da sildi: tüm veriyi hard-delete et ──
            logger.info(
                "[DeleteConversation] Karşılıklı silme — hard-delete başlatıldı | user_a=%s user_b=%s",
                user_a_id, user_b_id,
            )

            # Medya URL'lerini topla
            media_rows = await self.uow.session.execute(
                select(DirectMessage.media_url, DirectMessage.thumbnail_url).where(
                    or_(
                        and_(DirectMessage.sender_id == user_a_id, DirectMessage.receiver_id == user_b_id),
                        and_(DirectMessage.sender_id == user_b_id, DirectMessage.receiver_id == user_a_id),
                    )
                )
            )
            media_urls = [
                url
                for row in media_rows
                for url in (row.media_url, row.thumbnail_url)
                if url
            ]

            # Tüm mesajları hard-delete et
            await self.uow.session.execute(
                sa_delete(DirectMessage).where(
                    or_(
                        and_(DirectMessage.sender_id == user_a_id, DirectMessage.receiver_id == user_b_id),
                        and_(DirectMessage.sender_id == user_b_id, DirectMessage.receiver_id == user_a_id),
                    )
                )
            )

            # Thread'i hard-delete et; autoflush DELETE SQL'i recompute sorgusundan önce çalıştırır
            await self.uow.session.delete(thread)

            # Thread artık silindiği için recompute can_call=False (follow yoksa) döner
            rel_state = await RelationshipStateService.recompute_and_cache(
                user_a_id, user_b_id, self.uow.session
            )

        # ── Commit sonrası: MinIO temizliği + WS broadcast ──
        if media_urls:
            asyncio.create_task(_purge_media(media_urls))
            logger.info("[DeleteConversation] %d medya dosyası silinmek üzere kuyruğa alındı", len(media_urls))

        if rel_state is not None:
            RelationshipStateService.broadcast(rel_state)
