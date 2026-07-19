"""Redis helpers for group call participant tracking and invite locks."""
import logging
from typing import List, Optional

from app.utils.redis_client import get_redis

logger = logging.getLogger(__name__)

# Key TTLs
_PARTICIPANTS_TTL = 3 * 60 * 60   # 3 hours — longer than any realistic call
_INVITE_LOCK_TTL  = 35             # seconds — slightly more than invite_timeout_task delay (30s)


def _participants_key(call_id: int) -> str:
    return f"call:{call_id}:participants"


def _invite_lock_key(call_id: int, user_id: int) -> str:
    return f"call:{call_id}:invite:{user_id}"


async def add_participant_redis(call_id: int, user_id: int) -> None:
    """Add user_id to the call's active participant SET."""
    r = await get_redis()
    key = _participants_key(call_id)
    await r.sadd(key, str(user_id))
    await r.expire(key, _PARTICIPANTS_TTL)
    logger.debug("[CALL_REDIS] add_participant call_id=%s user_id=%s", call_id, user_id)


async def remove_participant_redis(call_id: int, user_id: int) -> None:
    """Remove user_id from the call's active participant SET."""
    r = await get_redis()
    await r.srem(_participants_key(call_id), str(user_id))
    logger.debug("[CALL_REDIS] remove_participant call_id=%s user_id=%s", call_id, user_id)


async def get_participants_redis(call_id: int) -> List[int]:
    """Return list of user_ids currently in the call (joined state tracked in Redis)."""
    r = await get_redis()
    members = await r.smembers(_participants_key(call_id))
    return [int(m) for m in members]


async def is_participant_redis(call_id: int, user_id: int) -> bool:
    r = await get_redis()
    return await r.sismember(_participants_key(call_id), str(user_id))


async def acquire_invite_lock(call_id: int, user_id: int) -> bool:
    """Set a NX lock to prevent duplicate in-flight invites. Returns True if lock acquired."""
    r = await get_redis()
    key = _invite_lock_key(call_id, user_id)
    result = await r.set(key, "1", ex=_INVITE_LOCK_TTL, nx=True)
    logger.debug("[CALL_REDIS] invite_lock call_id=%s user_id=%s acquired=%s", call_id, user_id, result)
    return result is not None


async def release_invite_lock(call_id: int, user_id: int) -> None:
    r = await get_redis()
    await r.delete(_invite_lock_key(call_id, user_id))
    logger.debug("[CALL_REDIS] invite_lock_release call_id=%s user_id=%s", call_id, user_id)


async def clear_call_redis(call_id: int) -> None:
    """Clean up all Redis state for a call when it ends."""
    r = await get_redis()
    await r.delete(_participants_key(call_id))
    logger.debug("[CALL_REDIS] clear_call call_id=%s", call_id)
