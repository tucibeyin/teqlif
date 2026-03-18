from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import List

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserOut
from app.utils.auth import get_current_user
from app.config import settings

router = APIRouter(prefix="/api/admin-data", tags=["admin-data"])

# GÜVENLİK DUVARI: Token geçerli olsa bile e-posta admin_email değilse reddet
async def check_admin_access(current_user: User = Depends(get_current_user)):
    if current_user.email != settings.admin_email:
        raise HTTPException(status_code=403, detail="Admin yetkisi bulunamadı.")
    return current_user

@router.get("/users/recent", response_model=List[UserOut])
async def get_recent_users(
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access)
):
    result = await db.execute(
        select(User).order_by(desc(User.created_at)).limit(limit)
    )
    return result.scalars().all()