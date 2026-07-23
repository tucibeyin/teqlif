"""
Onboarding — Yeni kullanıcı kategori tercihleri.

Kayıt sonrası kişiselleştirme için başlangıç user_interests kaydı oluşturur.
Mevcut kayıtların üzerine yazmaz (ON CONFLICT DO NOTHING).
"""
from fastapi import APIRouter, Depends
from pydantic import BaseModel, field_validator
from sqlalchemy import update as sa_update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import get_db
from app.models.user import User
from app.models.user_interest import UserInterest
from app.utils.auth import get_current_user
from app.utils.redis_client import get_redis

router = APIRouter(prefix="/api/onboarding", tags=["onboarding"])

_VALID_CATEGORIES = {
    "electronics", "vehicles", "real_estate", "fashion",
    "sports", "books", "home", "other",
}
_ONBOARDING_SCORE = 0.70


class OnboardingPayload(BaseModel):
    categories: list[str]

    @field_validator("categories")
    @classmethod
    def validate_categories(cls, v: list[str]) -> list[str]:
        valid = [c for c in v if c in _VALID_CATEGORIES]
        if not valid:
            raise ValueError("INVALID_CATEGORY")
        return valid[:5]


@router.post("/interests")
async def seed_interests(
    payload: OnboardingPayload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """
    Seçilen kategorileri user_interests tablosuna ekler.
    Kullanıcının daha önce organik olarak oluşturduğu kayıtlara dokunmaz.
    """
    stmt = (
        pg_insert(UserInterest)
        .values([
            {
                "user_id": current_user.id,
                "category": cat,
                "score": _ONBOARDING_SCORE,
                "raw_signals": {"raw_total": _ONBOARDING_SCORE, "source": "onboarding"},
            }
            for cat in payload.categories
        ])
        .on_conflict_do_nothing(constraint="uq_user_interest")
    )
    await db.execute(stmt)
    await db.execute(
        sa_update(User).where(User.id == current_user.id).values(onboarding_completed=True)
    )
    await db.commit()

    # Feed cache'i geçersiz kıl — yeni interests hemen etkili olsun
    try:
        redis = await get_redis()
        await redis.delete(
            f"interests:{current_user.id}",
            f"feed:{current_user.id}:0",
        )
    except Exception:
        pass

    return {"ok": True}
