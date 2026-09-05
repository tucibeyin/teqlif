"""
Call presence — kullanıcının anlık arama durumunu Redis'te tutar.

Üç noktada kullanılır:
1. RelationshipStateService: can_call hesabında hedef meşgulse 'user_busy' reason'ı verir.
2. start_call: caller/callee'yi 'ringing' olarak işaretler.
3. accept/reject/end/missed: varlığı günceller veya temizler.

TTL kasıtlı olarak uzun tutulmuştur (10 dk) — aramanın azami süresi +
bir server crash'inde bile orphan presence'ın otomatik temizlenmesi için.
"""
import json
from typing import Optional

from app.utils.redis_client import get_redis

_PRESENCE_TTL = 600  # saniye — 10 dakika


def _key(uid: int) -> str:
    return f"user:call_presence:{uid}"


async def set_presence(uid: int, status: str, call_id: int, peers: list[int]) -> None:
    """status: 'ringing' | 'in_call'"""
    r = await get_redis()
    await r.set(
        _key(uid),
        json.dumps({"status": status, "call_id": call_id, "peers": peers}),
        ex=_PRESENCE_TTL,
    )


async def clear_presence(uid: int) -> None:
    r = await get_redis()
    await r.delete(_key(uid))


async def get_presence(uid: int) -> Optional[dict]:
    r = await get_redis()
    raw = await r.get(_key(uid))
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None


async def is_busy(uid: int) -> bool:
    p = await get_presence(uid)
    return p is not None and p.get("status") in ("ringing", "in_call")
