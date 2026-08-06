"""
Direct Sale sold_out → ended geçişi için DB-polled periyodik scheduler.

Neden asyncio.create_task değil?
  Worker restart sırasında in-memory task'lar kaybolur. scheduled_end_at
  DB'de kalıcı olduğu için restart sonrası da doğru geçiş gerçekleşir.

Periyot: 10s — sold_out penceresi 5s, tolerans 5s, toplam max gecikme 10s.
Eşzamanlılık koruması: SELECT ... FOR UPDATE SKIP LOCKED — birden fazla
  worker aynı satışı işlemez.
"""
from __future__ import annotations
import asyncio
import logging
from datetime import datetime, timezone

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models.direct_sale import DirectSale
from app.core.logger import fire_and_forget
from app.use_cases.direct_sales import direct_sale_redis as redis_mgr
from app.constants import ws_types as WS

logger = logging.getLogger(__name__)

_POLL_INTERVAL_SECS = 10


async def direct_sale_scheduler() -> None:
    """
    Periyodik olarak scheduled_end_at süresi dolmuş sold_out satışları
    ended state'ine geçirir ve WS broadcast atar.
    """
    logger.info("[SCHEDULER] Direct sale scheduler başladı (interval=%ds)", _POLL_INTERVAL_SECS)
    while True:
        await asyncio.sleep(_POLL_INTERVAL_SECS)
        try:
            await _process_overdue_sales()
        except Exception as exc:
            logger.error("[SCHEDULER] İşlem döngüsü hatası: %s", exc, exc_info=True)


async def _process_overdue_sales() -> None:
    now = datetime.now(timezone.utc)
    async with AsyncSessionLocal() as session:
        # FOR UPDATE SKIP LOCKED: çok worker varsa aynı satışı iki kez işlemez
        result = await session.execute(
            select(DirectSale)
            .where(
                DirectSale.status == "sold_out",
                DirectSale.scheduled_end_at <= now,
            )
            .with_for_update(skip_locked=True)
        )
        sales = result.scalars().all()

        if not sales:
            return

        end_reason = "sold_out"
        for sale in sales:
            try:
                await redis_mgr.end_sale(sale.stream_id, end_reason)
                sale.status = "ended"
                sale.end_reason = end_reason
                sale.ended_at = now
                sale.scheduled_end_at = None
                logger.info("[SCHEDULER] sold_out → ended | sale_id=%s stream=%s",
                            sale.id, sale.stream_id)
            except Exception as exc:
                logger.error("[SCHEDULER] sale_id=%s Redis end_sale hatası: %s", sale.id, exc)

        await session.commit()

        # Commit sonrası WS broadcast (her satış için ayrı)
        for sale in sales:
            total_sold = sale.total_stock
            total_revenue = total_sold * float(sale.price)
            fire_and_forget(redis_mgr.publish_direct_sale(sale.stream_id, {
                "type": WS.DIRECT_SALE_ENDED,
                "sale_id": sale.id,
                "end_reason": end_reason,
                "total_sold": total_sold,
                "total_revenue": total_revenue,
            }))
