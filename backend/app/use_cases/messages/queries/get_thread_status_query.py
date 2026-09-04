from sqlalchemy import select, and_
from app.core.uow import AbstractUnitOfWork
from app.models.message_thread import MessageThread
from app.models.follow import Follow


def _compute_can_call(
    viewer_follows_target: bool,
    target_follows_viewer: bool,
    thread_status: str | None,
    call_allowed: bool,
) -> bool:
    """caller=viewer, callee=target perspektifinden can_call hesaplar."""
    # Mutual follow
    if viewer_follows_target and target_follows_viewer:
        return True
    # Takip edilen (viewer) → Takipçi (target): her zaman arayabilir
    if target_follows_viewer and not viewer_follows_target:
        return True
    # Takipçi (viewer) → Takip edilen (target): toggle kontrolü
    if viewer_follows_target and not target_follows_viewer:
        return call_allowed if thread_status == "accepted" else False
    # Follow yok — kabul edilmiş thread + toggle
    if thread_status == "accepted":
        return call_allowed
    return False


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

        can_call = _compute_can_call(
            viewer_follows_target=follows_other is not None,
            target_follows_viewer=followed_by_other is not None,
            thread_status=thread.status if thread else None,
            call_allowed=thread.call_allowed if thread else False,
        )

        if not thread:
            return {"status": None, "is_initiator": False, "can_call": can_call, "call_allowed": False}
        return {
            "status": thread.status,
            "is_initiator": thread.initiator_id == uid,
            "can_call": can_call,
            "call_allowed": thread.call_allowed,
        }
