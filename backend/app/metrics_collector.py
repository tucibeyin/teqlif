"""
Custom Prometheus metrikleri: ARQ kuyruk derinliği + iş metrikleri.

Her 30 saniyede bir Redis ve DB'den toplanır; /metrics endpoint'i üzerinden sunulur.
prometheus_client Gauge'ları uygulama başladığında bir kez register edilir.

ARQ kuyrukları: default, critical, video (Redis sorted set, ZCARD ile derinlik)
İş metrikleri:  aktif canlı yayın ve açık artırma sayıları (PostgreSQL)
"""
import asyncio
from contextlib import asynccontextmanager
from typing import AsyncIterator

from prometheus_client import Gauge
from sqlalchemy import func, select

from app.core.logger import get_logger
from app.database import AsyncSessionLocal

logger = get_logger(__name__)

_COLLECT_INTERVAL = 30  # saniye

# ── Gauge tanımlamaları (modül yüklenince bir kez register edilir) ─────────────

arq_queue_depth = Gauge(
    "arq_queue_depth",
    "ARQ kuyruğundaki bekleyen iş sayısı",
    ["queue"],
)

active_streams_gauge = Gauge(
    "teqlif_active_streams_total",
    "Şu anda yayında olan canlı yayın sayısı",
)

active_auctions_gauge = Gauge(
    "teqlif_active_auctions_total",
    "Şu anda aktif olan açık artırma sayısı",
)

_ARQ_QUEUES = ("default", "critical", "video")


# ── Redis bağlantısı ──────────────────────────────────────────────────────────

@asynccontextmanager
async def _redis_client() -> AsyncIterator:
    import redis.asyncio as aioredis
    from app.config import settings

    client = aioredis.from_url(settings.redis_url, decode_responses=True)
    try:
        yield client
    finally:
        await client.aclose()


# ── Koleksiyon fonksiyonları ──────────────────────────────────────────────────

async def _collect_arq() -> None:
    async with _redis_client() as client:
        for queue in _ARQ_QUEUES:
            depth = await client.zcard(queue)
            arq_queue_depth.labels(queue=queue).set(depth)


async def _collect_business() -> None:
    from app.models.auction import Auction
    from app.models.stream import LiveStream

    async with AsyncSessionLocal() as db:
        active_streams = await db.scalar(
            select(func.count()).where(LiveStream.is_live == True)  # noqa: E712
        ) or 0
        active_auctions = await db.scalar(
            select(func.count()).where(Auction.status == "active")
        ) or 0

    active_streams_gauge.set(active_streams)
    active_auctions_gauge.set(active_auctions)


async def _collect_once() -> None:
    """Tüm metrikleri bir tur topla; her hata kendi başına yutulur."""
    try:
        await _collect_arq()
    except Exception as exc:
        logger.warning("[metrics] ARQ kuyruk derinliği toplanamadı: %s", exc)

    try:
        await _collect_business()
    except Exception as exc:
        logger.warning("[metrics] İş metrikleri toplanamadı: %s", exc)


# ── Arka plan döngüsü ─────────────────────────────────────────────────────────

async def metrics_collector_loop() -> None:
    """
    Prometheus metriklerini periyodik olarak toplar.
    main.py lifespan'ında asyncio.create_task ile başlatılır.
    İlk toplama startup'ta hemen yapılır, ardından _COLLECT_INTERVAL'de tekrar edilir.
    """
    while True:
        await _collect_once()
        await asyncio.sleep(_COLLECT_INTERVAL)
