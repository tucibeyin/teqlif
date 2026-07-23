from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import UserStatus
from app.database import get_db
from app.models.follow import Follow
from app.models.rating import Rating
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException

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
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)  # noqa: E712
    )
    return result.scalar_one_or_none()


@router.get("/me/unread-count")
async def get_unread_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Giriş yapan kullanıcının okumadığı değerlendirmelerin sayısını döndürür."""
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
    """Kullanıcının okumadığı tüm değerlendirmeleri okundu olarak işaretler."""
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
    """Kullanıcının aldığı değerlendirmeleri (puanlayan kişinin detaylarıyla) listeler."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rater_id)
        .where(Rating.rated_id == current_user.id)
        .order_by(Rating.created_at.desc())
    )
    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "is_read": r.is_read,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "rater": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in rows.all()
    ]


@router.get("/me/given")
async def get_my_given_ratings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının başkalarına verdiği değerlendirmeleri (puanlanan kişinin detaylarıyla) listeler."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rated_id)
        .where(Rating.rater_id == current_user.id)
        .order_by(Rating.created_at.desc())
    )
    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "rated": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in rows.all()
    ]


@router.post("/{user_id}")
async def upsert_rating(
    user_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Hedef kullanıcıya puan ver (veya güncelle). Takip etmek zorunlu."""
    if user_id == current_user.id:
        raise ForbiddenException(code="SELF_RATING_FORBIDDEN")

    # Hedef kullanıcı var mı?
    target = await db.scalar(
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)  # noqa: E712
    )
    if not target:
        raise NotFoundException(code="USER_NOT_FOUND")

    # Takip kontrolü
    is_following = await db.scalar(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.followed_id == user_id,
        )
    )
    if not is_following:
        raise ForbiddenException(code="RATING_REQUIRES_FOLLOW")

    score = payload.get("score")
    if not isinstance(score, int) or score < 1 or score > 5:
        raise BadRequestException(code="INVALID_RATING_RANGE")

    comment = (payload.get("comment") or "").strip() or None
    if comment and len(comment) > 500:
        raise BadRequestException(code="COMMENT_TOO_LONG")

    # Upsert: var olan puanı güncelle, yoksa oluştur
    existing = await db.scalar(
        select(Rating).where(Rating.rater_id == current_user.id, Rating.rated_id == user_id)
    )
    if existing:
        existing.score = score
        existing.comment = comment
    else:
        db.add(Rating(rater_id=current_user.id, rated_id=user_id, score=score, comment=comment))

    await db.commit()
    return {"ok": True}


@router.get("/{user_id}/summary")
async def get_rating_summary(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının puan ortalaması ve toplam puan sayısı."""
    row = await db.execute(
        select(func.avg(Rating.score), func.count(Rating.id))
        .where(Rating.rated_id == user_id)
    )
    avg, count = row.one()

    my_rating = None
    if current_user and current_user.id != user_id:
        my_rating = await db.scalar(
            select(Rating).where(Rating.rater_id == current_user.id, Rating.rated_id == user_id)
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
    """Kullanıcıya verilen tüm puanları listele (rater bilgisiyle)."""
    rows = await db.execute(
        select(Rating, User)
        .join(User, User.id == Rating.rater_id)
        .where(Rating.rated_id == user_id)
        .order_by(Rating.updated_at.desc())
    )
    return [
        {
            "id": r.id,
            "score": r.score,
            "comment": r.comment,
            "created_at": r.created_at.isoformat() if r.created_at else None,
            "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            "rater": {
                "id": u.id,
                "username": u.username,
                "full_name": u.full_name,
                "profile_image_url": u.profile_image_url,
            },
        }
        for r, u in rows.all()
    ]


@router.delete("/{user_id}")
async def delete_rating(
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Verilen puanı geri al."""
    rating = await db.scalar(
        select(Rating).where(Rating.rater_id == current_user.id, Rating.rated_id == user_id)
    )
    if not rating:
        raise NotFoundException(code="RATING_NOT_FOUND")
    await db.delete(rating)
    await db.commit()
    return {"ok": True}
