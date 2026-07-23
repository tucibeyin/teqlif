from fastapi import APIRouter, Depends, HTTPException
from app.core.exceptions import NotFoundException, BadRequestException, InsufficientFundsException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, text as sql_text

import json
import logging
from app.models.enums import ListingStatus
from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.gift_event import GiftEvent
from app.use_cases.chat.chat_utils import publish_chat
from app.utils.auth import get_current_user
from app.utils.redis_client import get_redis

logger = logging.getLogger("teqlif")
router = APIRouter(prefix="/api/wallet", tags=["wallet"])

_TYPE_LABELS = {
    "airdrop":            "Hoş geldin hediyesi",
    "spend_lead_gen":     "Sıcak Talep bildirimi",
    "spend_ad_campaign":  "İlan sponsorluğu",
    "spend_ai":           "Yapay Zeka fiyatlama",
    "web_topup":          "Web yükleme",
    "send_gift":          "Canlı hediye gönderildi",
    "receive_gift":       "Canlı hediye alındı",
    "referral_bonus":     "Davet ödülü",
    "welcome_bonus":      "Davet kodu bonusu",
    "spend_retargeting":  "Retargeting bildirimi",
    "spend_boost":        "Öne çıkarma",
    "spend_boost_paid":   "Öne çıkarma (ücretli)",
    "spend_reactivation": "Yeniden yayına alma",
}


class TopupRequest(BaseModel):
    amount: int = Field(gt=0, le=10000)


class GiftRequest(BaseModel):
    stream_id: int
    receiver_username: str
    gift_name: str
    cost: int = Field(gt=0, le=1000)


def _txn_dict(t: TuciTransaction) -> dict:
    return {
        "id": t.id,
        "amount": t.amount,
        "transaction_type": t.transaction_type,
        "label": _TYPE_LABELS.get(t.transaction_type, t.transaction_type),
        "created_at": t.created_at.isoformat(),
        "reference_id": t.reference_id,
        "reference_type": t.reference_type,
    }


@router.post("/topup-manual", status_code=503)
async def topup_manual(
    body: TopupRequest,
    current_user: User = Depends(get_current_user),
):
    raise HTTPException(
        status_code=503,
        detail="Ödeme altyapısı henüz aktif değil. Tüm kullanıcılara başlangıç bakiyesi tanımlandı, yakında satın alma özelliği eklenecek.",
    )


