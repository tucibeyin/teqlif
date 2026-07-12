import asyncio
import re
import secrets
from typing import Optional
from fastapi import APIRouter, Cookie, Depends, Request, Response, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, case, update as sa_update

from app.database import get_db
from app.models.user import User
from app.schemas.user import UserRegister, UserLogin, UserOut, TokenOut, VerifyEmail, ResendCode, UserUpdate, ChangePasswordConfirm, NotificationPrefs, DEFAULT_NOTIF_PREFS, ForgotPassword, ResetPassword
from app.utils.auth import hash_password, verify_password, create_access_token, create_refresh_token, REFRESH_TOKEN_TTL, REFRESH_COOKIE, get_current_user, set_auth_cookies, clear_auth_cookies
from app.utils.email import send_verification_code, send_phone_verification_email, send_reset_password_email
from app.utils.i18n import _get_t
from app.utils.redis_client import get_redis
from app.core.exceptions import NotFoundException, BadRequestException, ForbiddenException, EmailNotVerifiedException, UnauthorizedException, ServiceException, ConflictException
from app.core.logger import get_logger, capture_exception
from app.core.rate_limit import limiter
from app.config import settings
from app.services.referral_service import apply_referral

logger = get_logger(__name__)
router = APIRouter(prefix="/api/auth", tags=["auth"])

VERIFY_CODE_TTL = 600          # 10 dakika
_VERIFY_CODE_MIN = 100_000     # 6 haneli kod alt sınırı
_VERIFY_CODE_RANGE = 900_000   # üretilecek kod aralığı (100000–999999)
_USERNAME_RE = re.compile(r"^[a-z0-9_]{3,50}$")
_PHONE_VERIFY_TOKEN_TTL = 1800  # 30 dakika
_SUPPORTED_LANGS = {"tr", "en", "ar"}



def _msg(request, data, key: str, default: str) -> str:
    lang = getattr(data, 'lang', None) if data else None
    if not lang and request:
        lang = _detect_lang(request)
    if not lang:
        lang = "tr"
    return _get_t(lang).get(key, default)


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
    raise_on_failure: bool = False, has_phone: bool = False, lang: str = "tr"
) -> None:
    """Doğrulama e-postasını ARQ kuyruğu üzerinden gönderir; başarısız olursa doğrudan gönderir.

    raise_on_failure=True ise doğrudan gönderim de başarısız olursa ServiceException fırlatır.
    """
    try:
        await request.app.state.arq_pool.enqueue_job(
            "send_verification_email_task", email, full_name, code, has_phone, lang
        )
    except Exception as e:
        logger.warning("ARQ enqueue başarısız, direkt gönderilecek [%s]: %s", email, str(e))
        try:
            await send_verification_code(email, full_name, code, has_phone=has_phone, lang=lang)
        except Exception as e2:
            logger.error(
                "Doğrulama e-postası gönderilemedi [%s]: %s", email, str(e2), exc_info=True
            )
            capture_exception(e2)
            if raise_on_failure:
                raise ServiceException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailFailed", "E-posta gönderilemedi"))


async def _create_user_and_send_code(
    request: Request, data: UserRegister, db: AsyncSession
) -> None:
    """Yeni kullanıcıyı oluşturur, doğrulama kodunu Redis'e kaydeder ve e-posta gönderir."""
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none():
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailTaken", "Bu e-posta adresi zaten kullanılıyor"))

    result = await db.execute(select(User).where(User.username == data.username))
    if result.scalar_one_or_none():
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrUsernameTaken", "Bu kullanıcı adı zaten alınmış"))

    if data.phone:
        result = await db.execute(select(User).where(User.phone == data.phone))
        if result.scalar_one_or_none():
            raise ConflictException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrPhoneTaken", "Bu telefon numarası zaten kayıtlı"))

    user = User(
        email=data.email,
        username=data.username,
        full_name=data.full_name,
        hashed_password=hash_password(data.password),
        email_verified=False,
        phone=data.phone or None,
        referral_code=None,
        pending_referred_by=data.referred_by.strip().upper() if data.referred_by else None,
    )
    db.add(user)
    await db.commit()

    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)
    lang = _detect_lang(request)
    await _send_verification_email(request, data.email, data.full_name, code, has_phone=bool(data.phone), lang=lang)


