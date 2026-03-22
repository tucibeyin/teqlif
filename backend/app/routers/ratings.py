from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

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
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    return result.scalar_one_or_none()


@router.post("/{user_id}")
async def upsert_rating(
    user_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Hedef kullanıcıya puan ver (veya güncelle). Takip etmek zorunlu."""
    if user_id == current_user.id:
        raise BadRequestException("Kendinizi puanlayamazsınız")

    # Hedef kullanıcı var mı?
    target = await db.scalar(
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    if not target:
        raise NotFoundException("Kullanıcı bulunamadı")

    # Takip kontrolü
    is_following = await db.scalar(
        select(Follow).where(
            Follow.follower_id == current_user.id,
            Follow.followed_id == user_id,
        )
    )
    if not is_following:
        raise ForbiddenException("Puan vermek için bu kullanıcıyı takip etmelisiniz")

    score = payload.get("score")
    if not isinstance(score, int) or score < 1 or score > 5:
        raise BadRequestException("Puan 1 ile 5 arasında olmalıdır")

    comment = (payload.get("comment") or "").strip() or None
    if comment and len(comment) > 500:
        raise BadRequestException("Yorum 500 karakteri geçemez")

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
        raise NotFoundException("Puan bulunamadı")
    await db.delete(rating)
    await db.commit()
    return {"ok": True}
