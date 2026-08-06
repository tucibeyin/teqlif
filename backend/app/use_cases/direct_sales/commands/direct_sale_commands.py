"""
Direct Sale iş mantığı — Clean Command Pattern.
Router sadece bu fonksiyonları çağırır; tüm DB/Redis/WS işlemleri burada.
"""
from __future__ import annotations
import logging
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.stream import LiveStream
from app.models.listing import Listing
from app.models.direct_sale import DirectSale, DirectSaleOrder
from app.schemas.direct_sale import (
    DirectSaleStartIn, DirectSalePurchaseIn, DirectSaleCancelIn,
    DirectSaleStateOut, DirectSaleOrderOut,
)
from app.core.exceptions import (
    NotFoundException, ForbiddenException,
    DirectSaleNotFoundException, DirectSaleNotActiveException,
    DirectSaleAlreadyActiveException,
)
from app.core.logger import fire_and_forget
from app.core.uow import SqlAlchemyUnitOfWork
from app.use_cases.direct_sales import direct_sale_redis as redis_mgr
from app.constants import ws_types as WS

logger = logging.getLogger(__name__)


# ── Yardımcılar ───────────────────────────────────────────────────────────────

async def _require_host(stream_id: int, user: User, session: AsyncSession) -> LiveStream:
    stream = await session.scalar(select(LiveStream).where(LiveStream.id == stream_id))
    if not stream:
        raise NotFoundException(code="STREAM_NOT_FOUND")
    if stream.host_id != user.id:
        raise ForbiddenException(code="HOST_REQUIRED")
    if not stream.is_live:
        raise ForbiddenException(code="STREAM_NOT_LIVE")
    return stream


async def _get_sale(sale_id: int, session: AsyncSession) -> DirectSale:
    sale = await session.scalar(select(DirectSale).where(DirectSale.id == sale_id))
    if not sale:
        raise DirectSaleNotFoundException()
    return sale


# ── POST /direct-sales/start ─────────────────────────────────────────────────

async def start_sale(stream_id: int, data: DirectSaleStartIn,
                     user: User, uow: SqlAlchemyUnitOfWork) -> dict:
    stream = await _require_host(stream_id, user, uow.session)

    # Aynı stream'de aktif/paused satış var mı?
    existing = await uow.session.scalar(
        select(DirectSale).where(
            DirectSale.stream_id == stream_id,
            DirectSale.status.in_(["active", "paused"]),
        )
    )
    if existing:
        raise DirectSaleAlreadyActiveException()

    # Listing'den veri al (listing seçilmişse)
    title = data.title
    product_image_url: Optional[str] = None
    category: Optional[str] = None

    if data.listing_id:
        listing = await uow.session.scalar(
            select(Listing).where(Listing.id == data.listing_id)
        )
        if listing:
            title = data.title or listing.title
            product_image_url = listing.image_url
            category = listing.category

    # title boş gelememeli (model_validator bunu zaten yakalar ama savunma)
    if not title:
        title = "Ürün"

    # DB kaydı oluştur
    sale = DirectSale(
        stream_id=stream_id,
        host_id=user.id,
        listing_id=data.listing_id,
        title=title,
        price=float(data.price),
        product_image_url=product_image_url,
        proof_image_url=data.proof_image_url,
        total_stock=data.stock_quantity,
        remaining_stock=data.stock_quantity,
        status="active",
        viewer_count_at_start=stream.viewer_count,
        category=category,
    )
    uow.session.add(sale)
    await uow.session.flush()   # sale.id alınır

    # Redis state yükle
    await redis_mgr.start_sale(
        stream_id=stream_id,
        sale_id=sale.id,
        title=title,
        price=float(data.price),
        total_stock=data.stock_quantity,
        product_image_url=product_image_url,
        proof_image_url=data.proof_image_url,
    )

    await uow.session.commit()

    payload = {
        "type": WS.DIRECT_SALE_STARTED,
        "sale_id": sale.id,
        "title": title,
        "price": float(data.price),
        "total_stock": data.stock_quantity,
        "remaining_stock": data.stock_quantity,
        "product_image_url": product_image_url,
        "proof_image_url": data.proof_image_url,
    }
    fire_and_forget(redis_mgr.publish_direct_sale(stream_id, payload))

    logger.info("[DIREKT SATIŞ] BAŞLADI | stream=%s sale_id=%s title=%r price=%s stock=%s",
                stream_id, sale.id, title, data.price, data.stock_quantity)
    return payload


# ── POST /direct-sales/{id}/pause ────────────────────────────────────────────

