from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, text as sql_text

from app.database import get_db
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.models.listing import Listing
from app.models.stream import LiveStream
from app.services.chat_service import publish_chat
from app.utils.auth import get_current_user

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
        raise HTTPException(status_code=404, detail="İşlem bulunamadı.")

    detail = _txn_dict(txn)

    if txn.reference_type == "listing" and txn.reference_id:
        listing = await db.scalar(select(Listing).where(Listing.id == txn.reference_id))
        if listing:
            detail["listing"] = {
                "id": listing.id,
                "title": listing.title,
                "category": listing.category,
                "price": listing.price,
                "image_url": listing.image_url,
                "is_active": listing.is_active,
            }

    elif txn.reference_type == "stream" and txn.reference_id:
        stream = await db.scalar(select(LiveStream).where(LiveStream.id == txn.reference_id))
        if stream:
            detail["stream"] = {
                "id": stream.id,
                "title": stream.title,
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
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı.")
    if receiver.id == current_user.id:
        raise HTTPException(status_code=400, detail="Kendinize hediye gönderemezsiniz.")

    if current_user.tuci_balance < body.cost:
        raise HTTPException(
            status_code=402,
            detail=f"Yetersiz TUCi bakiyesi. Mevcut: {current_user.tuci_balance} TUCi, Gerekli: {body.cost} TUCi",
        )

    # Platform komisyonu: Pro yayıncı %95, Standart %70 alır
    commission_rate = 0.95 if receiver.is_premium else 0.70
    host_share = int(body.cost * commission_rate)

    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance - :cost WHERE id = :uid"),
        {"cost": body.cost, "uid": current_user.id},
    )
    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance + :share WHERE id = :uid"),
        {"share": host_share, "uid": receiver.id},
    )
    db.add(TuciTransaction(user_id=current_user.id, amount=-body.cost,  transaction_type="send_gift",    reference_id=body.stream_id, reference_type="stream"))
    db.add(TuciTransaction(user_id=receiver.id,    amount=host_share,   transaction_type="receive_gift", reference_id=body.stream_id, reference_type="stream"))
    await db.commit()

    await publish_chat(body.stream_id, {
        "type": "gift",
        "sender": current_user.username,
        "gift_name": body.gift_name,
        "cost": body.cost,
    })

    await db.refresh(current_user)
    return {"ok": True, "new_balance": current_user.tuci_balance}
