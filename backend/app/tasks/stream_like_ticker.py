"""
Stream kalp toplu yayın döngüsü (SRE-105).

Her ~1 saniyede bir Redis'teki stream:likes:pending:{stream_id} sayaçlarını
GETDEL ile atomik olarak okuyup sıfırlar ve tüm aktif yayınlara
stream_like_batch WS sinyali olarak iletir.

Böylece her kalp için ayrı WS paketi (C10K) yerine saniyede 1 paket gönderilir.
"""
from __future__ import annotations

import asyncio
from app.core.logger import get_logger

logger = get_logger(__name__)

_TICK_INTERVAL = 1.0
_SCAN_PATTERN = "stream:likes:pending:*"


async def stream_like_ticker() -> None:
    from app.utils.redis_client import get_redis
    from app.use_cases.chat.chat_utils import publish_chat
    from app.constants import ws_types as WS

    while True:
        try:
            await asyncio.sleep(_TICK_INTERVAL)
            redis = await get_redis()

            # SCAN: tüm pending sayaç key'lerini topla
            cursor = 0
            pending_keys: list[str] = []
            while True:
                cursor, keys = await redis.scan(cursor, match=_SCAN_PATTERN, count=100)
                pending_keys.extend(keys)
                if cursor == 0:
                    break

            if not pending_keys:
                continue

            # Pipeline: GETDEL — her key'i atomik oku+sıfırla
            pipe = redis.pipeline(transaction=False)
            for key in pending_keys:
                pipe.getdel(key)
            counts = await pipe.execute()

            # Batch WS broadcast: her aktif yayın için tek paket
            for key, count_str in zip(pending_keys, counts):
                if not count_str:
                    continue
                count = int(count_str)
                if count <= 0:
                    continue
                try:
                    stream_id = int(key.rsplit(":", 1)[-1])
                except ValueError:
                    continue
                try:
                    await publish_chat(stream_id, {
                        "type": WS.STREAM_LIKE_BATCH,
                        "count": count,
                    })
                except Exception as exc:
                    logger.warning(
                        "[LikeTicker] broadcast hatası | stream_id=%s | %s", stream_id, exc
                    )

        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("[LikeTicker] tick hatası | %s", exc)