async def pause_sale(sale_id: int, user: User, uow: SqlAlchemyUnitOfWork) -> None:
    sale = await _get_sale(sale_id, uow.session)
    await _require_host(sale.stream_id, user, uow.session)

    if sale.status != "active":
        raise DirectSaleNotActiveException()

    await redis_mgr.pause_sale(sale.stream_id)
    sale.status = "paused"
    await uow.session.commit()

    fire_and_forget(redis_mgr.publish_direct_sale(sale.stream_id, {
        "type": WS.DIRECT_SALE_PAUSED,
        "sale_id": sale_id,
    }))
    logger.info("[DIREKT SATIŞ] DURAKLADI | sale_id=%s stream=%s", sale_id, sale.stream_id)


# ── POST /direct-sales/{id}/resume ───────────────────────────────────────────

async def resume_sale(sale_id: int, user: User, uow: SqlAlchemyUnitOfWork) -> None:
    sale = await _get_sale(sale_id, uow.session)
    await _require_host(sale.stream_id, user, uow.session)

    if sale.status != "paused":
        raise DirectSaleNotActiveException()

    await redis_mgr.resume_sale(sale.stream_id)
    sale.status = "active"
    await uow.session.commit()

    # Resume'de kalan stoğu da gönder
    remaining = sale.remaining_stock
    fire_and_forget(redis_mgr.publish_direct_sale(sale.stream_id, {
        "type": WS.DIRECT_SALE_RESUMED,
        "sale_id": sale_id,
        "remaining_stock": remaining,
    }))
    logger.info("[DIREKT SATIŞ] DEVAM ETTİ | sale_id=%s stream=%s", sale_id, sale.stream_id)


# ── POST /direct-sales/{id}/end ──────────────────────────────────────────────

async def end_sale(sale_id: int, user: User, uow: SqlAlchemyUnitOfWork) -> None:
    sale = await _get_sale(sale_id, uow.session)
    await _require_host(sale.stream_id, user, uow.session)

    if sale.status not in ("active", "paused"):
        raise DirectSaleNotActiveException()

    from datetime import datetime, timezone
    end_reason = "host_ended"

    await redis_mgr.end_sale(sale.stream_id, end_reason)
    sale.status = "ended"
    sale.end_reason = end_reason
    sale.ended_at = datetime.now(timezone.utc)
    await uow.session.commit()

    # Toplam satış özeti
    total_sold = sale.total_stock - sale.remaining_stock
    total_revenue = total_sold * float(sale.price)

    fire_and_forget(redis_mgr.publish_direct_sale(sale.stream_id, {
        "type": WS.DIRECT_SALE_ENDED,
        "sale_id": sale_id,
        "end_reason": end_reason,
        "total_sold": total_sold,
        "total_revenue": total_revenue,
    }))
    logger.info("[DIREKT SATIŞ] BİTTİ | sale_id=%s end_reason=%s total_sold=%s",
                sale_id, end_reason, total_sold)


# ── POST /direct-sales/{id}/cancel ───────────────────────────────────────────

async def cancel_sale(sale_id: int, data: DirectSaleCancelIn,
                      user: User, uow: SqlAlchemyUnitOfWork) -> None:
    sale = await _get_sale(sale_id, uow.session)
    await _require_host(sale.stream_id, user, uow.session)

    if sale.status not in ("active", "paused"):
        raise DirectSaleNotActiveException()

    from datetime import datetime, timezone

    await redis_mgr.cancel_sale(sale.stream_id)
    sale.status = "cancelled"
    sale.orders_voided = data.orders_voided
    sale.ended_at = datetime.now(timezone.utc)

    # Sipariş iptali isteniyorsa tüm order'ları cancelled yap
    if data.orders_voided:
        orders = await uow.session.scalars(
            select(DirectSaleOrder).where(
                DirectSaleOrder.sale_id == sale_id,
                DirectSaleOrder.status == "completed",
            )
        )
        for order in orders.all():
            order.status = "cancelled"

    await uow.session.commit()

    fire_and_forget(redis_mgr.publish_direct_sale(sale.stream_id, {
        "type": WS.DIRECT_SALE_CANCELLED,
        "sale_id": sale_id,
        "orders_voided": data.orders_voided,
    }))
    logger.info("[DIREKT SATIŞ] İPTAL | sale_id=%s orders_voided=%s", sale_id, data.orders_voided)


# ── GET /direct-sales/{stream_id}/state ──────────────────────────────────────

async def get_sale_state(stream_id: int) -> DirectSaleStateOut:
    state = await redis_mgr.get_state(stream_id)
    if not state:
        return DirectSaleStateOut(
            status="idle",
            sale_id=0,
            title="",
            price=0.0,
            total_stock=0,
            remaining_stock=0,
        )
    return DirectSaleStateOut(**state)
