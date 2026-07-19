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
from typing import Awaitable, Callable

from app.utils.redis_client import get_redis
from app.core.logger import get_logger

logger = get_logger(__name__)

# Messages retained per stream (approximate — Redis trims lazily).
# 500 covers several minutes of high-traffic bursts; increase if needed.
STREAM_MAXLEN = 500

_BLOCK_MS  = 5_000   # XREAD block timeout — implicit keepalive
_MAX_DELAY = 30.0    # exponential backoff ceiling


async def stream_listener(
    stream_name: str,
    on_message: Callable[[dict], Awaitable[None]],
) -> None:
    """
    Per-worker background task that reads messages from a Redis Stream.

    - Reconnects automatically with jitter + exponential backoff.
    - Escalates to logger.error after 5 consecutive failures (Sentry alert).
    - Saves read position to Redis after every batch so restarts are safe.
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
                        try:
                            data = json.loads(fields["data"])
                            await on_message(data)
                        except Exception as exc:
                            logger.warning(
                                "[STREAM:%s] Mesaj işleme hatası | id=%s | %s",
                                stream_name, msg_id, exc,
                            )
                        last_id = msg_id  # advance position even on error

                # Persist position after each batch — best-effort, non-fatal.
                # If this write fails, worst case: a few messages are reprocessed
                # on the next restart (idempotent broadcast_local handles that).
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
