import asyncio
import re
import secrets
from typing import Optional
from fastapi import APIRouter, Cookie, Depends, Request, Response, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserRegister, UserLogin, UserOut, TokenOut, VerifyEmail, ResendCode, UserUpdate, ChangePasswordConfirm, NotificationPrefs, DEFAULT_NOTIF_PREFS
from app.utils.auth import hash_password, verify_password, create_access_token, create_refresh_token, REFRESH_TOKEN_TTL, REFRESH_COOKIE, get_current_user, set_auth_cookies, clear_auth_cookies
from app.utils.email import send_verification_code, send_phone_verification_email
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException, EmailNotVerifiedException, UnauthorizedException, ServiceException, ConflictException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter
from app.config import settings

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auth", tags=["auth"])

VERIFY_CODE_TTL = 600          # 10 dakika
_VERIFY_CODE_MIN = 100_000     # 6 haneli kod alt sınırı
_VERIFY_CODE_RANGE = 900_000   # üretilecek kod aralığı (100000–999999)
_USERNAME_RE = re.compile(r"^[a-z0-9_]{3,50}$")
_PHONE_VERIFY_TOKEN_TTL = 1800  # 30 dakika
_SUPPORTED_LANGS = {"tr", "en", "ar"}


def _detect_lang(request: Request) -> str:
    """Accept-Language header'ından desteklenen dili döner; bulunamazsa 'tr'."""
    header = request.headers.get("accept-language", "")
    for part in header.replace(",", ";").split(";"):
        lang = part.strip()[:2].lower()
        if lang in _SUPPORTED_LANGS:
            return lang
    return "tr"


async def _send_verification_email(
    request: Request, email: str, full_name: str, code: str, *,
    raise_on_failure: bool = False, has_phone: bool = False,
) -> None:
    """Doğrulama e-postasını ARQ kuyruğu üzerinden gönderir; başarısız olursa doğrudan gönderir.

    raise_on_failure=True ise doğrudan gönderim de başarısız olursa ServiceException fırlatır.
    """
    try:
        await request.app.state.arq_pool.enqueue_job(
            "send_verification_email_task", email, full_name, code, has_phone
        )
    except Exception as e:
        logger.warning("ARQ enqueue başarısız, direkt gönderilecek [%s]: %s", email, str(e))
        try:
            await send_verification_code(email, full_name, code, has_phone=has_phone)
        except Exception as e2:
            logger.error(
                "Doğrulama e-postası gönderilemedi [%s]: %s", email, str(e2), exc_info=True
            )
            capture_exception(e2)
            if raise_on_failure:
                raise ServiceException("E-posta gönderilemedi")


async def _create_user_and_send_code(
    request: Request, data: UserRegister, db: AsyncSession
) -> None:
    """Yeni kullanıcıyı oluşturur, doğrulama kodunu Redis'e kaydeder ve e-posta gönderir."""
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none():
        raise BadRequestException("Bu e-posta adresi zaten kullanılıyor")

    result = await db.execute(select(User).where(User.username == data.username))
    if result.scalar_one_or_none():
        raise BadRequestException("Bu kullanıcı adı zaten alınmış")

    if data.phone:
        result = await db.execute(select(User).where(User.phone == data.phone))
        if result.scalar_one_or_none():
            raise ConflictException("Bu telefon numarası zaten kayıtlı")

    user = User(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        is_verified=False,
        phone=data.phone or None,
    )
    db.add(user)
    await db.commit()

    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)
    await _send_verification_email(request, data.email, data.full_name, code, has_phone=bool(data.phone))


