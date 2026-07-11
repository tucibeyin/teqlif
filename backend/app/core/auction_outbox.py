"""
Auction Event Outbox — Redis Stream tabanlı.

Sorun: publish_auction() DB commit'ten sonra çağrılır. Aralarında process
crash olursa WebSocket client'lar güncellemeyi kaçırır.

Çözüm: İki katmanlı yayın:
  1. Gerçek zamanlı: mevcut Redis Pub/Sub (değişmez)
  2. Dayanıklı:     Redis Stream auction:events:{stream_id}
                    → WebSocket bağlanınca son N event replay edilir
                    → Bağlantı kesintisinde missed event'ler yakalanır

Stream key: auction:events:{stream_id}
  TTL      : 24 saat (artırma süresiyle eş)
  Max len  : 200 event (MAXLEN ~200)
  Consumer group: her worker için ayrı group gerekmez —
                  sadece reconnect replay için kullanılır (XREVRANGE)

Kullanım (auction_service.py'de):
    from app.core.auction_outbox import outbox_publish, outbox_replay

    # Yayın: Pub/Sub ile birlikte çağrılır
    await outbox_publish(stream_id, {"type": "AUCTION_STATE", ...})

    # Replay: WebSocket bağlantısında son 10 eventi gönder
    events = await outbox_replay(stream_id, count=10)
"""
from __future__ import annotations

import json

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

_STREAM_PREFIX = "auction:events"
_MAX_LEN       = 200
_TTL_SECONDS   = 86_400  # 24 saat


def _stream_key(stream_id: int) -> str:
    return f"{_STREAM_PREFIX}:{stream_id}"


async def outbox_publish(stream_id: int, payload: dict) -> None:
    """
    Event'i Redis Stream'e yazar (XADD).
    publish_auction() ile birlikte çağrılır; pub/sub başarısız olsa bile
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
        logger.warning("[OUTBOX] Stream yazılamadı | stream_id=%s | %s", stream_id, exc)


async def outbox_replay(stream_id: int, count: int = 20) -> list[dict]:
    """
    Son `count` event'i en yeniden eskiye döner.
    WebSocket bağlantısında catch-up için kullanılır.
    """
    try:
        redis = await get_redis()
        key = _stream_key(stream_id)
        entries = await redis.xrevrange(key, count=count)
        return [json.loads(entry[1]["data"]) for entry in entries if "data" in entry[1]]
    except Exception as exc:
        logger.warning("[OUTBOX] Stream okunamadı | stream_id=%s | %s", stream_id, exc)
        return []
