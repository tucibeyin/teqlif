import asyncio
from datetime import datetime, timezone

from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import BadRequestException, ForbiddenException, NotFoundException
from app.core.logger import get_logger
from app.models.rating import Rating
from app.models.user import User
from app.services.notification_service import push_notification
from app.core.auto_mod import censor_text

logger = get_logger(__name__)


class ReplyRatingCommand:
    """Değerlendirilen kişi aldığı bir değerlendirmeye yanıt yazar."""

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, rating_id: int, replier_id: int, reply_text: str) -> dict:
        reply_text = reply_text.strip()
        if not reply_text:
            raise BadRequestException(code="REPLY_EMPTY")
        if len(reply_text) > 500:
            raise BadRequestException(code="REPLY_TOO_LONG")

        reply_text = censor_text(reply_text)

        rating = await self.uow.session.scalar(
            select(Rating).where(Rating.id == rating_id)
        )
        if not rating:
            raise NotFoundException(code="RATING_NOT_FOUND")

        if rating.rated_id != replier_id:
            raise ForbiddenException(code="REPLY_FORBIDDEN")

        rating.reply = reply_text
        rating.replied_at = datetime.now(timezone.utc)
        rater_id = rating.rater_id
        await self.uow.session.commit()

        logger.info(
            "[ReplyRatingCommand] replied | rating_id=%s replier=%s",
            rating_id, replier_id,
        )

        replier = await self.uow.session.scalar(
            select(User).where(User.id == replier_id)
        )
        if replier:
            asyncio.create_task(push_notification(
                user_id=rater_id,
                notif={
                    "type": "rating_reply",
                    "i18n": {
                        "title_key": "notifRatingReplyTitle",
                        "title_params": {"username": replier.username},
                    },
                    "related_id": replier.id,
                    "sender_username": replier.username,
                    "sender_image_url": replier.profile_image_url,
                },
                pref_key="ratings",
            ))

        return {"ok": True}
