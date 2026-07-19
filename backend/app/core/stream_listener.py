"""
Redis Stream Fan-Out Listener — Pub/Sub replacement.

Why not pub/sub?
  Pub/Sub is fire-and-forget.  Any message published while a subscriber is
  reconnecting is permanently lost.  In a 3-worker Gunicorn setup a single
  Redis blip silently drops DMs, call events, and chat messages for every
  user whose WebSocket happens to be on the reconnecting worker.

Why Streams?
  Each worker tracks its own read position (`stream_pos:{name}:{pid}`) in
  Redis.  On restart the worker reads from the saved position and delivers
  every message that arrived during the downtime — in order, exactly once per
  worker.  The stream retains the last STREAM_MAXLEN messages; anything older
  is trimmed automatically.

Fan-out semantics:
  Unlike consumer groups (each message → one consumer), every worker reads the
  stream independently.  This mirrors pub/sub fan-out: all workers see all
  messages, only the one that has the target WebSocket connection actually
  delivers it.

Dead-Letter Queue (DLQ):
  When on_message() raises, the raw entry is written to `dlq:{stream_name}`
  before the position advances.  This makes every processing failure visible
  and inspectable without blocking delivery of subsequent messages.

  Inspect via redis-cli:
    XLEN dlq:dm_broadcast
    XREVRANGE dlq:dm_broadcast + - COUNT 10

Usage:
    from app.core.stream_listener import stream_listener

    async def my_listener() -> None:
        async def _handle(data: dict) -> None:
            topic = data.pop("_topic")
            asyncio.create_task(ws_manager.broadcast_local(topic, data))
        await stream_listener("my_stream", _handle)
"""
from __future__ import annotations

import asyncio
import json
import os
import random
import time
from typing import Awaitable, Callable

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

# Messages retained per main stream (approximate — Redis trims lazily).
STREAM_MAXLEN = 500

# DLQ retains the last N failed entries per stream so the key never grows
# unboundedly, but there is always a recent window to inspect.
_DLQ_MAXLEN = 1_000
_DLQ_TTL    = 7 * 86_400   # 7 days — long enough for on-call to investigate

_BLOCK_MS  = 5_000   # XREAD block timeout — implicit keepalive
_MAX_DELAY = 30.0    # exponential backoff ceiling


async def _write_dlq(
    r,
    stream_name: str,
    msg_id: str,
    raw_data: str,
    exc: Exception,
) -> None:
    """Write a failed message to the dead-letter queue for this stream.

    Never raises — a DLQ write failure is logged at ERROR (Sentry) but must
    not interrupt delivery of the next message.
    """
    dlq_key = f"dlq:{stream_name}"
    try:
        await r.xadd(
            dlq_key,
            {
                "original_id":  msg_id,
                "stream":        stream_name,
                "data":          raw_data,
                "error":         str(exc)[:1000],
                "worker_pid":    str(os.getpid()),
                "failed_at":     str(int(time.time())),
            },
            maxlen=_DLQ_MAXLEN,
            approximate=True,
        )
        await r.expire(dlq_key, _DLQ_TTL)
        logger.warning(
            "[DLQ:%s] Başarısız mesaj kaydedildi | original_id=%s | hata=%s",
            stream_name, msg_id, exc,
        )
    except Exception as dlq_exc:
        # DLQ itself failed — escalate to Sentry so on-call knows
        logger.error(
            "[DLQ:%s] DLQ yazılamadı | original_id=%s | dlq_hata=%s | asıl_hata=%s",
            stream_name, msg_id, dlq_exc, exc,
        )


async def stream_listener(
    stream_name: str,
    on_message: Callable[[dict], Awaitable[None]],
) -> None:
    """
    Per-worker background task that reads messages from a Redis Stream.

    Delivery guarantees:
      - At-least-once: position is saved after every batch; a crash between
        delivery and save replays only that batch (client dedup handles this).
      - Failed messages go to dlq:{stream_name} instead of being silently
        dropped, giving ops full visibility.

    Reconnection:
      - Exponential backoff with jitter (prevents thundering herd on Redis restart).
      - Escalates to logger.error (→ Sentry) after 5 consecutive failures.
    """
    worker_id = str(os.getpid())
    pos_key = f"stream_pos:{stream_name}:{worker_id}"
    delay = 1.0
    consecutive_failures = 0

    while True:
        try:
            r = await get_redis()

            # On first-ever start use "$" (only new messages).
            # On restart use the saved position (deliver missed messages).
            saved = await r.get(pos_key)
            last_id: str = saved if saved else "$"

            logger.info(
                "[STREAM:%s] Dinleyici başladı | pid=%s pos=%s",
                stream_name, worker_id, last_id,
            )
            delay = 1.0
            consecutive_failures = 0

            while True:
                result = await r.xread({stream_name: last_id}, block=_BLOCK_MS, count=50)
                if not result:
                    continue  # timeout — no messages, loop (keepalive)

                for _, messages in result:
                    for msg_id, fields in messages:
                        raw_data = fields.get("data", "{}")
                        try:
                            data = json.loads(raw_data)
                            await on_message(data)
                        except Exception as exc:
                            # Do not re-raise — advance position so one bad
                            # message never blocks the rest of the stream.
                            await _write_dlq(r, stream_name, msg_id, raw_data, exc)
                        last_id = msg_id

                # Persist position after each batch — best-effort, non-fatal.
                # Failure here means a few messages may be reprocessed on the
                # next restart; client-side dedup (WsService._seenKeys) handles that.
                try:
                    await r.set(pos_key, last_id, ex=86400)
                except Exception:
                    pass

        except asyncio.CancelledError:
            return
        except Exception as exc:
            consecutive_failures += 1
            if consecutive_failures >= 5:
                logger.error(
                    "[STREAM:%s] %d ardışık bağlantı hatası: %s",
                    stream_name, consecutive_failures, exc,
                )
            else:
                logger.warning(
                    "[STREAM:%s] Bağlantı hatası, %.1fs sonra yeniden denenecek: %s",
                    stream_name, delay, exc,
                )

        jitter = random.uniform(0, delay * 0.3)
        await asyncio.sleep(delay + jitter)
        delay = min(delay * 2, _MAX_DELAY)
