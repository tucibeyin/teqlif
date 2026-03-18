from fastapi import APIRouter, Depends, HTTPException, Body, status
from google.oauth2 import id_token
from google.auth.transport import requests
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.database import get_db
from app.models.user import User
from app.utils.auth import create_access_token

router = APIRouter(prefix="/api/admin-auth", tags=["admin-auth"])

@router.post("/verify-google")
async def verify_google(token: str = Body(..., embed=True)):
    try:
        # 1. Google Token'ını doğrula
        idinfo = id_token.verify_oauth2_token(
            token, 
            requests.Request(), 
            settings.google_client_id
        )

        # 2. E-posta kontrolü (Sadece senin e-postan mı?)
        if idinfo['email'] != settings.admin_email:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, 
                detail="Bu alan sadece sistem yöneticisine özeldir."
            )

        return {"status": "google_ok", "email": idinfo['email']}
    
    except ValueError:
        raise HTTPException(status_code=401, detail="Geçersiz Google Token.")

@router.post("/verify-password")
async def verify_password(
    password: str = Body(..., embed=True),
    db: AsyncSession = Depends(get_db)
):
    # 1. .env'deki ADMIN_PASSWORD ile karşılaştır
    if password != settings.admin_password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, 
            detail="Yönetici şifresi hatalı."
        )

    # 2. Şifre doğruysa, senin kullanıcını DB'de bul ve bir admin token'ı üret
    result = await db.execute(
        select(User).where(User.email == settings.admin_email)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="Admin kullanıcısı veritabanında bulunamadı.")

    # Normal kullanıcı login'indeki gibi token üret
    access_token = create_access_token(user_id=user.id)
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "message": "Backoffice erişimi onaylandı"
    }