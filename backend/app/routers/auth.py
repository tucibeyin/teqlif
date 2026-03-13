import random
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserRegister, UserLogin, UserOut, TokenOut, VerifyEmail, ResendCode
from app.utils.auth import hash_password, verify_password, create_access_token, get_current_user
from app.utils.email import send_verification_code
from app.utils.redis_client import get_redis

router = APIRouter(prefix="/api/auth", tags=["auth"])

VERIFY_CODE_TTL = 600  # 10 dakika


@router.post("/register", status_code=status.HTTP_201_CREATED)
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Bu e-posta adresi zaten kullanılıyor")

    result = await db.execute(select(User).where(User.username == data.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Bu kullanıcı adı zaten alınmış")

    user = User(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        is_verified=False,
    )
    db.add(user)
    await db.commit()

    # 6 haneli kod üret, Redis'e kaydet
    code = str(random.randint(100000, 999999))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)

    # E-posta gönder
    try:
        await send_verification_code(data.email, data.full_name, code)
    except Exception:
        # E-posta hatası kayıt işlemini engellemesin
        pass

    return {"message": "Kayıt başarılı. E-posta adresinize doğrulama kodu gönderdik."}


@router.post("/verify", response_model=TokenOut)
async def verify(data: VerifyEmail, db: AsyncSession = Depends(get_db)):
    redis = await get_redis()
    stored_code = await redis.get(f"verify:{data.email}")

    if not stored_code or stored_code != data.code:
        raise HTTPException(status_code=400, detail="Kod hatalı veya süresi dolmuş")

    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    user.is_verified = True
    await db.commit()
    await db.refresh(user)
    await redis.delete(f"verify:{data.email}")

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı")

    if not user.is_active:
        raise HTTPException(status_code=403, detail="Hesabınız devre dışı")

    if not user.is_verified:
        raise HTTPException(status_code=403, detail="E-posta adresinizi doğrulamanız gerekiyor")

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user=UserOut.model_validate(user))


@router.post("/resend-code")
async def resend_code(data: ResendCode, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user or user.is_verified:
        raise HTTPException(status_code=400, detail="Geçersiz istek")

    code = str(random.randint(100000, 999999))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)

    try:
        await send_verification_code(data.email, user.full_name, code)
    except Exception:
        raise HTTPException(status_code=500, detail="E-posta gönderilemedi")

    return {"message": "Kod tekrar gönderildi"}


@router.get("/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    return current_user
