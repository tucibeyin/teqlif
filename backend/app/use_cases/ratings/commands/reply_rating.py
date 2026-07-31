from datetime import datetime, timezone
from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import BadRequestException, ForbiddenException, NotFoundException
from app.core.logger import get_logger
from app.models.rating import Rating

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

        rating = await self.uow.session.scalar(
            select(Rating).where(Rating.id == rating_id)
        )
        if not rating:
            raise NotFoundException(code="RATING_NOT_FOUND")

        if rating.rated_id != replier_id:
            raise ForbiddenException(code="REPLY_FORBIDDEN")

        rating.reply = reply_text
        rating.replied_at = datetime.now(timezone.utc)
        await self.uow.session.commit()

        logger.info(
            "[ReplyRatingCommand] replied | rating_id=%s replier=%s",
            rating_id, replier_id,
        )
        return {"ok": True}
