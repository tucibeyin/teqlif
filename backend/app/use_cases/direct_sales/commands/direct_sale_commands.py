"""
Direct Sale iş mantığı — Clean Command Pattern.
Router sadece bu fonksiyonları çağırır; tüm DB/Redis/WS işlemleri burada.
"""
from __future__ import annotations
import logging
from typing import Optional, List

from sqlalchemy import select, func
from sqlalchemy.orm import aliased
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.stream import LiveStream
from app.models.listing import Listing
from app.models.direct_sale import DirectSale, DirectSaleOrder
from app.models.message import DirectMessage
from app.schemas.direct_sale import (
    DirectSaleStartIn, DirectSalePurchaseIn, DirectSaleCancelIn,
    DirectSaleStateOut, DirectSaleOrderOut, DirectSaleSummaryOut,
)
from app.core.exceptions import (
    NotFoundException, ForbiddenException,
    DirectSaleNotFoundException, DirectSaleNotActiveException,
    DirectSaleAlreadyActiveException, DirectSaleInsufficientStockException,
)
from app.core.logger import fire_and_forget
from app.core.uow import SqlAlchemyUnitOfWork
from app.core.ws_manager import ws_manager
from app.use_cases.direct_sales import direct_sale_redis as redis_mgr
from app.constants import ws_types as WS

_DM_CHANNEL = "dm_broadcast"

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

    if sale.status not in ("active", "paused", "sold_out"):
        raise DirectSaleNotActiveException()

    from datetime import datetime, timezone
    end_reason = "host_ended"

    await redis_mgr.end_sale(sale.stream_id, end_reason)
    sale.status = "ended"
    sale.end_reason = end_reason
    sale.ended_at = datetime.now(timezone.utc)
    sale.scheduled_end_at = None  # scheduler artık işleme almayacak
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


# ── POST /direct-sales/{id}/purchase ─────────────────────────────────────────

def _build_purchase_dm(title: str, listing_id: Optional[int],
                       sale_id: int, quantity: int,
                       unit_price: float) -> str:
    total = quantity * unit_price

    def fmt(v: float) -> str:
        return f"{v:,.0f} TL".replace(",", ".")

    price_line = fmt(total)
    if quantity > 1:
        price_line += f" ({quantity} adet × {fmt(unit_price)})"

    dm = (
        f"🛍️ Satın alma tamamlandı! Tebrikler!\n"
        f"📦 Ürün: {title}\n"
        f"💰 Fiyat: {price_line}"
    )
    if listing_id:
        dm += f"\n🔗 teqlif://listing/{listing_id}"
    dm += f"\n📋 teqlif://direct-sale/{sale_id}"
    return dm


async def purchase_sale(sale_id: int, data: DirectSalePurchaseIn,
                        user: User, uow: SqlAlchemyUnitOfWork) -> dict:
    sale = await _get_sale(sale_id, uow.session)

    if sale.status != "active":
        raise DirectSaleNotActiveException()

    # Lua atomik stok azaltma
    remaining = await redis_mgr.decrement_stock(sale.stream_id, data.quantity)

    if remaining == -1:
        # Redis key yok — nadir race, satışı aktif sayma
        raise DirectSaleNotActiveException()
    if remaining == -2:
        raise DirectSaleInsufficientStockException()

    # remaining >= 0: başarılı

    from datetime import datetime, timezone, timedelta
    unit_price = float(sale.price)
    stream_id = sale.stream_id

    # DB: order oluştur, satış stoğunu güncelle
    order = DirectSaleOrder(
        sale_id=sale_id,
        seller_id=sale.host_id,
        buyer_id=user.id,
        listing_id=sale.listing_id,
        quantity=data.quantity,
        unit_price=unit_price,
        status="completed",
    )
    uow.session.add(order)
    sale.remaining_stock = remaining
    if remaining == 0:
        sale.status = "sold_out"
        # Scheduler 5 sn sonra ended'a geçirecek — DB'ye yazıyoruz (durable)
        sale.scheduled_end_at = datetime.now(timezone.utc) + timedelta(seconds=5)

    # DM: host → buyer (aynı commit'te)
    dm_content = _build_purchase_dm(
        title=sale.title,
        listing_id=sale.listing_id,
        sale_id=sale_id,
        quantity=data.quantity,
        unit_price=unit_price,
    )
    dm = DirectMessage(
        sender_id=sale.host_id,
        receiver_id=user.id,
        content=dm_content,
    )
    uow.session.add(dm)

    await uow.session.flush()  # order.id + dm.id alınır

    # Redis hash sync
    await redis_mgr.update_remaining_stock(stream_id, remaining)
    if remaining == 0:
        await redis_mgr.set_sold_out(stream_id)

    await uow.session.commit()

    # Stream WS: direct_sale_purchased
    fire_and_forget(redis_mgr.publish_direct_sale(stream_id, {
        "type": WS.DIRECT_SALE_PURCHASED,
        "sale_id": sale_id,
        "buyer_username": user.username,
        "quantity": data.quantity,
        "remaining_stock": remaining,
    }))

    if remaining == 0:
        fire_and_forget(redis_mgr.publish_direct_sale(stream_id, {
            "type": WS.DIRECT_SALE_SOLD_OUT,
            "sale_id": sale_id,
        }))

    # DM WS broadcast (buyer + host her ikisine)
    from datetime import datetime, timezone as _tz
    dm_payload = {
        "type": "message",
        "id": dm.id,
        "sender_id": sale.host_id,
        "receiver_id": user.id,
        "sender_username": user.username,
        "content": dm_content,
        "is_read": False,
        "created_at": datetime.now(_tz.utc).isoformat(),
    }
    fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{user.id}", dm_payload))
    fire_and_forget(ws_manager.publish(_DM_CHANNEL, f"dm:{sale.host_id}", dm_payload))

    # Push notification → buyer
    try:
        from app.services.notification_service import push_notification
        fire_and_forget(push_notification(
            user.id,
            {
                "type": "direct_sale_purchased",
                "i18n": {
                    "title_key": "notifDirectSalePurchased",
                    "body_key": "notifDirectSalePurchasedBody",
                    "body_params": {"item": sale.title, "price": f"{unit_price:.0f} TL"},
                },
                "sale_id": sale_id,
            },
            pref_key="direct_sale_purchased",
        ))
    except Exception as exc:
        logger.warning("[SATIN ALMA] push_notification başarısız | buyer=%s | %s", user.id, exc)

    logger.info("[SATIN ALMA] | sale_id=%s buyer=%s qty=%s remaining=%s",
                sale_id, user.id, data.quantity, remaining)

    return {
        "order_id": order.id,
        "sale_id": sale_id,
        "quantity": data.quantity,
        "unit_price": unit_price,
        "total_price": data.quantity * unit_price,
        "remaining_stock": remaining,
    }


