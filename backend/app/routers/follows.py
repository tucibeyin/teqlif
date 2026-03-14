from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.database import get_db
from app.models.follow import Follow
from app.models.user import User
from app.utils.auth import get_current_user

router = APIRouter(prefix="/api/follows", tags=["follows"])


@router.post("/{user_id}")
async def follow_user(user_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Kendinizi takip edemezsiniz")
    existing = await db.execute(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Zaten takip ediyorsunuz")
    follow = Follow(follower_id=current_user.id, followed_id=user_id)
    db.add(follow)
    await db.commit()
    return {"ok": True}


@router.delete("/{user_id}")
async def unfollow_user(user_id: int, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    follow = result.scalar_one_or_none()
    if not follow:
        raise HTTPException(status_code=404, detail="Takip kaydı bulunamadı")
    await db.delete(follow)
    await db.commit()
    return {"ok": True}
