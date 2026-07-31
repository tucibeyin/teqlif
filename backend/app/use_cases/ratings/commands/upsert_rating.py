from sqlalchemy import select
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import BadRequestException, ForbiddenException, NotFoundException
from app.core.logger import get_logger
from app.models.enums import UserStatus
from app.models.follow import Follow
from app.models.rating import Rating
from app.models.rating_history import RatingHistory
from app.models.user import User

logger = get_logger(__name__)


class UpsertRatingCommand:
    """Bir kullanıcıya puan ver veya mevcut puanı güncelle.
    Güncelleme durumunda eski değer rating_history tablosuna kaydedilir.
    """

    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(
        self,
        rater_id: int,
        rated_id: int,
        score: int,
        comment: str | None,
    ) -> dict:
        if rater_id == rated_id:
            raise ForbiddenException(code="SELF_RATING_FORBIDDEN")

        if not isinstance(score, int) or score < 1 or score > 5:
            raise BadRequestException(code="INVALID_RATING_RANGE")

        if comment and len(comment) > 500:
            raise BadRequestException(code="COMMENT_TOO_LONG")

        target = await self.uow.session.scalar(
            select(User).where(User.id == rated_id, User.status == UserStatus.ACTIVE)
        )
        if not target:
            raise NotFoundException(code="USER_NOT_FOUND")

        is_following = await self.uow.session.scalar(
            select(Follow).where(
                Follow.follower_id == rater_id,
                Follow.followed_id == rated_id,
            )
        )
        if not is_following:
            raise ForbiddenException(code="RATING_REQUIRES_FOLLOW")

        existing = await self.uow.session.scalar(
            select(Rating).where(
                Rating.rater_id == rater_id, Rating.rated_id == rated_id
            )
        )

        if existing:
            # Güncelleme: eski değeri history'ye kaydet
            self.uow.session.add(
                RatingHistory(
                    rating_id=existing.id,
                    score=existing.score,
                    comment=existing.comment,
                )
            )
            existing.score = score
            existing.comment = comment
            logger.info(
                "[UpsertRatingCommand] Updated | rater=%s rated=%s score=%s",
                rater_id, rated_id, score,
            )
        else:
            self.uow.session.add(
                Rating(rater_id=rater_id, rated_id=rated_id, score=score, comment=comment)
            )
            logger.info(
                "[UpsertRatingCommand] Created | rater=%s rated=%s score=%s",
                rater_id, rated_id, score,
            )

        await self.uow.session.commit()
        return {"ok": True}
