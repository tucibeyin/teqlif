from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError

from app.database import get_db
from app.models.user import User
from app.models.listing import Listing
from app.models.follow import Follow
from app.models.stream import LiveStream
from app.models.block import UserBlock
from app.schemas.block import BlockedUserOut, BlockStatusOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token

router = APIRouter(prefix="/api/users", tags=["users"])


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


@router.get("/blocked", response_model=List[BlockedUserOut])
async def list_blocked_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User)
        .join(UserBlock, UserBlock.blocked_id == User.id)
        .where(UserBlock.blocker_id == current_user.id)
        .order_by(UserBlock.created_at.desc())
    )
    return result.scalars().all()


@router.post("/{username}/block", response_model=BlockStatusOut)
async def block_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.username == username, User.is_active == True)  # noqa: E712
    )
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")
    if target.id == current_user.id:
        raise HTTPException(status_code=400, detail="Kendinizi engelleyemezsiniz")

    block = UserBlock(blocker_id=current_user.id, blocked_id=target.id)
    db.add(block)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()  # already blocked — idempotent
    return BlockStatusOut(is_blocked=True)


@router.delete("/{username}/block", response_model=BlockStatusOut)
async def unblock_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.username == username, User.is_active == True)  # noqa: E712
    )
    target = result.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    block = await db.scalar(
        select(UserBlock).where(
            UserBlock.blocker_id == current_user.id,
            UserBlock.blocked_id == target.id,
        )
    )
    if block:
        await db.delete(block)
        await db.commit()
    return BlockStatusOut(is_blocked=False)


@router.get("/{username}")
async def get_user_profile(
    username: str,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User).where(User.username == username, User.is_active == True)  # noqa: E712
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    listing_count = await db.scalar(
        select(func.count()).where(Listing.user_id == user.id, Listing.is_active == True)  # noqa: E712
    ) or 0

    follower_count = await db.scalar(
        select(func.count()).where(Follow.followed_id == user.id)
    ) or 0

    following_count = await db.scalar(
        select(func.count()).where(Follow.follower_id == user.id)
    ) or 0

    is_following = False
    is_blocked = False
    if current_user and current_user.id != user.id:
        chk = await db.scalar(
            select(Follow).where(
                Follow.follower_id == current_user.id,
                Follow.followed_id == user.id,
            )
        )
        is_following = chk is not None

        block_chk = await db.scalar(
            select(UserBlock).where(
                UserBlock.blocker_id == current_user.id,
                UserBlock.blocked_id == user.id,
            )
        )
        is_blocked = block_chk is not None

    active_stream = await db.scalar(
        select(LiveStream).where(
            LiveStream.host_id == user.id,
            LiveStream.is_live == True,  # noqa: E712
        )
    )

    return {
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "profile_image_url": user.profile_image_url,
        "listing_count": listing_count,
        "follower_count": follower_count,
        "following_count": following_count,
        "is_following": is_following,
        "is_blocked": is_blocked,
        "is_live": active_stream is not None,
        "active_stream_id": active_stream.id if active_stream else None,
    }
