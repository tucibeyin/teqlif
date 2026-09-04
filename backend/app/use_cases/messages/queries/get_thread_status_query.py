from sqlalchemy import select, and_
from app.core.uow import AbstractUnitOfWork
from app.models.message_thread import MessageThread
from app.models.follow import Follow

_REASON_NO_FOLLOW     = "no_follow"
_REASON_PENDING       = "pending"
_REASON_CALL_DISABLED = "call_disabled"


def _compute_can_call(
    viewer_follows_target: bool,
    target_follows_viewer: bool,
    thread_status: str | None,
    call_allowed: bool,
) -> tuple[bool, str | None]:
    """
    caller=viewer, callee=target perspektifinden can_call hesaplar.
    Returns (can_call, reason) -- reason is None when can_call=True.
    """
    # Mutual follow
    if viewer_follows_target and target_follows_viewer:
        return True, None
    # Takip edilen (viewer) -> Takipci (target): her zaman arayabilir
    if target_follows_viewer and not viewer_follows_target:
        return True, None
    # Takipci (viewer) -> Takip edilen (target): toggle kontrolu
    if viewer_follows_target and not target_follows_viewer:
        if thread_status == "accepted":
            return (True, None) if call_allowed else (False, _REASON_CALL_DISABLED)
        if thread_status == "pending":
            return False, _REASON_PENDING
        return False, _REASON_NO_FOLLOW
    # Follow yok -- kabul edilmis thread + toggle
    if thread_status == "accepted":
        return (True, None) if call_allowed else (False, _REASON_CALL_DISABLED)
    if thread_status == "pending":
        return False, _REASON_PENDING
    return False, _REASON_NO_FOLLOW


class GetThreadStatusQuery:
    def __init__(self, uow: AbstractUnitOfWork):
        self.uow = uow

    async def execute(self, uid: int, other_id: int) -> dict:
        user_a, user_b = min(uid, other_id), max(uid, other_id)
        thread = await self.uow.session.scalar(
            select(MessageThread).where(
                MessageThread.user_a_id == user_a,
                MessageThread.user_b_id == user_b,
            )
        )

        follows_other = await self.uow.session.scalar(
            select(Follow).where(
                and_(
                    Follow.follower_id == uid,
                    Follow.followed_id == other_id,
                    Follow.status == "accepted",
                )
            )
        )
        followed_by_other = await self.uow.session.scalar(
            select(Follow).where(
                and_(
                    Follow.follower_id == other_id,
                    Follow.followed_id == uid,
                    Follow.status == "accepted",
                )
            )
        )

        can_call, can_call_reason = _compute_can_call(
            viewer_follows_target=follows_other is not None,
            target_follows_viewer=followed_by_other is not None,
            thread_status=thread.status if thread else None,
            call_allowed=thread.call_allowed if thread else False,
        )

        if not thread:
            return {
                "status": None,
                "is_initiator": False,
                "can_call": can_call,
                "can_call_reason": can_call_reason,
                "call_allowed": False,
            }
        return {
            "status": thread.status,
            "is_initiator": thread.initiator_id == uid,
            "can_call": can_call,
            "can_call_reason": can_call_reason,
            "call_allowed": thread.call_allowed,
        }
