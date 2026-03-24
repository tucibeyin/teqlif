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
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.schemas.block import BlockedUserOut, BlockStatusOut
from app.utils.auth import get_current_user, bearer_scheme, decode_token
from app.services.user_service import UserService

router = APIRouter(prefix="/api/users", tags=["users"])


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


@router.get("/{username}")
async def get_user_profile(
    username: str,
    current_user: Optional[User] = Depends(_optional_user),
    db: AsyncSession = Depends(get_db),
):
    return await UserService(db).get_profile(username, current_user)
