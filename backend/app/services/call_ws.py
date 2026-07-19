"""WebSocket broadcast helpers for group call events."""
import logging
from typing import List

from app.core.ws_manager import ws_manager
from app.utils.call_redis import get_participants_redis

logger = logging.getLogger(__name__)

_DM_CHANNEL = "dm_broadcast"


async def send_to_user(user_id: int, payload: dict) -> None:
    """Send a WS message to a single user via their dm channel."""
    logger.debug("[CALL_WS] send_to_user user_id=%s type=%s", user_id, payload.get("type"))
    await ws_manager.publish(_DM_CHANNEL, f"dm:{user_id}", payload)


async def broadcast_to_call_participants(
    call_id: int,
    payload: dict,
    exclude_user_id: int | None = None,
) -> None:
    """
    Send a WS message to all current participants of a call (tracked in Redis SET).
    Optionally exclude one user (e.g. the sender themselves).
    """
    participant_ids: List[int] = await get_participants_redis(call_id)
    logger.debug(
        "[CALL_WS] broadcast_to_call call_id=%s type=%s participants=%s exclude=%s",
        call_id, payload.get("type"), participant_ids, exclude_user_id,
    )
    for uid in participant_ids:
        if exclude_user_id is not None and uid == exclude_user_id:
            continue
        await ws_manager.publish(_DM_CHANNEL, f"dm:{uid}", payload)
