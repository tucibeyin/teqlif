from fastapi import APIRouter, Depends, Body
from google.oauth2 import id_token
from google.auth.transport import requests
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.database import get_db
from app.models.user import User
from app.utils.auth import create_access_token
from app.core.exceptions import NotFoundException, ForbiddenException, UnauthorizedException
from app.core.logger import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/api/admin-auth", tags=["admin-auth"])


@router.post("/verify-google")
async def verify_google(token: str = Body(..., embed=True)):
    try:
        idinfo = id_token.verify_oauth2_token(
            token,
            requests.Request(),
            settings.google_client_id,
        )
    except ValueError:
        raise UnauthorizedException("Geçersiz Google Token.")

    if idinfo["email"] != settings.admin_email:
        raise ForbiddenException("Bu alan sadece sistem yöneticisine özeldir.")

    return {"status": "google_ok", "email": idinfo["email"]}


from app.security.auth import AdminSecurity


@router.post("/verify-password")
async def verify_password(
    password: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db),
):
    admin_security = AdminSecurity()
    is_valid = admin_security.verify_admin_password(password)

    # Geçici geriye dönük uyumluluk: eski düz metin şifre desteği
    if not is_valid and settings.admin_password:
        is_valid = password == settings.admin_password

    if not is_valid:
        raise UnauthorizedException("Yönetici şifresi hatalı.")

    result = await db.execute(select(User).where(User.email == settings.admin_email))
    user = result.scalar_one_or_none()
    if not user:
        raise NotFoundException("Admin kullanıcısı veritabanında bulunamadı.")

    access_token = create_access_token(user_id=user.id)
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "message": "Backoffice erişimi onaylandı",
    }
