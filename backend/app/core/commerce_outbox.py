"""
Direct Sale Event Outbox — Redis Stream tabanlı.

auction_outbox.py ile aynı mekanizma; DS event'leri ayrı stream key'inde saklanır.
Bağlantı kesilip yeniden bağlanan istemci kaçırdığı DS event'lerini (satın alım,
duraklatma, devam vb.) replay ile alır.

Stream key: ds:events:{stream_id}
  TTL      : 24 saat (satış yaşam döngüsüyle eş)
  Max len  : 100 event
"""
from __future__ import annotations

import json
import time

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_STREAM_PREFIX = "ds:events"
_MAX_LEN       = 100
_TTL_SECONDS   = 86_400  # 24 saat


def _stream_key(stream_id: int) -> str:
    return f"{_STREAM_PREFIX}:{stream_id}"


async def ds_outbox_push(stream_id: int, payload: dict) -> None:
    """
    DS event'ini Redis Stream'e yazar (XADD).
    publish_direct_sale() ile birlikte çağrılır; pub/sub başarısız olsa bile
    event stream'de durur, reconnect sırasında replay edilir.
    """
    try:
        redis = await get_redis()
        key = _stream_key(stream_id)
        await redis.xadd(
            key,
            {"data": json.dumps(payload)},
            maxlen=_MAX_LEN,
            approximate=True,
        )
        await redis.expire(key, _TTL_SECONDS)
    except Exception as exc:
        logger.warning("[DS_OUTBOX] Stream yazılamadı | stream_id=%s | %s", stream_id, exc)


async def ds_outbox_replay(stream_id: int, count: int = 10, max_age_seconds: int = 30) -> list[dict]:
    """
    Son `count` DS event'ini en yeniden eskiye döner, yalnızca son `max_age_seconds` içindekiler.
    """
    try:
        redis = await get_redis()
        key = _stream_key(stream_id)
        min_ms = int((time.time() - max_age_seconds) * 1000)
        min_id = f"{min_ms}-0"
        entries = await redis.xrevrange(key, min=min_id, count=count)
        return [json.loads(entry[1]["data"]) for entry in entries if "data" in entry[1]]
    except Exception as exc:
        logger.warning("[DS_OUTBOX] Stream okunamadı | stream_id=%s | %s", stream_id, exc)
        return []