@router.get("/balance")
async def get_balance(
    limit: int = 5,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    limit = max(1, min(limit, 100))
    result = await db.execute(
        select(TuciTransaction)
        .where(TuciTransaction.user_id == current_user.id)
        .order_by(desc(TuciTransaction.created_at))
        .limit(limit)
    )
    txns = result.scalars().all()
    return {
        "balance": current_user.tuci_balance,
        "transactions": [_txn_dict(t) for t in txns],
    }


@router.post("/transfer")
async def transfer_tuci(
    data: dict,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    from app.use_cases.wallet.commands.transfer_tuci import TransferTuciCommand

    recipient_id = data.get("recipient_id")
    amount = data.get("amount")
    return await TransferTuciCommand(uow).execute(
        sender_id=current_user.id,
        receiver_id=recipient_id,
        amount=amount
    )


@router.get("/transaction/{txn_id}")
async def get_transaction_detail(
    txn_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    txn = await db.scalar(
        select(TuciTransaction).where(
            TuciTransaction.id == txn_id,
            TuciTransaction.user_id == current_user.id,
        )
    )
    if txn is None:
        raise NotFoundException()

    detail = _txn_dict(txn)

    if txn.reference_type == "listing" and txn.reference_id:
        listing = await db.scalar(select(Listing).where(Listing.id == txn.reference_id))
        if listing:
            owner = await db.scalar(select(User).where(User.id == listing.user_id))
            detail["listing"] = {
                "id": listing.id,
                "title": listing.title,
                "category": listing.category,
                "price": listing.price,
                "image_url": listing.image_url,
                "status": listing.status.value if hasattr(listing.status, 'value') else str(listing.status),
                "owner_id": listing.user_id,
                "owner_username": owner.username if owner else None,
                "owner_avatar": owner.profile_image_thumb_url if owner else None,
            }

    elif txn.reference_type == "stream" and txn.reference_id:
        stream = await db.scalar(select(LiveStream).where(LiveStream.id == txn.reference_id))
        if stream:
            host = await db.scalar(select(User).where(User.id == stream.host_id))
            detail["stream"] = {
                "id": stream.id,
                "title": stream.title,
                "host_id": stream.host_id,
                "host_username": host.username if host else None,
                "host_avatar": host.profile_image_thumb_url if host else None,
            }

    elif txn.reference_type == "gift_event" and txn.reference_id:
        gift_ev = await db.scalar(select(GiftEvent).where(GiftEvent.id == txn.reference_id))
        if gift_ev:
            sender   = await db.scalar(select(User).where(User.id == gift_ev.sender_id))
            receiver = await db.scalar(select(User).where(User.id == gift_ev.receiver_id))
            stream   = await db.scalar(select(LiveStream).where(LiveStream.id == gift_ev.stream_id))
            detail["gift_event"] = {
                "id": gift_ev.id,
                "gift_name": gift_ev.gift_name,
                "cost_tuci": gift_ev.cost_tuci,
                "host_share": gift_ev.host_share,
                "sent_at": gift_ev.sent_at.isoformat(),
                "sender": {
                    "id": gift_ev.sender_id,
                    "username": sender.username if sender else None,
                    "avatar": sender.profile_image_thumb_url if sender else None,
                },
                "receiver": {
                    "id": gift_ev.receiver_id,
                    "username": receiver.username if receiver else None,
                    "avatar": receiver.profile_image_thumb_url if receiver else None,
                },
                "stream": {
                    "id": gift_ev.stream_id,
                    "title": stream.title if stream else None,
                },
            }

    return detail


@router.post("/send-gift")
async def send_gift(
    body: GiftRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(User).where(User.username == body.receiver_username))
    receiver = result.scalar_one_or_none()
    if receiver is None:
        raise NotFoundException()
    if receiver.id == current_user.id:
        raise BadRequestException()

    # Platform komisyonu: Pro yayıncı %95, Standart %70 alır
    commission_rate = 0.95 if receiver.is_premium else 0.70
    host_share = int(body.cost * commission_rate)

    # 1) Atomik bakiye düşüşü — tek SQL ile kontrol + güncelleme.
    # WHERE tuci_balance >= cost koşulu olmazsa iki eş zamanlı istek session
    # cache'deki aynı bakiyeyi okuyup ikisi de geçer ve bakiye eksi olur.
    deduct = await db.execute(
        sql_text(
            "UPDATE users SET tuci_balance = tuci_balance - :cost "
            "WHERE id = :uid AND tuci_balance >= :cost "
            "RETURNING tuci_balance"
        ),
        {"cost": body.cost, "uid": current_user.id},
    )
    if deduct.fetchone() is None:
        logger.warning("TUCi transaction failed: insufficient balance", extra={
            "user_id": current_user.id, "required": body.cost,
        })
        raise InsufficientFundsException()

    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance + :share WHERE id = :uid"),
        {"share": host_share, "uid": receiver.id},
    )

    # 2) GiftEvent kaydı — tam audit trail
    gift_ev = GiftEvent(
        stream_id=body.stream_id,
        sender_id=current_user.id,
        receiver_id=receiver.id,
        gift_name=body.gift_name,
        cost_tuci=body.cost,
        host_share=host_share,
    )
    db.add(gift_ev)
    await db.flush()  # gift_ev.id'yi al

    # 3) Her iki TuciTransaction aynı GiftEvent'e işaret eder
    db.add(TuciTransaction(
        user_id=current_user.id, amount=-body.cost,
        transaction_type="send_gift",
        reference_id=gift_ev.id, reference_type="gift_event",
    ))
    db.add(TuciTransaction(
        user_id=receiver.id, amount=host_share,
        transaction_type="receive_gift",
        reference_id=gift_ev.id, reference_type="gift_event",
    ))

    logger.info("TUCi transaction: send_gift", extra={
        "sender_id": current_user.id,
        "receiver_id": receiver.id,
        "amount": body.cost,
        "gift_name": body.gift_name
    })
    
    await db.commit()

    # 4) WebSocket: anlık animasyon
    await publish_chat(body.stream_id, {
        "type": "gift",
        "sender": current_user.username,
        "gift_name": body.gift_name,
        "cost": body.cost,
    })

    # 5) Redis event log: son 200 hediye, 24s TTL
    try:
        redis = await get_redis()
        key = f"gift:log:{body.stream_id}"
        payload = json.dumps({
            "gift_event_id": gift_ev.id,
            "gift_name": body.gift_name,
            "cost_tuci": body.cost,
            "host_share": host_share,
            "sender": current_user.username,
            "receiver": receiver.username,
            "ts": gift_ev.sent_at.isoformat() if gift_ev.sent_at else None,
        })
        await redis.lpush(key, payload)
        await redis.ltrim(key, 0, 199)
        await redis.expire(key, 86400)
    except Exception as _redis_exc:
        logger.warning("[WALLET] Gift log Redis yazılamadı | stream_id=%s | %s", body.stream_id, _redis_exc)

    await db.refresh(current_user)
    return {"ok": True, "new_balance": current_user.tuci_balance}
