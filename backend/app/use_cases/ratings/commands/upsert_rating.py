import asyncio

from sqlalchemy import select, text as sa_text
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import BadRequestException, ForbiddenException, NotFoundException
from app.core.logger import get_logger
from app.models.enums import UserStatus
from app.models.follow import Follow
from app.models.rating_history import RatingHistory
from app.models.user import User
from app.services.notification_service import push_notification
from app.core.auto_mod import censor_text

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

        if comment:
            comment = censor_text(comment)

        notif_payload: dict | None = None

        async with self.uow:
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

            # Tek SQL ifadesiyle atomik upsert — çift tıklama / yarış güvenli.
            # old_val CTE, upsert CTE ile aynı snapshot'ta eski değeri yakalar.
            row = (await self.uow.session.execute(
                sa_text("""
                    WITH old_val AS (
                        SELECT id, score, comment
                        FROM ratings
                        WHERE rater_id = :rater_id AND rated_id = :rated_id
                    ),
                    upsert AS (
                        INSERT INTO ratings (rater_id, rated_id, score, comment)
                        VALUES (:rater_id, :rated_id, :score, :comment)
                        ON CONFLICT (rater_id, rated_id) DO UPDATE
                            SET score      = EXCLUDED.score,
                                comment    = EXCLUDED.comment,
                                updated_at = NOW()
                        RETURNING id
                    )
                    SELECT upsert.id,
                           (old_val.id IS NOT NULL) AS was_update,
                           old_val.score             AS old_score,
                           old_val.comment           AS old_comment
                    FROM upsert LEFT JOIN old_val ON true
                """),
                {
                    "rater_id": rater_id,
                    "rated_id": rated_id,
                    "score": score,
                    "comment": comment,
                },
            )).one()

            rating_id: int = row.id
            was_update: bool = row.was_update

            if was_update:
                logger.info(
                    "[UpsertRatingCommand] Updated | rater=%s rated=%s score=%s",
                    rater_id, rated_id, score,
                )
                old_score = row.old_score
                if old_score != score:
                    self.uow.session.add(RatingHistory(
                        rating_id=rating_id,
                        score=old_score,
                        comment=row.old_comment,
                    ))
                    rater = await self.uow.session.scalar(
                        select(User).where(User.id == rater_id)
                    )
                    if rater:
                        notif_payload = {
                            "user_id": rated_id,
                            "notif": {
                                "type": "rating_updated",
                                "i18n": {
                                    "title_key": "notifRatingUpdatedTitle",
                                    "title_params": {"username": rater.username},
                                },
                                "related_id": rater.id,
                                "sender_username": rater.username,
                                "sender_image_url": rater.profile_image_url,
                            },
                            "pref_key": "ratings",
                        }
            else:
                logger.info(
                    "[UpsertRatingCommand] Created | rater=%s rated=%s score=%s",
                    rater_id, rated_id, score,
                )

        # UoW commit tamamlandı; bildirim bağımsız async görev olarak başlatılır
        if notif_payload:
            asyncio.create_task(push_notification(**notif_payload))

        return {"ok": True}
