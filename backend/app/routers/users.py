"""
Kullanıcı router — Clean Router Pattern.

Her endpoint sadece:
  1. Bağımlılıkları (auth, db) alır
  2. UserService'i instantiate eder
  3. Uygun servis metodunu çağırır ve sonucu döner

İş mantığı, DB sorguları ve yetki kontrolleri tamamen
app.services.user_service.UserService'e taşınmıştır.
"""
from typing import Optional, List

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.database import get_db
from app.models.user import User
from app.models.referral import Referral
from app.schemas.block import BlockedUserOut, BlockStatusOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.services.user_service import UserService
from app.services.referral_service import apply_referral

router = APIRouter(prefix="/api/users", tags=["users"])


class ApplyReferralBody(BaseModel):
    referral_code: str = Field(min_length=4, max_length=12)


# ── Opsiyonel kullanıcı bağımlılığı (unauthenticated profil erişimi) ─────────
async def _optional_user(
    credentials=Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    if not credentials:
        return None
    user_id = decode_token(credentials.credentials)
    if not user_id:
        return None
    result = await db.execute(
        select(User).where(User.id == user_id, User.is_active == True)  # noqa: E712
    )
    return result.scalar_one_or_none()


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/blocked", response_model=List[BlockedUserOut])
async def list_blocked_users(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).list_blocked(current_user)


@router.post("/{username}/block", response_model=BlockStatusOut)
async def block_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).block(username, current_user)


@router.delete("/{username}/block", response_model=BlockStatusOut)
async def unblock_user(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).unblock(username, current_user)


@router.post("/apply-referral")
async def apply_referral_code(
    body: ApplyReferralBody,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Davet kodunu uygular — referrer +50 TUCi, referred +10 TUCi."""
    return await apply_referral(db, current_user, body.referral_code)


@router.get("/my-referral")
async def my_referral(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının kendi davet kodunu ve istatistiklerini döner."""
    total_invited = await db.scalar(
        select(func.count()).where(Referral.referrer_id == current_user.id)
    )
    already_used = await db.scalar(
        select(Referral).where(Referral.referred_id == current_user.id)
    )
    return {
        "referral_code": current_user.referral_code,
        "referral_link": f"https://teqlif.com/davet/{current_user.referral_code}",
        "total_invited": total_invited or 0,
        "referrer_bonus_per_invite": 50,
        "referred_bonus": 10,
        "already_used_a_code": already_used is not None,
    }


@router.get("/{username}")
async def get_user_profile(
    username: str,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).get_profile(username, current_user)
