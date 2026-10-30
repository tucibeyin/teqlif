from fastapi import APIRouter, Depends, HTTPException, Path
from app.core.exceptions import NotFoundException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

import json
import logging
from app.database import get_db, get_uow
from app.core.uow import SqlAlchemyUnitOfWork
from app.models.user import User
from app.models.teqlik_transaction import TeqlikTransaction
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.models.gift_event import GiftEvent
from app.use_cases.chat.chat_utils import publish_chat
from app.utils.auth import get_current_user, invalidate_user_session_cache
from app.utils.redis_client import get_redis

logger = logging.getLogger("teqlif")
router = APIRouter(prefix="/api/wallet", tags=["wallet"])


# ── IAP satın alma ─────────────────────────────────────────────────────────────

class PurchaseVerifyRequest(BaseModel):
    platform: str = Field(..., pattern="^(apple|google|web)$")
    payload: str
    product_id: str
    device_id: str | None = None
    try_amount: float = 0.0


@router.post("/purchase/verify")
async def verify_purchase(
    body: PurchaseVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.verify_purchase_command import VerifyPurchaseCommand
    result = await VerifyPurchaseCommand(db).execute(
        user_id=current_user.id,
        platform=body.platform,
        payload=body.payload,
        product_id=body.product_id,
        device_id=body.device_id,
        try_amount=body.try_amount,
    )
    await db.commit()
    await invalidate_user_session_cache(current_user.id)
    return result


# ── App Store Server Notifications ────────────────────────────────────────────

class StoreNotificationRequest(BaseModel):
    signedPayload: str


@router.post("/store-notifications/{platform}", status_code=200)
async def store_notifications(
    body: StoreNotificationRequest,
    platform: str = Path(..., pattern="^(apple|google|web)$"),
):
    from app.use_cases.wallet.commands.handle_store_notification_command import HandleStoreNotificationCommand
    await HandleStoreNotificationCommand().execute(
        platform=platform,
        signed_payload=body.signedPayload,
    )
    return {"ok": True}

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


@router.get("/summary")
async def wallet_summary(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.queries.get_wallet_summary_query import GetWalletSummaryQuery
    return await GetWalletSummaryQuery(db).execute(current_user.id)


# ── Cashout (withdraw) ──────────────────────────────────────────────────────────

class WithdrawRequest(BaseModel):
    teqlik_amount: int = Field(gt=0)
    currency: str = Field(default="TRY", pattern="^[A-Z]{3}$")
    iban: str = Field(min_length=15, max_length=34)
    account_holder_name: str = Field(min_length=2, max_length=120)


@router.post("/withdraw")
async def request_withdrawal(
    body: WithdrawRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.request_withdrawal_command import RequestWithdrawalCommand
    result = await RequestWithdrawalCommand(db).execute(
        user_id=current_user.id,
        teqlik_amount=body.teqlik_amount,
        currency=body.currency,
        iban=body.iban,
        account_holder=body.account_holder_name,
    )
    await db.commit()
    return result


@router.delete("/withdraw/{request_id}")
async def cancel_withdrawal(
    request_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.cancel_withdrawal_request_command import CancelWithdrawalRequestCommand
    result = await CancelWithdrawalRequestCommand(db).execute(
        user_id=current_user.id,
        request_id=request_id,
    )
    await db.commit()
    return result


# ── Seçenek C — available → teqlik_balance (%10 bonus) ─────────────────────────

class ConvertToTeqlikRequest(BaseModel):
    teqlik_amount: int = Field(gt=0)


@router.post("/convert-to-teqlik")
async def convert_to_teqlik(
    body: ConvertToTeqlikRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.convert_to_teqlik_command import ConvertToTeqlikCommand
    result = await ConvertToTeqlikCommand(db).execute(
        user_id=current_user.id,
        teqlik_amount=body.teqlik_amount,
    )
    await db.commit()
    await invalidate_user_session_cache(current_user.id)
    return result


class TopupRequest(BaseModel):
    amount: int = Field(gt=0, le=10000)


class TransferRequest(BaseModel):
    recipient_id: int
    amount: int = Field(gt=0, le=10000)


class GiftRequest(BaseModel):
    stream_id: int
    receiver_username: str
    gift_name: str
    cost: int = Field(gt=0, le=1000)


def _txn_dict(t: TeqlikTransaction) -> dict:
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
        detail="PAYMENT_NOT_AVAILABLE",
    )


@router.get("/balance")
async def get_balance(
    limit: int = 5,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    limit = max(1, min(limit, 100))
    result = await db.execute(
        select(TeqlikTransaction)
        .where(TeqlikTransaction.user_id == current_user.id)
        .order_by(desc(TeqlikTransaction.created_at))
        .limit(limit)
    )
    txns = result.scalars().all()
    return {
        "balance": current_user.teqlik_balance,
        "transactions": [_txn_dict(t) for t in txns],
    }


@router.post("/transfer")
async def transfer_teqlik(
    data: TransferRequest,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    from app.use_cases.wallet.commands.transfer_teqlik import TransferTeqlikCommand

    result = await TransferTeqlikCommand(uow).execute(
        sender_id=current_user.id,
        receiver_id=data.recipient_id,
        amount=data.amount
    )
    await invalidate_user_session_cache(current_user.id)
    await invalidate_user_session_cache(data.recipient_id)
    return result


@router.get("/transaction/{txn_id}")
async def get_transaction_detail(
    txn_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    txn = await db.scalar(
        select(TeqlikTransaction).where(
            TeqlikTransaction.id == txn_id,
            TeqlikTransaction.user_id == current_user.id,
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
                "cost_teqlik": gift_ev.cost_teqlik,
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
    from app.use_cases.wallet.commands.send_gift_command import SendGiftCommand

    cmd = SendGiftCommand(db)
    result = await cmd.execute(
        sender_id=current_user.id,
        receiver_username=body.receiver_username,
        gift_name=body.gift_name,
        stream_id=body.stream_id,
    )

    # commit — transaction serbest bırakılır, ardından domain events
    await db.commit()

    # Post-commit domain events: commit SONRASI, transaction DIŞINDA
    try:
        await publish_chat(body.stream_id, {
            "type": "gift",
            "sender": current_user.username,
            "gift_name": body.gift_name,
            "cost": result["cost"],
            "gift_event_id": result["gift_event_id"],
        })
    except Exception as _ws_exc:
        logger.warning("[WALLET] WebSocket yayını başarısız | stream_id=%s | %s", body.stream_id, _ws_exc)

    try:
        from app.services.notification_service import push_notification
        from app.core.logger import fire_and_forget
        fire_and_forget(push_notification(
            result["receiver_id"],
            {
                "type": "gift_received",
                "sender_username": current_user.username,
                "gift_name": body.gift_name,
                "earned_teqlik": result["earned_teqlik"],
            },
            pref_key="gift_received",
        ))
    except Exception as _push_exc:
        logger.warning("[WALLET] Push notification başarısız | %s", _push_exc)

    # Redis gift log (son 200 hediye, 24s TTL)
    try:
        redis = await get_redis()
        key = f"gift:log:{body.stream_id}"
        log_payload = json.dumps({
            "gift_event_id": result["gift_event_id"],
            "gift_name": body.gift_name,
            "cost_teqlik": result["cost"],
            "host_share": result["earned_teqlik"],
            "sender": current_user.username,
        })
        await redis.lpush(key, log_payload)
        await redis.ltrim(key, 0, 199)
        await redis.expire(key, 86400)
    except Exception as _redis_exc:
        logger.warning("[WALLET] Gift log Redis yazılamadı | stream_id=%s | %s", body.stream_id, _redis_exc)

    await invalidate_user_session_cache(current_user.id)
    await db.refresh(current_user)
    return {"ok": True, "new_balance": current_user.teqlik_balance}