# ── GET /direct-sales/{id}/summary ───────────────────────────────────────────

async def get_sale_summary(sale_id: int, user: User,
                           session: AsyncSession) -> DirectSaleSummaryOut:
    sale = await _get_sale(sale_id, session)

    if user.id == sale.host_id:
        # Satıcı görünümü — tüm tamamlanan order'ları topla
        row = await session.execute(
            select(
                func.coalesce(func.sum(DirectSaleOrder.quantity), 0).label("total_qty"),
                func.count(DirectSaleOrder.id).label("order_count"),
                func.coalesce(
                    func.sum(DirectSaleOrder.quantity * DirectSaleOrder.unit_price), 0
                ).label("total_revenue"),
            ).where(
                DirectSaleOrder.sale_id == sale_id,
                DirectSaleOrder.status == "completed",
            )
        )
        agg = row.one()
        return DirectSaleSummaryOut(
            role="seller",
            sale_id=sale_id,
            item_name=sale.title,
            proof_image_url=sale.proof_image_url,
            image_url=sale.product_image_url,
            status=sale.status,
            end_reason=sale.end_reason,
            ended_at=sale.ended_at,
            total_revenue=float(agg.total_revenue),
            total_quantity_sold=int(agg.total_qty),
            order_count=int(agg.order_count),
        )
    else:
        # Alıcı görünümü — bu kullanıcının order'larını topla
        row = await session.execute(
            select(
                func.coalesce(func.sum(DirectSaleOrder.quantity), 0).label("total_qty"),
                func.coalesce(
                    func.sum(DirectSaleOrder.quantity * DirectSaleOrder.unit_price), 0
                ).label("total_price"),
                func.min(DirectSaleOrder.unit_price).label("unit_price"),
                func.max(DirectSaleOrder.status).label("order_status"),
            ).where(
                DirectSaleOrder.sale_id == sale_id,
                DirectSaleOrder.buyer_id == user.id,
            )
        )
        agg = row.one()

        # Satıcı username'i al
        seller = await session.scalar(select(User).where(User.id == sale.host_id))

        return DirectSaleSummaryOut(
            role="buyer",
            sale_id=sale_id,
            item_name=sale.title,
            proof_image_url=sale.proof_image_url,
            image_url=sale.product_image_url,
            status=sale.status,
            end_reason=sale.end_reason,
            ended_at=sale.ended_at,
            seller_username=seller.username if seller else None,
            buyer_quantity=int(agg.total_qty),
            buyer_unit_price=float(agg.unit_price) if agg.unit_price else float(sale.price),
            buyer_total=float(agg.total_price),
            buyer_order_status=agg.order_status,
        )


# ── GET /direct-sales/{id}/orders ────────────────────────────────────────────

async def get_sale_orders(sale_id: int, user: User,
                          session: AsyncSession) -> List[DirectSaleOrderOut]:
    sale = await _get_sale(sale_id, session)
    if sale.host_id != user.id:
        raise ForbiddenException(code="HOST_REQUIRED")

    BuyerUser = aliased(User)
    rows = await session.execute(
        select(
            DirectSaleOrder.id,
            BuyerUser.username.label("buyer_username"),
            DirectSaleOrder.quantity,
            DirectSaleOrder.unit_price,
            (DirectSaleOrder.quantity * DirectSaleOrder.unit_price).label("total_price"),
            DirectSaleOrder.status,
            DirectSaleOrder.created_at,
        )
        .join(BuyerUser, BuyerUser.id == DirectSaleOrder.buyer_id)
        .where(DirectSaleOrder.sale_id == sale_id)
        .order_by(DirectSaleOrder.created_at.asc())
    )

    return [
        DirectSaleOrderOut(
            id=r.id,
            buyer_username=r.buyer_username,
            quantity=r.quantity,
            unit_price=float(r.unit_price),
            total_price=float(r.total_price),
            status=r.status,
            created_at=r.created_at,
        )
        for r in rows.all()
    ]
