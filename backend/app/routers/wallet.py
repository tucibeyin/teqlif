from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, text as sql_text

from app.database import get_db
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.utils.auth import get_current_user

router = APIRouter(prefix="/api/wallet", tags=["wallet"])

_TYPE_LABELS = {
    "airdrop":        "Hoş geldin hediyesi",
    "spend_lead_gen": "Sıcak Talep blast",
    "spend_ai":       "Yapay Zeka fiyatlama",
    "web_topup":      "Web yükleme",
}


class TopupRequest(BaseModel):
    amount: int = Field(gt=0, le=10000)


@router.post("/topup-manual", status_code=200)
async def topup_manual(
    body: TopupRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Kullanıcının kendi hesabına TUCi yükler (web paneli üzerinden).
    Admin ise herhangi bir kullanıcıya yükleyebilir — şimdilik kendi hesabına.
    """
    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance + :amt WHERE id = :uid"),
        {"amt": body.amount, "uid": current_user.id},
    )
    db.add(TuciTransaction(
        user_id=current_user.id,
        amount=body.amount,
        transaction_type="web_topup",
    ))
    await db.commit()

    # Güncel bakiyeyi döndür
    refreshed = await db.execute(
        sql_text("SELECT tuci_balance FROM users WHERE id = :uid"),
        {"uid": current_user.id},
    )
    new_balance = refreshed.scalar()
    return {"balance": new_balance, "added": body.amount}


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
        "transactions": [
            {
                "id": t.id,
                "amount": t.amount,
                "transaction_type": t.transaction_type,
                "label": _TYPE_LABELS.get(t.transaction_type, t.transaction_type),
                "created_at": t.created_at.isoformat(),
            }
            for t in txns
        ],
    }
