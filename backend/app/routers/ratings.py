from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import UserStatus
from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.follow import Follow
from app.models.rating import Rating
from app.models.rating_history import RatingHistory
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException
from app.use_cases.ratings.commands.upsert_rating import UpsertRatingCommand
from app.use_cases.ratings.commands.reply_rating import ReplyRatingCommand

router = APIRouter(prefix="/api/ratings", tags=["ratings"])


async def _optional_user(
    credentials=Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    if not credentials:
        return None
    user_id = decode_token(credentials.credentials)
    if not user_id:
        return None
    result = await db.execute(
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)
    )
    return result.scalar_one_or_none()


def _serialize_history(history_rows) -> list:
    return [
        {
            "score": h.score,
            "comment": h.comment,
            "changed_at": h.changed_at.isoformat() if h.changed_at else None,
        }
        for h in history_rows
    ]


async def _fetch_history(db: AsyncSession, rating_ids: list[int]) -> dict[int, list]:
    """rating_id → history list sözlüğü döndürür (toplu sorgu)."""
    if not rating_ids:
        return {}
    rows = await db.execute(
        select(RatingHistory)
        .where(RatingHistory.rating_id.in_(rating_ids))
        .order_by(RatingHistory.rating_id, RatingHistory.changed_at.asc())
    )
    history_map: dict[int, list] = {}
    for h in rows.scalars().all():
        history_map.setdefault(h.rating_id, []).append(
            {
                "score": h.score,
                "comment": h.comment,
                "changed_at": h.changed_at.isoformat() if h.changed_at else None,
            }
        )
    return history_map


@router.get("/me/unread-count")
async def get_unread_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    count = await db.scalar(
        select(func.count(Rating.id))
        .where(Rating.rated_id == current_user.id, Rating.is_read == False)
    )
    return {"unread_count": count or 0}


@router.patch("/me/mark-read")
async def mark_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ratings = await db.scalars(
        select(Rating).where(Rating.rated_id == current_user.id, Rating.is_read == False)
    )
    for r in ratings:
        r.is_read = True
    await db.commit()
    return {"ok": True}


@router.get("/me/received")
async def get_my_received_ratings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının aldığı değerlendirmeler — yanıt ve geçmiş bilgisiyle."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rater_id)
        .where(Rating.rated_id == current_user.id)
        .order_by(Rating.created_at.desc())
    )
    pairs = rows.all()
    rating_ids = [r.id for r, _ in pairs]
    history_map = await _fetch_history(db, rating_ids)

    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "reply": r.reply,
            "replied_at": r.replied_at.isoformat() if r.replied_at else None,
            "is_read": r.is_read,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "history": history_map.get(r.id, []),
            "rater": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in pairs
    ]


@router.get("/me/given")
async def get_my_given_ratings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının verdiği değerlendirmeler — geçmiş bilgisiyle."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rated_id)
        .where(Rating.rater_id == current_user.id)
        .order_by(Rating.created_at.desc())
    )
    pairs = rows.all()
    rating_ids = [r.id for r, _ in pairs]
    history_map = await _fetch_history(db, rating_ids)

    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "reply": r.reply,
            "replied_at": r.replied_at.isoformat() if r.replied_at else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "history": history_map.get(r.id, []),
            "rated": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in pairs
    ]


@router.post("/{user_id}")
async def upsert_rating(
    user_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    """Hedef kullanıcıya puan ver veya güncelle. Eski değer history'ye yazılır."""
    score = payload.get("score")
    comment = (payload.get("comment") or "").strip() or None
    return await UpsertRatingCommand(uow).execute(
        rater_id=current_user.id,
        rated_id=user_id,
        score=score,
        comment=comment,
    )


@router.post("/reply/{rating_id}")
async def reply_rating(
    rating_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    """Değerlendirilen kişi aldığı değerlendirmeye yanıt yazar."""
    reply_text = (payload.get("reply") or "").strip()
    return await ReplyRatingCommand(uow).execute(
        rating_id=rating_id,
        replier_id=current_user.id,
        reply_text=reply_text,
    )


@router.get("/{user_id}/summary")
async def get_rating_summary(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    row = await db.execute(
        select(func.avg(Rating.score), func.count(Rating.id))
        .where(Rating.rated_id == user_id)
    )
    avg, count = row.one()

    my_rating = None
    if current_user and current_user.id != user_id:
        my_rating = await db.scalar(
            select(Rating).where(
                Rating.rater_id == current_user.id, Rating.rated_id == user_id
            )
        )

    return {
        "average": round(float(avg), 1) if avg else None,
        "count": count,
        "my_rating": {
            "score": my_rating.score,
            "comment": my_rating.comment,
        } if my_rating else None,
    }


@router.get("/{user_id}")
async def get_ratings(
    user_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcıya verilen tüm puanlar — yanıt ve geçmiş bilgisiyle."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rater_id)
        .where(Rating.rated_id == user_id)
        .order_by(Rating.updated_at.desc())
    )
    pairs = rows.all()
    rating_ids = [r.id for r, _ in pairs]
    history_map = await _fetch_history(db, rating_ids)

    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "reply": r.reply,
            "replied_at": r.replied_at.isoformat() if r.replied_at else None,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "history": history_map.get(r.id, []),
            "rater": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in pairs
    ]


@router.delete("/{user_id}")
async def delete_rating(
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rating = await db.scalar(
        select(Rating).where(
            Rating.rater_id == current_user.id, Rating.rated_id == user_id
        )
    )
    if not rating:
        raise NotFoundException(code="RATING_NOT_FOUND")
    await db.delete(rating)
    await db.commit()
    return {"ok": True}
