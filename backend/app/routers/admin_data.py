from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from typing import List

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserOut
from app.utils.auth import get_current_user
from app.config import settings

from pydantic import BaseModel
from typing import Optional
from app.utils.auth import hash_password

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

# --- YENİ EKLENEN VERİ MODELLERİ (SCHEMAS) ---
class AdminUserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    is_active: Optional[bool] = None

class AdminPasswordReset(BaseModel):
    new_password: str

# --- YENİ EKLENEN ENDPOINT'LER ---

# 1. Kullanıcı Bilgilerini Güncelleme (Ban/Unban dahil)
@router.patch("/users/{user_id}")
async def update_user_info(
    user_id: int,
    data: AdminUserUpdate,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access)
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    if data.full_name is not None:
        user.full_name = data.full_name
    if data.email is not None:
        user.email = data.email
    if data.is_active is not None:
        user.is_active = data.is_active

    await db.commit()
    return {"message": f"{user.username} bilgileri güncellendi."}

# 2. Şifre Sıfırlama (Backdoor)
@router.patch("/users/{user_id}/password")
async def reset_user_password(
    user_id: int,
    data: AdminPasswordReset,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(check_admin_access)
):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    # Yeni şifreyi bcrypt ile şifreleyip kaydediyoruz
    user.hashed_password = hash_password(data.new_password)
    await db.commit()
    return {"message": f"{user.username} şifresi başarıyla değiştirildi."}