import asyncio
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.enums import UserStatus
from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.follow import Follow
from app.models.user import User
from app.models.message_thread import MessageThread
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException, ConflictException
from app.use_cases.follows.queries.get_followers_query import GetFollowersQuery
from app.use_cases.follows.queries.get_following_query import GetFollowingQuery
from app.use_cases.messages.queries.get_thread_status_query import _compute_can_call
from app.services.dm_broadcast import broadcast_dm


async def _broadcast_can_call_updated(uid_a: int, uid_b: int, db: AsyncSession) -> None:
    """Follow değişiminden sonra her iki tarafa güncel can_call gönder."""
    follows_ab = await db.scalar(
        select(Follow).where(Follow.follower_id == uid_a, Follow.followed_id == uid_b, Follow.status == "accepted")
    )
    follows_ba = await db.scalar(
        select(Follow).where(Follow.follower_id == uid_b, Follow.followed_id == uid_a, Follow.status == "accepted")
    )
    user_a, user_b = min(uid_a, uid_b), max(uid_a, uid_b)
    thread = await db.scalar(
        select(MessageThread).where(MessageThread.user_a_id == user_a, MessageThread.user_b_id == user_b)
    )
    # uid_a → uid_b can_call
    can_call_ab, reason_ab = _compute_can_call(
        viewer_follows_target=follows_ab is not None,
        target_follows_viewer=follows_ba is not None,
        thread_status=thread.status if thread else None,
        call_allowed=thread.call_allowed if thread else False,
    )
    # uid_b → uid_a can_call
    can_call_ba, reason_ba = _compute_can_call(
        viewer_follows_target=follows_ba is not None,
        target_follows_viewer=follows_ab is not None,
        thread_status=thread.status if thread else None,
        call_allowed=thread.call_allowed if thread else False,
    )
    asyncio.create_task(broadcast_dm(uid_a, {"type": "can_call_changed", "user_id": uid_b, "can_call": can_call_ab, "reason": reason_ab}))
    asyncio.create_task(broadcast_dm(uid_b, {"type": "can_call_changed", "user_id": uid_a, "can_call": can_call_ba, "reason": reason_ba}))

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
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)  # noqa: E712
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
        .where(Follow.followed_id == current_user.id, Follow.status == "pending", User.status == UserStatus.ACTIVE)
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


@router.get("/requests/sent")
async def get_sent_follow_requests(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rows = await db.execute(
        select(User)
        .join(Follow, Follow.followed_id == User.id)
        .where(Follow.follower_id == current_user.id, Follow.status == "pending", User.status == UserStatus.ACTIVE)
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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise ForbiddenException(code="SELF_FOLLOW_FORBIDDEN")

    target = await db.scalar(
        select(User).where(User.id == user_id, User.status == UserStatus.ACTIVE)  # noqa: E712
    )
    if not target:
        raise NotFoundException(code="USER_NOT_FOUND")

    existing = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if existing:
        raise ConflictException(code="ALREADY_FOLLOWING")

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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == current_user.id, Follow.followed_id == user_id)
    )
    if not follow:
        raise NotFoundException(code="FOLLOW_RECORD_NOT_FOUND")
    unfollowed_id = user_id
    await db.delete(follow)
    await db.commit()
    asyncio.create_task(_broadcast_can_call_updated(current_user.id, unfollowed_id, db))
    return {"ok": True}


@router.get("/{user_id}/followers")
async def get_followers(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetFollowersQuery(uow).execute(user_id, current_user)


@router.get("/{user_id}/following")
async def get_following(
    user_id: int,
    current_user: Optional[User] = Depends(_optional_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetFollowingQuery(uow).execute(user_id, current_user)
@router.post("/{follower_id}/accept")
async def accept_follow_request(
    follower_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == current_user.id, Follow.status == "pending")
    )
    if not follow:
        raise NotFoundException(code="FOLLOW_REQUEST_NOT_FOUND")
    
    follow.status = "accepted"

    # Follow kabul edilince mesaj isteği de normal konuşmaya dönüşür
    from sqlalchemy import update as sa_update
    from app.models.message_thread import MessageThread
    from app.utils.redis_client import get_redis
    user_a, user_b = min(follower_id, current_user.id), max(follower_id, current_user.id)
    await db.execute(
        sa_update(MessageThread)
        .where(
            MessageThread.user_a_id == user_a,
            MessageThread.user_b_id == user_b,
            MessageThread.status == "pending",
        )
        .values(status="accepted")
    )
    await db.commit()
    _redis = await get_redis()
    await _redis.decr(f"msg:unread:request:{current_user.id}")

    asyncio.create_task(_broadcast_can_call_updated(follower_id, current_user.id, db))

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
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    follow = await db.scalar(
        select(Follow).where(Follow.follower_id == follower_id, Follow.followed_id == current_user.id, Follow.status == "pending")
    )
    if not follow:
        raise NotFoundException(code="FOLLOW_REQUEST_NOT_FOUND")
    
    await db.delete(follow)
    await db.commit()
    return {"ok": True}
