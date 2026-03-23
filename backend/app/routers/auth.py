import random
from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserRegister, UserLogin, UserOut, TokenOut, VerifyEmail, ResendCode, UserUpdate, ChangePasswordConfirm, NotificationPrefs, DEFAULT_NOTIF_PREFS
from app.utils.auth import hash_password, verify_password, create_access_token, get_current_user
from app.utils.email import send_verification_code
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException, UnauthorizedException, ServiceException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auth", tags=["auth"])

VERIFY_CODE_TTL = 600  # 10 dakika


@router.post("/register", status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def register(request: Request, data: UserRegister, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none():
        raise BadRequestException("Bu e-posta adresi zaten kullanılıyor")

    result = await db.execute(select(User).where(User.username == data.username))
    if result.scalar_one_or_none():
        raise BadRequestException("Bu kullanıcı adı zaten alınmış")

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

    # E-posta kuyruğa alınır — API yanıtı bloklanmaz
    try:
        await request.app.state.arq_pool.enqueue_job(
            "send_verification_email_task", data.email, data.full_name, code
        )
    except Exception as e:
        # ARQ pool erişim hatası — yedek olarak direkt gönder
        logger.warning("ARQ enqueue başarısız, direkt gönderilecek [%s]: %s", data.email, str(e))
        try:
            await send_verification_code(data.email, data.full_name, code)
        except Exception as e2:
            logger.warning("Doğrulama e-postası gönderilemedi [%s]: %s", data.email, str(e2))
            capture_exception(e2)

    return {"message": "Kayıt başarılı. E-posta adresinize doğrulama kodu gönderdik."}


@router.post("/verify", response_model=TokenOut)
async def verify(data: VerifyEmail, db: AsyncSession = Depends(get_db)):
    redis = await get_redis()
    stored_code = await redis.get(f"verify:{data.email}")

    if not stored_code or stored_code != data.code:
        raise BadRequestException("Kod hatalı veya süresi dolmuş")

    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user:
        raise NotFoundException("Kullanıcı bulunamadı")

    user.is_verified = True
    await db.commit()
    await db.refresh(user)
    await redis.delete(f"verify:{data.email}")

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
@limiter.limit("5/minute")
async def login(request: Request, data: UserLogin, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.hashed_password):
        raise UnauthorizedException("E-posta veya şifre hatalı")

    if not user.is_active:
        raise ForbiddenException("Hesabınız devre dışı")

    if not user.is_verified:
        raise ForbiddenException("E-posta adresinizi doğrulamanız gerekiyor")

    token = create_access_token(user.id)
    return TokenOut(access_token=token, user=UserOut.model_validate(user))


@router.post("/resend-code")
@limiter.limit("5/minute")
async def resend_code(request: Request, data: ResendCode, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user or user.is_verified:
        raise BadRequestException("Geçersiz istek")

    code = str(random.randint(100000, 999999))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)

    # E-posta kuyruğa alınır — API yanıtı bloklanmaz
    try:
        await request.app.state.arq_pool.enqueue_job(
            "send_verification_email_task", data.email, user.full_name, code
        )
    except Exception as e:
        # ARQ pool erişim hatası — yedek olarak direkt gönder
        logger.warning("ARQ enqueue başarısız, direkt gönderilecek [%s]: %s", data.email, str(e))
        try:
            await send_verification_code(data.email, user.full_name, code)
        except Exception as e2:
            logger.error("Doğrulama kodu e-postası gönderilemedi [%s]: %s", data.email, str(e2), exc_info=True)
            capture_exception(e2)
            raise ServiceException("E-posta gönderilemedi")

    return {"message": "Kod tekrar gönderildi"}


@router.get("/check-username")
async def check_username(username: str = "", exclude_id: int | None = None, db: AsyncSession = Depends(get_db)):
    import re
    if not re.match(r"^[a-z0-9_]{3,50}$", username):
        return {"available": False, "reason": "format"}
    q = select(User).where(User.username == username)
    if exclude_id is not None:
        q = q.where(User.id != exclude_id)
    result = await db.execute(q)
    taken = result.scalar_one_or_none() is not None
    return {"available": not taken}


@router.get("/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    return current_user


@router.patch("/me", response_model=UserOut)
async def update_me(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if data.full_name is not None:
        data.full_name = data.full_name.strip()
        if len(data.full_name) < 2:
            raise BadRequestException("Ad soyad en az 2 karakter olmalı")
        current_user.full_name = data.full_name

    if data.username is not None:
        import re
        if not re.match(r"^[a-z0-9_]{3,50}$", data.username):
            raise BadRequestException("Kullanıcı adı 3-50 karakter, sadece küçük harf/rakam/alt çizgi")
        result = await db.execute(
            select(User).where(User.username == data.username, User.id != current_user.id)
        )
        if result.scalar_one_or_none():
            raise BadRequestException("Bu kullanıcı adı zaten alınmış")
        current_user.username = data.username

    if data.profile_image_url is not None:
        current_user.profile_image_url = data.profile_image_url

    if data.profile_image_thumb_url is not None:
        current_user.profile_image_thumb_url = data.profile_image_thumb_url

    await db.commit()
    await db.refresh(current_user)
    return current_user


@router.post("/change-password/send-code")
async def change_password_send_code(
    current_user: User = Depends(get_current_user),
):
    code = str(random.randint(100000, 999999))
    redis = await get_redis()
    await redis.setex(f"chpwd:{current_user.id}", VERIFY_CODE_TTL, code)
    try:
        await send_verification_code(current_user.email, current_user.full_name, code)
    except Exception as e:
        logger.error("Şifre değişim kodu e-postası gönderilemedi [user_id=%s]: %s", current_user.id, str(e), exc_info=True)
        capture_exception(e)
        raise ServiceException("E-posta gönderilemedi")
    return {"message": "Doğrulama kodu e-posta adresinize gönderildi"}


@router.post("/change-password/confirm")
async def change_password_confirm(
    data: ChangePasswordConfirm,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(data.current_password, current_user.hashed_password):
        raise BadRequestException("Mevcut şifreniz hatalı")
    redis = await get_redis()
    stored_code = await redis.get(f"chpwd:{current_user.id}")
    if not stored_code or stored_code != data.code:
        raise BadRequestException("Doğrulama kodu hatalı veya süresi dolmuş")
    current_user.hashed_password = hash_password(data.new_password)
    await db.commit()
    await redis.delete(f"chpwd:{current_user.id}")
    return {"message": "Şifreniz başarıyla değiştirildi"}


@router.get("/notification-prefs", response_model=NotificationPrefs)
async def get_notification_prefs(current_user: User = Depends(get_current_user)):
    prefs = current_user.notification_prefs or {}
    merged = {**DEFAULT_NOTIF_PREFS, **prefs}
    return NotificationPrefs(**merged)


@router.patch("/notification-prefs", response_model=NotificationPrefs)
async def update_notification_prefs(
    data: NotificationPrefs,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    current_user.notification_prefs = data.model_dump()
    await db.commit()
    await db.refresh(current_user)
    return data


@router.post("/fcm-token")
async def save_fcm_token(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    token = payload.get("token")
    if token:
        current_user.fcm_token = token
        await db.commit()
    return {"ok": True}
