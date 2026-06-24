from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from app.database import get_db
from app.models.user import User
from app.models.tuci_transaction import TuciTransaction
from app.utils.auth import get_current_user

router = APIRouter(prefix="/api/wallet", tags=["wallet"])

_TYPE_LABELS = {
    "airdrop":       "Hoş geldin hediyesi",
    "spend_lead_gen": "Sıcak Talep blast",
    "spend_ai":      "Yapay Zeka fiyatlama",
}


@router.get("/balance")
async def get_balance(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TuciTransaction)
        .where(TuciTransaction.user_id == current_user.id)
        .order_by(desc(TuciTransaction.created_at))
        .limit(5)
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
