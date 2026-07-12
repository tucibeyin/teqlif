import asyncio
from typing import Optional

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.follow import Follow
from app.models.user import User
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.core.exceptions import NotFoundException, BadRequestException
from app.utils.i18n import _msg

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
@router.get("/requests")
async def get_follow_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rows = await db.execute(
        select(User)
        .join(Follow, Follow.follower_id == User.id)
        .where(Follow.followed_id == current_user.id, Follow.status == "pending", User.is_active == True)
        .order_by(Follow.created_at.desc())
    )
    users = rows.scalars().all()
    return [
        {
            "id": u.id,
            "username": u.username,
            "full_name": u.full_name,
            "profile_image_thumb_url": u.profile_image_thumb_url,
        }
        for u in users
    ]


@router.post("/{user_id}")
async def follow_user(
    user_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise BadRequestException(_msg(request, None, "errFollowSelf", "Kendinizi takip edemezsiniz"))

    target = await db.scalar(
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    if not target:
        raise NotFoundException(_msg(request, None, "errUserNotFound", "Kullanıcı bulunamadı"))

    existing = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if existing:
        raise BadRequestException(_msg(request, None, "errAlreadyFollowing", "Zaten takip ediyorsunuz veya istek gönderilmiş"))

    status = "pending" if target.is_private else "accepted"
    follow = Follow(follower_id=current_user.id, followed_id=user_id, status=status)
    db.add(follow)
    await db.commit()

    from app.routers.notifications import push_notification
    if status == "pending":
        asyncio.create_task(push_notification(
            user_id=user_id,
            notif={
                "type": "follow_request",
                "i18n": {
                    "title_key": "notifFollowRequestTitle",
                    "title_params": {"username": current_user.username},
                },
                "body": current_user.username,
                "related_id": current_user.id,
                "sender_username": current_user.username,
            },
            pref_key="follows",
        ))
    else:
        asyncio.create_task(push_notification(
            user_id=user_id,
            notif={
                "type": "follow",
                "i18n": {
                    "title_key": "notifFollow",
                    "title_params": {"username": current_user.username},
                },
                "body": current_user.username,
                "related_id": current_user.id,
                "sender_username": current_user.username,
            },
            pref_key="follows",
        ))

    return {"ok": True, "status": status}

@router.delete("/{user_id}")
async def unfollow_user(
    user_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if not follow:
        raise NotFoundException(_msg(request, None, "errFollowRecordNotFound", "Takip kaydı bulunamadı"))
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
        .where(Follow.followed_id == user_id, Follow.status == "accepted", User.is_active == True)  # noqa: E712
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
        .where(Follow.follower_id == user_id, Follow.status == "accepted", User.is_active == True)  # noqa: E712
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
@router.post("/{follower_id}/accept")
async def accept_follow_request(
    follower_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == current_user.id, Follow.status == "pending")
    )
    if not follow:
        raise NotFoundException(_msg(request, None, "errFollowRequestNotFound", "Takip isteği bulunamadı"))
    
    follow.status = "accepted"
    await db.commit()

    from app.routers.notifications import push_notification
    asyncio.create_task(push_notification(
        user_id=follower_id,
        notif={
            "type": "follow_accepted",
            "i18n": {
                "title_key": "notifFollowAcceptedTitle",
                "title_params": {"username": current_user.username},
            },
            "body": current_user.username,
            "related_id": current_user.id,
            "sender_username": current_user.username,
        },
        pref_key="follows",
    ))

    return {"ok": True}

@router.post("/{follower_id}/reject")
async def reject_follow_request(
    follower_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == current_user.id, Follow.status == "pending")
    )
    if not follow:
        raise NotFoundException(_msg(request, None, "errFollowRequestNotFound", "Takip isteği bulunamadı"))
    
    await db.delete(follow)
    await db.commit()
    return {"ok": True}
