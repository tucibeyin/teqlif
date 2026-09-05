import asyncio
from sqlalchemy import select, and_
from app.core.uow import AbstractUnitOfWork
from app.core.exceptions import NotFoundException
from app.models.message_thread import MessageThread
from app.models.follow import Follow
from app.services.dm_broadcast import broadcast_dm
from app.use_cases.messages.queries.get_thread_status_query import _compute_can_call
from app.utils.redis_client import get_redis


class DeclineMessageRequestCommand:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, requester_id: int) -> None:
        user_a, user_b = min(uid, requester_id), max(uid, requester_id)
        uid_follows_req = False
        req_follows_uid = False

        async with self.uow:
            thread = await self.uow.session.scalar(
                select(MessageThread).where(
                    MessageThread.user_a_id == user_a,
                    MessageThread.user_b_id == user_b,
                    MessageThread.status == "pending",
                )
            )
            if not thread:
                raise NotFoundException(code="MESSAGE_REQUEST_NOT_FOUND")

            thread.status = "declined"
            thread.call_allowed = False

            uid_follows_req = bool(await self.uow.session.scalar(
                select(Follow).where(
                    and_(Follow.follower_id == uid, Follow.followed_id == requester_id, Follow.status == "accepted")
                )
            ))
            req_follows_uid = bool(await self.uow.session.scalar(
                select(Follow).where(
                    and_(Follow.follower_id == requester_id, Follow.followed_id == uid, Follow.status == "accepted")
                )
            ))

        redis = await get_redis()
        await redis.decr(f"msg:unread:request:{uid}")

        can_call_uid, reason_uid = _compute_can_call(uid_follows_req, req_follows_uid, "declined", False)
        can_call_req, reason_req = _compute_can_call(req_follows_uid, uid_follows_req, "declined", False)

        asyncio.create_task(broadcast_dm(uid, {
            "type": "can_call_changed",
            "user_id": requester_id,
            "can_call": can_call_uid,
            "reason": reason_uid,
            "call_permission_editable": False,
            "thread_status": "declined",
            "call_allowed": False,
        }))
        asyncio.create_task(broadcast_dm(requester_id, {
            "type": "can_call_changed",
            "user_id": uid,
            "can_call": can_call_req,
            "reason": reason_req,
            "call_permission_editable": False,
            "thread_status": "declined",
            "call_allowed": False,
        }))
