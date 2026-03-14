from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.database import get_db
from app.models.user import User
from app.models.listing import Listing
from app.models.follow import Follow
from app.utils.auth import get_current_user

router = APIRouter(prefix="/api/users", tags=["users"])


async def _optional_user(db: AsyncSession = Depends(get_db)):
    """Returns None if not authenticated."""
    return None


@router.get("/{username}")
async def get_user_profile(
    username: str,
    db: AsyncSession = Depends(get_db),
    # optional auth — we try to read token manually below
):
    result = await db.execute(
        select(User).where(User.username == username, User.is_active == True)  # noqa: E712
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    # Count listings
    listing_count_result = await db.execute(
        select(func.count()).where(Listing.user_id == user.id, Listing.is_active == True)  # noqa: E712
    )
    listing_count = listing_count_result.scalar() or 0

    # Count followers
    follower_count_result = await db.execute(
        select(func.count()).where(Follow.followed_id == user.id)
    )
    follower_count = follower_count_result.scalar() or 0

    # Count following
    following_count_result = await db.execute(
        select(func.count()).where(Follow.follower_id == user.id)
    )
    following_count = following_count_result.scalar() or 0

    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "listing_count": listing_count,
        "follower_count": follower_count,
        "following_count": following_count,
    }


@router.get("/{username}/is-following")
async def check_is_following(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.username == username))
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
    follow = await db.execute(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == target.id)
    )
    return {"is_following": follow.scalar_one_or_none() is not None}
