import asyncio
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.follow import Follow
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token

router = APIRouter(prefix="/api/follows", tags=["follows"])


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
async def follow_user(
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Kendinizi takip edemezsiniz")

    target = await db.scalar(
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    if not target:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    existing = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if existing:
        raise HTTPException(status_code=400, detail="Zaten takip ediyorsunuz")

    db.add(Follow(follower_id=current_user.id, followed_id=user_id))
    await db.commit()

    from app.routers.notifications import push_notification
    asyncio.create_task(push_notification(
        user_id=user_id,
        notif={
            "type": "follow",
            "title": f"@{current_user.username} seni takip etmeye başladı",
            "body": None,
            "related_id": current_user.id,
        },
    ))

    return {"ok": True}


@router.delete("/{user_id}")
async def unfollow_user(
    user_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if not follow:
        raise HTTPException(status_code=404, detail="Takip kaydı bulunamadı")
    await db.delete(follow)
    await db.commit()
    return {"ok": True}


@router.get("/{user_id}/followers")
async def get_followers(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    rows = await db.execute(
        select(User)
        .join(Follow, Follow.follower_id == User.id)
        .where(Follow.followed_id == user_id, User.is_active == True)  # noqa: E712
        .order_by(Follow.created_at.desc())
    )
    users = rows.scalars().all()

    following_ids: set[int] = set()
    if current_user and users:
        ids = [u.id for u in users]
        res = await db.execute(
            select(Follow.followed_id).where(
                Follow.follower_id == current_user.id,
                Follow.followed_id.in_(ids),
            )
        )
        following_ids = set(res.scalars())

    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "is_following": u.id in following_ids,
            "is_me": current_user is not None and u.id == current_user.id,
        }
        for u in users
    ]


@router.get("/{user_id}/following")
async def get_following(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    rows = await db.execute(
        select(User)
        .join(Follow, Follow.followed_id == User.id)
        .where(Follow.follower_id == user_id, User.is_active == True)  # noqa: E712
        .order_by(Follow.created_at.desc())
    )
    users = rows.scalars().all()

    following_ids: set[int] = set()
    if current_user and users:
        ids = [u.id for u in users]
        res = await db.execute(
            select(Follow.followed_id).where(
                Follow.follower_id == current_user.id,
                Follow.followed_id.in_(ids),
            )
        )
        following_ids = set(res.scalars())

    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "is_following": u.id in following_ids,
            "is_me": current_user is not None and u.id == current_user.id,
        }
        for u in users
    ]