@router.post("/register", status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def register(request: Request, data: UserRegister, db: AsyncSession = Depends(get_db)):
    await _create_user_and_send_code(request, data, db)
    return {"message": "Kayıt başarılı. E-posta adresinize doğrulama kodu gönderdik."}


@router.post("/verify", response_model=TokenOut)
@limiter.limit("5/minute")
async def verify(request: Request, data: VerifyEmail, response: Response, db: AsyncSession = Depends(get_db)):
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

    lang = _detect_lang(request)
    try:
        await request.app.state.arq_pool.enqueue_job(
            "send_welcome_email_task", user.email, user.full_name, bool(user.phone), lang,
        )
    except Exception as exc:
        logger.warning("[WELCOME] Kuyruğa alınamadı, direkt gönderiliyor | %s", exc)
        try:
            from app.utils.email import send_welcome_email
            await send_welcome_email(user.email, user.full_name, has_phone=bool(user.phone), lang=lang)
        except Exception as exc2:
            logger.error("[WELCOME] Gönderilemedi | %s", exc2)

    token = create_access_token(user.id)
    refresh = create_refresh_token()
    await redis.setex(f"refresh:{refresh}", REFRESH_TOKEN_TTL, str(user.id))
    set_auth_cookies(response, token, refresh)
    return TokenOut(access_token=token, refresh_token=refresh, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
@limiter.limit("5/minute")
async def login(request: Request, data: UserLogin, response: Response, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.hashed_password):
        raise UnauthorizedException("E-posta veya şifre hatalı")

    if not user.is_active:
        raise ForbiddenException("Hesabınız devre dışı")

    if not user.is_verified:
        raise EmailNotVerifiedException()

    redis = await get_redis()
    token = create_access_token(user.id)
    refresh = create_refresh_token()
    await redis.setex(f"refresh:{refresh}", REFRESH_TOKEN_TTL, str(user.id))
    set_auth_cookies(response, token, refresh)
    return TokenOut(access_token=token, refresh_token=refresh, user=UserOut.model_validate(user))


@router.post("/resend-code")
@limiter.limit("5/minute")
async def resend_code(request: Request, data: ResendCode, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user or user.is_verified:
        raise BadRequestException("Geçersiz istek")

    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)
    await _send_verification_email(request, data.email, user.full_name, code, raise_on_failure=True)
    return {"message": "Kod tekrar gönderildi"}


@router.get("/check-username")
async def check_username(username: str = "", exclude_id: int | None = None, db: AsyncSession = Depends(get_db)):
    if not _USERNAME_RE.match(username):
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


@router.get("/init")
async def init_context(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Single endpoint that returns user + wallet balance + unread counts.
    Used by the frontend to reduce page-load API calls from 4 to 1."""
    from app.models.notification import Notification
    from app.models.message import DirectMessage

    notif_result, msg_result = await asyncio.gather(
        db.execute(
            select(func.count()).where(
                Notification.user_id == current_user.id,
                Notification.is_read == False,  # noqa: E712
                Notification.type != "message",
            )
        ),
        db.execute(
            select(func.count()).where(
                DirectMessage.receiver_id == current_user.id,
                DirectMessage.is_read == False,  # noqa: E712
            )
        ),
    )

    return {
        "user": UserOut.model_validate(current_user),
        "wallet_balance": current_user.tuci_balance,
        "notifications_unread": notif_result.scalar_one(),
        "messages_unread": msg_result.scalar_one(),
    }


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
        if not _USERNAME_RE.match(data.username):
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

    if data.bio is not None:
        bio = data.bio.strip()
        if len(bio) > 60:
            raise BadRequestException("Biyografi en fazla 60 karakter olabilir")
        current_user.bio = bio or None

    if data.website_url is not None:
        url = data.website_url.strip()
        if url and not url.startswith(("http://", "https://")):
            raise BadRequestException("Link http:// veya https:// ile başlamalı")
        current_user.website_url = url or None

    await db.commit()
    await db.refresh(current_user)
    return current_user


@router.get("/me/purchases")
async def my_purchases(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının açık artırmada kazandığı ürünlerin geçmişi (son 50 kayıt)."""
    from app.models.auction import Auction
    from app.models.listing import Listing as ListingModel

    result = await db.execute(
        select(
            Auction.id,
            Auction.item_name,
            Auction.final_price,
            Auction.is_bought_it_now,
            Auction.bid_count,
            Auction.ended_at,
            Auction.listing_id,
            ListingModel.image_url,
            ListingModel.category,
            ListingModel.thumbnail_url,
        )
        .join(ListingModel, ListingModel.id == Auction.listing_id, isouter=True)
        .where(
            Auction.winner_id == current_user.id,
            Auction.status == "ended",
        )
        .order_by(Auction.ended_at.desc())
        .limit(50)
    )
    rows = result.fetchall()
    return [
        {
            "auction_id": r.id,
            "item_name": r.item_name,
            "final_price": r.final_price,
            "is_bought_it_now": r.is_bought_it_now,
            "bid_count": r.bid_count,
            "ended_at": r.ended_at.isoformat() if r.ended_at else None,
            "listing_id": r.listing_id,
            "image_url": r.image_url,
            "thumbnail_url": r.thumbnail_url,
            "category": r.category,
        }
        for r in rows
    ]


@router.post("/refresh")
@limiter.limit("20/minute")
async def refresh_token(
    request: Request,
    response: Response,
    payload: dict = {},
    cookie_refresh: Optional[str] = Cookie(default=None, alias=REFRESH_COOKIE),
    db: AsyncSession = Depends(get_db),
):
    # Cookie öncelikli (web), body fallback (mobile)
    token = cookie_refresh or payload.get("refresh_token", "")
    if not token:
        raise BadRequestException("refresh_token gerekli")

    redis = await get_redis()
    user_id_str = await redis.get(f"refresh:{token}")
    if not user_id_str:
        raise UnauthorizedException("Geçersiz veya süresi dolmuş refresh token")

    result = await db.execute(select(User).where(User.id == int(user_id_str)))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise UnauthorizedException("Kullanıcı bulunamadı")

    # Eski token'ı sil (rotation), yeni token çifti üret
    await redis.delete(f"refresh:{token}")
    new_access = create_access_token(user.id)
    new_refresh = create_refresh_token()
    await redis.setex(f"refresh:{new_refresh}", REFRESH_TOKEN_TTL, str(user.id))
    set_auth_cookies(response, new_access, new_refresh)

    return {"access_token": new_access, "refresh_token": new_refresh, "token_type": "bearer"}


@router.post("/logout")
async def logout(response: Response):
    """Cookie'leri temizler. Mobile token'ları frontend tarafından silinir."""
    clear_auth_cookies(response)
    return {"message": "Çıkış yapıldı"}


@router.post("/change-password/send-code")
async def change_password_send_code(
    current_user: User = Depends(get_current_user),
):
    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
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


class _EmailChangeRequest(BaseModel):
    new_email: str


class _EmailChangeVerify(BaseModel):
    new_email: str
    code: str


@router.post("/email-change/request", status_code=status.HTTP_202_ACCEPTED)
async def request_email_change(
    data: _EmailChangeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Yeni e-postaya doğrulama kodu gönderir."""
    from pydantic import EmailStr, validate_email
    from pydantic_core import PydanticCustomError
    import json as _json

    # Temel format kontrolü
    try:
        validate_email(data.new_email)
    except Exception:
        raise BadRequestException("Geçersiz e-posta adresi")

    new_email = data.new_email.lower().strip()

    if new_email == current_user.email:
        raise BadRequestException("Bu zaten mevcut e-posta adresiniz")

    existing = await db.scalar(select(User).where(User.email == new_email))
    if existing:
        raise BadRequestException("Bu e-posta adresi zaten kullanılıyor")

    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(
        f"email_change:{current_user.id}",
        VERIFY_CODE_TTL,
        _json.dumps({"new_email": new_email, "code": code}),
    )

    try:
        await send_verification_code(new_email, current_user.full_name, code)
    except Exception as exc:
        logger.error("[EMAIL_CHANGE] Kod gönderilemedi | user_id=%s | %s", current_user.id, exc)
        raise BadRequestException("E-posta gönderilemedi, lütfen tekrar deneyin")

    return {"message": "Doğrulama kodu gönderildi"}


@router.post("/email-change/verify")
async def verify_email_change(
    data: _EmailChangeVerify,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Doğrulama kodunu kontrol edip e-postayı günceller."""
    import json as _json

    redis = await get_redis()
    raw = await redis.get(f"email_change:{current_user.id}")
    if not raw:
        raise BadRequestException("Doğrulama kodu bulunamadı veya süresi doldu")

    stored = _json.loads(raw)
    if stored["code"] != data.code.strip():
        raise BadRequestException("Doğrulama kodu hatalı")
    if stored["new_email"] != data.new_email.lower().strip():
        raise BadRequestException("E-posta adresi eşleşmiyor")

    # Çakışma son kontrolü
    existing = await db.scalar(
        select(User).where(User.email == stored["new_email"], User.id != current_user.id)
    )
    if existing:
        raise BadRequestException("Bu e-posta adresi başka bir hesapta kullanılıyor")

    current_user.email = stored["new_email"]
    await db.commit()
    await redis.delete(f"email_change:{current_user.id}")

    logger.info("[EMAIL_CHANGE] E-posta güncellendi | user_id=%s → %s", current_user.id, stored["new_email"])
    return {"message": "E-posta adresiniz başarıyla güncellendi"}


class _PhoneVerifyRequest(BaseModel):
    phone: str


@router.post("/phone-verify/request", status_code=status.HTTP_202_ACCEPTED)
async def request_phone_verification(
    data: _PhoneVerifyRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Telefon numarasını kaydedip doğrulama e-postası gönderir."""
    from app.security.validation import SecureInputValidator
    from fastapi.responses import JSONResponse

    valid, err = SecureInputValidator.validate_phone(data.phone)
    if not valid:
        raise BadRequestException("Geçersiz telefon numarası formatı")

    # Başka bir kullanıcıda kayıtlıysa reddet
    existing = await db.scalar(
        select(User).where(User.phone == data.phone, User.id != current_user.id)
    )
    if existing:
        raise BadRequestException("Bu telefon numarası başka bir hesapta kayıtlı")

    # Telefonu kaydet (henüz doğrulanmamış)
    current_user.phone = data.phone
    current_user.phone_verified = False
    await db.commit()

    # Token üret ve Redis'e kaydet
    token = secrets.token_urlsafe(32)
    redis = await get_redis()
    import json as _json
    await redis.setex(
        f"phone_verify:{token}",
        _PHONE_VERIFY_TOKEN_TTL,
        _json.dumps({"user_id": current_user.id, "phone": data.phone}),
    )

    base_url = settings.site_url.rstrip("/")
    yes_url = f"{base_url}/api/auth/phone-verify/confirm?token={token}&action=yes"
    no_url = f"{base_url}/api/auth/phone-verify/confirm?token={token}&action=no"

    try:
        await send_phone_verification_email(
            email=current_user.email,
            full_name=current_user.full_name,
            phone=data.phone,
            yes_url=yes_url,
            no_url=no_url,
        )
    except Exception as exc:
        logger.error("[PHONE_VERIFY] E-posta gönderilemedi | user_id=%s | %s", current_user.id, exc)

    logger.info("[PHONE_VERIFY] Doğrulama e-postası gönderildi | user_id=%s phone=%s", current_user.id, data.phone)
    return {"message": "Doğrulama e-postası gönderildi"}


@router.get("/phone-verify/confirm")
async def confirm_phone_verification_page(
    token: str,
    action: str,
):
    """E-posta linki: onay sayfası gösterir. Gerçek işlem POST ile yapılır.
    Email prefetcher'ları GET atar ama POST atamaz — token korunmuş olur."""
    from fastapi.responses import HTMLResponse
    redis = await get_redis()
    if not await redis.exists(f"phone_verify:{token}"):
        return HTMLResponse(_phone_verify_html(
            "Bağlantı Kullanılamaz",
            "Bu doğrulama bağlantısı daha önce kullanılmış ya da süresi dolmuş.",
            "#64748b", False,
        ))
    return HTMLResponse(_phone_verify_confirm_page(token, action))


@router.post("/phone-verify/confirm")
async def confirm_phone_verification(
    token: str,
    action: str,
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcı onay butonuna bastığında çağrılır. Token bu noktada tüketilir."""
    from fastapi.responses import HTMLResponse
    import json as _json

    redis = await get_redis()
    raw = await redis.get(f"phone_verify:{token}")

    if not raw:
        return HTMLResponse(_phone_verify_html(
            "Bağlantı Geçersiz",
            "Bu doğrulama bağlantısı geçersiz ya da süresi dolmuş (30 dk geçerlidir).",
            "#ef4444", False,
        ))

    data = _json.loads(raw)
    user_id = data["user_id"]
    phone = data["phone"]

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        await redis.delete(f"phone_verify:{token}")
        return HTMLResponse(_phone_verify_html(
            "Hata", "Kullanıcı bulunamadı.", "#ef4444", False,
        ))

    if action == "yes":
        if user.phone == phone:
            user.phone_verified = True
            await db.commit()
        await redis.delete(f"phone_verify:{token}")
        return HTMLResponse(_phone_verify_html(
            "Telefon Doğrulandı ✓",
            f"<strong>{phone}</strong> numarası başarıyla doğrulandı. Uygulamaya dönebilirsiniz.",
            "#0d9488", True,
        ))
    else:
        if user.phone == phone:
            user.phone = None
            user.phone_verified = False
            await db.commit()
        await redis.delete(f"phone_verify:{token}")
        return HTMLResponse(_phone_verify_html(
            "Numara Reddedildi",
            "Telefon numarası hesabınızdan kaldırıldı. Uygulamadan profil sayfanıza gidip numaranızı güncelleyebilirsiniz.",
            "#f59e0b", False,
        ))


def _phone_verify_confirm_page(token: str, action: str) -> str:
    """GET ile açılan ara sayfa.
    Email tarayıcıları JS çalıştırmaz → token korunur.
    Gerçek kullanıcı açınca JS formu anında POST eder → tek dokunuşta sonuç."""
    label = "Telefonunuz doğrulanıyor..." if action == "yes" else "Telefon numaranız kaldırılıyor..."
    return f"""<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>teqlif — Telefon Doğrulama</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0;}}
    body{{background:#0f172a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;
         display:flex;align-items:center;justify-content:center;min-height:100vh;padding:16px;}}
    .card{{background:#1e293b;border-radius:24px;padding:40px 28px;max-width:400px;width:100%;
           text-align:center;box-shadow:0 8px 40px #00000080;}}
    .brand{{color:#06b6d4;font-weight:800;font-size:24px;letter-spacing:-0.5px;margin-bottom:32px;}}
    .spinner{{width:48px;height:48px;border:3px solid #1e3a5f;border-top-color:#06b6d4;
              border-radius:50%;animation:spin 0.8s linear infinite;margin:0 auto 20px;}}
    @keyframes spin{{to{{transform:rotate(360deg)}}}}
    p{{color:#94a3b8;font-size:15px;}}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">teqlif</div>
    <div class="spinner"></div>
    <p>{label}</p>
    <form id="f" method="POST" action="/api/auth/phone-verify/confirm?token={token}&action={action}" style="display:none"></form>
  </div>
  <script>document.getElementById('f').submit();</script>
</body>
</html>"""


def _phone_verify_html(title: str, body: str, color: str, success: bool) -> str:
    icon = "✓" if success else "✕"
    btn = (
        f'<a href="teqlif://profile" style="display:inline-block;margin-top:24px;background:{color};color:#fff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:700;font-size:15px;">Uygulamaya Dön</a>'
        if success else ""
    )
    return f"""<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>teqlif — {title}</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0;}}
    body{{background:#0f172a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:16px;}}
    .card{{background:#1e293b;border-radius:24px;padding:40px 28px;max-width:400px;width:100%;text-align:center;box-shadow:0 8px 40px #00000080;}}
    .brand{{color:#06b6d4;font-weight:800;font-size:24px;letter-spacing:-0.5px;margin-bottom:32px;}}
    .icon{{width:80px;height:80px;border-radius:50%;background:{color}20;border:2px solid {color}60;display:flex;align-items:center;justify-content:center;margin:0 auto 24px;font-size:36px;color:{color};}}
    h2{{color:#f1f5f9;margin:0 0 14px;font-size:22px;font-weight:700;}}
    p{{color:#94a3b8;line-height:1.7;font-size:15px;}}
    .hint{{margin-top:20px;font-size:13px;color:#475569;}}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">teqlif</div>
    <div class="icon">{icon}</div>
    <h2>{title}</h2>
    <p>{body}</p>
    {btn}
    <p class="hint">Bu sayfayı kapatıp uygulamaya dönebilirsiniz.</p>
  </div>
</body>
</html>"""


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