@router.post("/register", status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def register(request: Request, data: UserRegister, db: AsyncSession = Depends(get_db)):
    await _create_user_and_send_code(request, data, db)
    
    # Telegram Bildirimi (Asenkron)
    try:
        phone_info = data.phone if data.phone else 'Yok'
        msg = f"⏳ <b>Yeni Bir Kullanıcı Kayıt Oldu!</b> (Henüz Onaysız)\n\n👤 <b>İsim:</b> {data.full_name}\n📧 <b>E-posta:</b> {data.email}\n📱 <b>Telefon:</b> {phone_info}"
        await request.app.state.arq_pool.enqueue_job("send_telegram_notification_task", msg)
    except Exception as exc:
        logger.error("[Register] Telegram bildirimi kuyruğa eklenemedi: %s", exc)
        
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgRegisterSuccess", "Kayıt başarılı. E-posta adresinize doğrulama kodu gönderdik.")}


@router.post("/verify", response_model=TokenOut)
@limiter.limit("5/minute")
async def verify(request: Request, data: VerifyEmail, response: Response, db: AsyncSession = Depends(get_db)):
    redis = await get_redis()
    stored_code = await redis.get(f"verify:{data.email}")

    if not stored_code or stored_code != data.code:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrCodeInvalid", "Kod hatalı veya süresi dolmuş"))

    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user:
        raise NotFoundException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrUserNotFound", "Kullanıcı bulunamadı"))

    user.email_verified = True
    await db.commit()
    await db.refresh(user)
    await redis.delete(f"verify:{data.email}")

    if user.pending_referred_by and user.is_verified:
        try:
            from app.services.referral_service import apply_referral
            await apply_referral(db, user, user.pending_referred_by)
        except Exception:
            pass  # Geçersiz/süresi dolmuş kod — doğrulamayı engelleme

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

    # Telegram Bildirimi (Asenkron)
    try:
        msg = f"✅ <b>Kullanıcı E-postasını Onayladı!</b>\n\n👤 <b>İsim:</b> {user.full_name}\n📧 <b>E-posta:</b> {user.email}"
        await request.app.state.arq_pool.enqueue_job("send_telegram_notification_task", msg)
    except Exception as exc:
        logger.error("[Verify] Telegram bildirimi kuyruğa eklenemedi: %s", exc)

    token = create_access_token(user.id)
    refresh = create_refresh_token()
    await redis.setex(f"refresh:{refresh}", REFRESH_TOKEN_TTL, str(user.id))
    set_auth_cookies(response, token, refresh)
    return TokenOut(access_token=token, refresh_token=refresh, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
@limiter.limit("5/minute")
async def login(request: Request, data: UserLogin, response: Response, db: AsyncSession = Depends(get_db)):
    stmt = select(User).where(
        or_(
            func.lower(User.email) == data.login_identifier.lower(),
            func.lower(User.username) == data.login_identifier.lower()
        )
    )
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user or not verify_password(data.password, user.hashed_password):
        raise UnauthorizedException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrInvalidCredentials", "E-posta veya şifre hatalı"))

    if not user.is_active:
        raise ForbiddenException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrAccountDisabled", "Hesabınız devre dışı"))

    if not user.email_verified:
        raise EmailNotVerifiedException(email=user.email)

    if not user.onboarding_completed:
        from app.models.user_interest import UserInterest
        has_interests = await db.scalar(
            select(func.count()).where(UserInterest.user_id == user.id)
        )
        if has_interests:
            user.onboarding_completed = True
            await db.execute(
                sa_update(User).where(User.id == user.id).values(onboarding_completed=True)
            )
            await db.commit()

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
    if not user or user.email_verified:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrInvalidRequest", "Geçersiz istek"))

    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(f"verify:{data.email}", VERIFY_CODE_TTL, code)
    lang = data.lang if hasattr(data, 'lang') and data.lang else _detect_lang(request)
    await _send_verification_email(request, data.email, user.full_name, code, raise_on_failure=True, lang=lang)
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgCodeResent", "Kod tekrar gönderildi")}


@router.post("/forgot-password")
@limiter.limit("3/minute")
async def forgot_password(request: Request, data: ForgotPassword, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    
    # We return 200 even if user doesn't exist to prevent email enumeration
    if not user:
        return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgResetEmailSent", "Şifre sıfırlama e-postası gönderildi")}
        
    code = str(_VERIFY_CODE_MIN + secrets.randbelow(_VERIFY_CODE_RANGE))
    redis = await get_redis()
    await redis.setex(f"reset_pwd:{data.email}", VERIFY_CODE_TTL, code)
    
    lang = data.lang if hasattr(data, 'lang') and data.lang else _detect_lang(request)
    try:
        await send_reset_password_email(data.email, user.full_name, code, lang)
    except Exception as e:
        logger.error(f"Reset password email failed for {data.email}: {e}")
        capture_exception(e)
        raise ServiceException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailFailedLater", "E-posta gönderilemedi, lütfen daha sonra tekrar deneyin."))
        
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgResetEmailSent", "Şifre sıfırlama e-postası gönderildi")}


@router.post("/reset-password")
@limiter.limit("5/minute")
async def reset_password(request: Request, data: ResetPassword, db: AsyncSession = Depends(get_db)):
    redis = await get_redis()
    key = f"reset_pwd:{data.email}"
    stored_code = await redis.get(key)
    
    if not stored_code or stored_code != data.code:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrCodeInvalidOrExpired", "Geçersiz veya süresi dolmuş kod"))
        
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    
    if not user:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrCodeInvalidOrExpired", "Geçersiz veya süresi dolmuş kod"))
        
    user.hashed_password = hash_password(data.new_password)
    await db.commit()
    await redis.delete(key)
    
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgPasswordReset", "Şifreniz başarıyla sıfırlandı")}


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
async def me(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if not current_user.onboarding_completed:
        from app.models.user_interest import UserInterest
        has_interests = await db.scalar(
            select(func.count()).where(UserInterest.user_id == current_user.id)
        )
        if has_interests:
            current_user.onboarding_completed = True
            await db.execute(
                sa_update(User).where(User.id == current_user.id).values(onboarding_completed=True)
            )
            await db.commit()
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
    if hasattr(data, 'locale') and data.locale is not None:
        current_user.locale = data.locale.strip()

    if data.full_name is not None:
        data.full_name = data.full_name.strip()
        if len(data.full_name) < 2:
            raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrNameShort", "Ad soyad en az 2 karakter olmalı"))
        current_user.full_name = data.full_name

    if data.username is not None:
        if not _USERNAME_RE.match(data.username):
            raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrUsernameFormat", "Kullanıcı adı 3-50 karakter, sadece küçük harf/rakam/alt çizgi"))
        result = await db.execute(
            select(User).where(User.username == data.username, User.id != current_user.id)
        )
        if result.scalar_one_or_none():
            raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrUsernameTaken", "Bu kullanıcı adı zaten alınmış"))
        current_user.username = data.username

    if data.profile_image_url is not None:
        current_user.profile_image_url = data.profile_image_url

    if data.profile_image_thumb_url is not None:
        current_user.profile_image_thumb_url = data.profile_image_thumb_url

    if data.bio is not None:
        bio = data.bio.strip()
        if len(bio) > 60:
            raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrBioLong", "Biyografi en fazla 60 karakter olabilir"))
        current_user.bio = bio or None

    if data.website_url is not None:
        url = data.website_url.strip()
        if url and not url.startswith(("http://", "https://")):
            raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrLinkFormat", "Link http:// veya https:// ile başlamalı"))
        current_user.website_url = url or None

    _social_fields = ("instagram_url", "kick_url", "twitch_url", "facebook_url", "youtube_url", "tiktok_url")
    for _field in _social_fields:
        _val = getattr(data, _field, None)
        if _val is not None:
            setattr(current_user, _field, _val.strip() or None)

    if data.locale is not None:
        current_user.locale = data.locale.strip()

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
    from app.models.stream import LiveStream
    from app.models.user import User

    result = await db.execute(
        select(
            Auction.id,
            Auction.item_name,
            Auction.start_price,
            Auction.final_price,
            Auction.is_bought_it_now,
            Auction.bid_count,
            Auction.started_at,
            Auction.ended_at,
            Auction.listing_id,
            Auction.stream_id,
            Auction.proof_image_url,
            ListingModel.image_url,
            ListingModel.category,
            ListingModel.thumbnail_url,
            User.username.label("seller_username"),
            func.coalesce(LiveStream.host_id, ListingModel.user_id).label("seller_id"),
        )
        .join(ListingModel, ListingModel.id == Auction.listing_id, isouter=True)
        .join(LiveStream, LiveStream.id == Auction.stream_id, isouter=True)
        .join(User, User.id == LiveStream.host_id, isouter=True)
        .where(
            Auction.winner_id == current_user.id,
            Auction.status == "completed",
        )
        .order_by(Auction.ended_at.desc())
        .limit(50)
    )
    rows = result.fetchall()
    return [
        {
            "auction_id": r.id,
            "stream_id": r.stream_id,
            "item_name": r.item_name,
            "start_price": r.start_price,
            "final_price": r.final_price,
            "is_bought_it_now": r.is_bought_it_now,
            "bid_count": r.bid_count,
            "started_at": r.started_at.isoformat() if r.started_at else None,
            "ended_at": r.ended_at.isoformat() if r.ended_at else None,
            "listing_id": r.listing_id,
            "image_url": r.image_url,
            "thumbnail_url": r.thumbnail_url,
            "proof_image_url": r.proof_image_url,
            "category": r.category,
            "seller_username": r.seller_username,
            "seller_id": r.seller_id,
        }
        for r in rows
    ]


@router.get("/me/sales")
async def my_sales(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcının (Host) sattığı ürünlerin geçmişi (son 50 kayıt)."""
    from app.models.auction import Auction
    from app.models.listing import Listing as ListingModel
    from app.models.stream import LiveStream
    from app.models.user import User

    # The seller is either the stream host or the listing user
    result = await db.execute(
        select(
            Auction.id,
            Auction.item_name,
            Auction.start_price,
            Auction.final_price,
            Auction.is_bought_it_now,
            Auction.bid_count,
            Auction.started_at,
            Auction.ended_at,
            Auction.listing_id,
            Auction.stream_id,
            Auction.proof_image_url,
            ListingModel.image_url,
            ListingModel.category,
            ListingModel.thumbnail_url,
            User.username.label("buyer_username"),
            Auction.winner_id.label("buyer_id"),
        )
        .join(ListingModel, ListingModel.id == Auction.listing_id, isouter=True)
        .join(LiveStream, LiveStream.id == Auction.stream_id, isouter=True)
        .join(User, User.id == Auction.winner_id, isouter=True)
        .where(
            # the current user is the host of the stream where it was sold
            # OR the current user is the owner of the listing
            or_(
                LiveStream.host_id == current_user.id,
                ListingModel.user_id == current_user.id
            ),
            Auction.status == "completed",
            Auction.winner_id.is_not(None)
        )
        .order_by(Auction.ended_at.desc())
        .limit(50)
    )
    rows = result.fetchall()
    return [
        {
            "auction_id": r.id,
            "stream_id": r.stream_id,
            "item_name": r.item_name,
            "start_price": r.start_price,
            "final_price": r.final_price,
            "is_bought_it_now": r.is_bought_it_now,
            "bid_count": r.bid_count,
            "started_at": r.started_at.isoformat() if r.started_at else None,
            "ended_at": r.ended_at.isoformat() if r.ended_at else None,
            "listing_id": r.listing_id,
            "image_url": r.image_url,
            "thumbnail_url": r.thumbnail_url,
            "proof_image_url": r.proof_image_url,
            "category": r.category,
            "buyer_username": r.buyer_username,
            "buyer_id": r.buyer_id,
        }
        for r in rows
    ]


@router.get("/me/auction/{auction_id}")
async def my_auction_context(
    auction_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Bir açık artırmanın detayını döndürür.
    Çağıran kullanıcı alıcıysa 'purchase' rolü, satıcıysa 'sale' rolü döner.
    Mesajlardaki teqlif://auction/{id} linklerinde kullanılır.
    """
    from app.models.auction import Auction
    from app.models.listing import Listing as ListingModel
    from app.models.stream import LiveStream
    from app.models.user import User as UserModel

    uid = current_user.id

    # Alıcı mı? (winner_id == current_user.id)
    result = await db.execute(
        select(
            Auction.id,
            Auction.item_name,
            Auction.start_price,
            Auction.final_price,
            Auction.is_bought_it_now,
            Auction.bid_count,
            Auction.started_at,
            Auction.ended_at,
            Auction.listing_id,
            Auction.stream_id,
            Auction.proof_image_url,
            ListingModel.image_url,
            ListingModel.category,
            ListingModel.thumbnail_url,
            UserModel.username.label("seller_username"),
            func.coalesce(LiveStream.host_id, ListingModel.user_id).label("seller_id"),
        )
        .join(ListingModel, ListingModel.id == Auction.listing_id, isouter=True)
        .join(LiveStream, LiveStream.id == Auction.stream_id, isouter=True)
        .join(UserModel, UserModel.id == LiveStream.host_id, isouter=True)
        .where(Auction.id == auction_id, Auction.winner_id == uid)
    )
    buyer_row = result.fetchone()
    if buyer_row:
        return {
            "role": "buyer",
            "data": {
                "auction_id": buyer_row.id,
                "stream_id": buyer_row.stream_id,
                "item_name": buyer_row.item_name,
                "start_price": buyer_row.start_price,
                "final_price": buyer_row.final_price,
                "is_bought_it_now": buyer_row.is_bought_it_now,
                "bid_count": buyer_row.bid_count,
                "started_at": buyer_row.started_at.isoformat() if buyer_row.started_at else None,
                "ended_at": buyer_row.ended_at.isoformat() if buyer_row.ended_at else None,
                "listing_id": buyer_row.listing_id,
                "image_url": buyer_row.image_url,
                "thumbnail_url": buyer_row.thumbnail_url,
                "proof_image_url": buyer_row.proof_image_url,
                "category": buyer_row.category,
                "seller_username": buyer_row.seller_username,
                "seller_id": buyer_row.seller_id,
            },
        }

    # Satıcı mı? (stream host veya listing sahibi)
    result2 = await db.execute(
        select(
            Auction.id,
            Auction.item_name,
            Auction.start_price,
            Auction.final_price,
            Auction.is_bought_it_now,
            Auction.bid_count,
            Auction.started_at,
            Auction.ended_at,
            Auction.listing_id,
            Auction.stream_id,
            Auction.proof_image_url,
            ListingModel.image_url,
            ListingModel.category,
            ListingModel.thumbnail_url,
            UserModel.username.label("buyer_username"),
            Auction.winner_id.label("buyer_id"),
        )
        .join(ListingModel, ListingModel.id == Auction.listing_id, isouter=True)
        .join(LiveStream, LiveStream.id == Auction.stream_id, isouter=True)
        .join(UserModel, UserModel.id == Auction.winner_id, isouter=True)
        .where(
            Auction.id == auction_id,
            or_(LiveStream.host_id == uid, ListingModel.user_id == uid),
        )
    )
    seller_row = result2.fetchone()
    if seller_row:
        return {
            "role": "seller",
            "data": {
                "auction_id": seller_row.id,
                "stream_id": seller_row.stream_id,
                "item_name": seller_row.item_name,
                "start_price": seller_row.start_price,
                "final_price": seller_row.final_price,
                "is_bought_it_now": seller_row.is_bought_it_now,
                "bid_count": seller_row.bid_count,
                "started_at": seller_row.started_at.isoformat() if seller_row.started_at else None,
                "ended_at": seller_row.ended_at.isoformat() if seller_row.ended_at else None,
                "listing_id": seller_row.listing_id,
                "image_url": seller_row.image_url,
                "thumbnail_url": seller_row.thumbnail_url,
                "proof_image_url": seller_row.proof_image_url,
                "category": seller_row.category,
                "buyer_username": seller_row.buyer_username,
                "buyer_id": seller_row.buyer_id,
            },
        }

    from app.core.exceptions import NotFoundException
    raise NotFoundException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrAuctionNotFound", "Bu açık artırma bulunamadı veya erişim izniniz yok"))


@router.post("/refresh")
@limiter.limit("60/minute")
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
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrTokenRequired", "refresh_token gerekli"))

    redis = await get_redis()
    user_id_str = await redis.get(f"refresh:{token}")
    if not user_id_str:
        raise UnauthorizedException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrTokenInvalid", "Geçersiz veya süresi dolmuş refresh token"))

    result = await db.execute(select(User).where(User.id == int(user_id_str)))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise UnauthorizedException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrUserNotFound", "Kullanıcı bulunamadı"))

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
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgLogout", "Çıkış yapıldı")}


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
        raise ServiceException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailFailed", "E-posta gönderilemedi"))
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgVerifyEmailSent", "Doğrulama kodu e-posta adresinize gönderildi")}


@router.post("/change-password/confirm")
async def change_password_confirm(
    data: ChangePasswordConfirm,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if not verify_password(data.current_password, current_user.hashed_password):
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrCurrentPasswordInvalid", "Mevcut şifreniz hatalı"))
    redis = await get_redis()
    stored_code = await redis.get(f"chpwd:{current_user.id}")
    if not stored_code or stored_code != data.code:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrVerifyCodeInvalid", "Doğrulama kodu hatalı veya süresi dolmuş"))
    current_user.hashed_password = hash_password(data.new_password)
    await db.commit()
    await redis.delete(f"chpwd:{current_user.id}")
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgPasswordChanged", "Şifreniz başarıyla değiştirildi")}


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
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailInvalid", "Geçersiz e-posta adresi"))

    new_email = data.new_email.lower().strip()

    if new_email == current_user.email:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailSame", "Bu zaten mevcut e-posta adresiniz"))

    existing = await db.scalar(select(User).where(User.email == new_email))
    if existing:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailTaken", "Bu e-posta adresi zaten kullanılıyor"))

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
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailRetry", "E-posta gönderilemedi, lütfen tekrar deneyin"))

    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgCodeSent", "Doğrulama kodu gönderildi")}


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
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrVerifyCodeNotFound", "Doğrulama kodu bulunamadı veya süresi doldu"))

    stored = _json.loads(raw)
    if stored["code"] != data.code.strip():
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrVerifyCodeWrong", "Doğrulama kodu hatalı"))
    if stored["new_email"] != data.new_email.lower().strip():
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailMismatch", "E-posta adresi eşleşmiyor"))

    # Çakışma son kontrolü
    existing = await db.scalar(
        select(User).where(User.email == stored["new_email"], User.id != current_user.id)
    )
    if existing:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrEmailUsed", "Bu e-posta adresi başka bir hesapta kullanılıyor"))

    current_user.email = stored["new_email"]
    await db.commit()
    await redis.delete(f"email_change:{current_user.id}")

    logger.info("[EMAIL_CHANGE] E-posta güncellendi | user_id=%s → %s", current_user.id, stored["new_email"])
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgEmailUpdated", "E-posta adresiniz başarıyla güncellendi")}


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
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrPhoneFormat", "Geçersiz telefon numarası formatı"))

    # Başka bir kullanıcıda kayıtlıysa reddet
    existing = await db.scalar(
        select(User).where(User.phone == data.phone, User.id != current_user.id)
    )
    if existing:
        raise BadRequestException(_msg(request if "request" in locals() else None, locals().get("data"), "apiErrPhoneUsed", "Bu telefon numarası başka bir hesapta kayıtlı"))

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
    return {"message": _msg(request if "request" in locals() else None, locals().get("data"), "apiMsgVerifyEmailSent2", "Doğrulama e-postası gönderildi")}


@router.get("/phone-verify/confirm")
async def confirm_phone_verification_page(
    token: Optional[str] = None,
    action: Optional[str] = None,
):
    """E-posta linki: onay sayfası gösterir. Gerçek işlem POST ile yapılır.
    Email prefetcher'ları GET atar ama POST atamaz — token korunmuş olur."""
    from fastapi.responses import HTMLResponse
    if not token:
        return HTMLResponse(_phone_verify_html(
            "Geçersiz Bağlantı",
            "Bu doğrulama bağlantısı geçersiz.",
            "#64748b", False,
        ), status_code=400)
    redis = await get_redis()
    if not await redis.exists(f"phone_verify:{token}"):
        return HTMLResponse(_phone_verify_html(
            "Bağlantı Kullanılamaz",
            "Bu doğrulama bağlantısı daha önce kullanılmış ya da süresi dolmuş.",
            "#64748b", False,
        ))
    return HTMLResponse(_phone_verify_confirm_page(token, action or "yes"))


@router.post("/phone-verify/confirm")
async def confirm_phone_verification(
    request: Request,
    action: str,
    db: AsyncSession = Depends(get_db),
):
    """Kullanıcı onay butonuna bastığında çağrılır. Token bu noktada tüketilir.
    Token form body'den okunur (HTML'de görünmez → email tarayıcı POST atamaz)."""
    from fastapi.responses import HTMLResponse
    import json as _json

    # Token yalnızca form field'ında — query string'de yok (scanner koruması)
    form = await request.form()
    token = form.get("token")
    if not token:
        return HTMLResponse(_phone_verify_html(
            "Geçersiz İstek", "Token bulunamadı.", "#ef4444", False,
        ))

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
            await db.refresh(user)
            if user.pending_referred_by and user.is_verified:
                try:
                    from app.services.referral_service import apply_referral
                    await apply_referral(db, user, user.pending_referred_by)
                except Exception:
                    pass
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
    """GET ile açılan onay sayfası — kullanıcı butona basana kadar hiçbir şey olmaz.
    JS auto-submit yok: link prefetcher / Mail Privacy Protection koruması."""
    if action == "yes":
        icon = "📱"
        heading = "Telefon Numaranızı Doğrulayın"
        desc = "Bu telefon numarasını hesabınıza eklemek istediğinizi onaylayın."
        btn_text = "Evet, Bu Numara Benim"
        btn_color = "#0d9488"
    else:
        icon = "🚫"
        heading = "Telefon Numarasını Reddet"
        desc = "Bu numarayı siz eklemediyseniz aşağıdaki butona basın; numara hesabınızdan kaldırılacak."
        btn_text = "Bu Numara Benim Değil"
        btn_color = "#ef4444"

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
    .brand{{color:#06b6d4;font-weight:800;font-size:24px;letter-spacing:-0.5px;margin-bottom:24px;}}
    .icon{{font-size:48px;margin-bottom:16px;}}
    h2{{color:#f1f5f9;font-size:20px;font-weight:700;margin-bottom:12px;}}
    p{{color:#94a3b8;font-size:14px;line-height:1.6;margin-bottom:28px;}}
    .btn{{display:block;width:100%;padding:15px;background:{btn_color};color:#fff;
          border:none;border-radius:14px;font-size:16px;font-weight:700;
          cursor:pointer;text-decoration:none;}}
    .btn:hover{{opacity:0.9;}}
  </style>
</head>
<body>
  <div class="card">
    <div class="brand">teqlif</div>
    <div class="icon">{icon}</div>
    <h2>{heading}</h2>
    <p>{desc}</p>
    <form method="POST" action="/api/auth/phone-verify/confirm?action={action}">
      <input type="hidden" name="token" value="{token}">
      <button type="submit" class="btn">{btn_text}</button>
    </form>
  </div>
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
    request: Request,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    token = payload.get("token")
    lang = _detect_lang(request)

    values: dict = {}
    if token:
        values["fcm_token"] = token
    if current_user.locale != lang:
        values["locale"] = lang

    if values:
        await db.execute(sa_update(User).where(User.id == current_user.id).values(**values))
        await db.commit()
    return {"ok": True}
