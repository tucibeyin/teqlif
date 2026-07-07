"""
Referral (Davet) Motoru — iş mantığı katmanı.

Sorumluluklar:
  - Benzersiz referral_code üretimi
  - Davet kodu uygulaması (apply_referral)
  - TUCi ödül transferi (referrer +50, referred +10)
"""
import random
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text as sql_text

from app.models.user import User
from app.models.referral import Referral
from app.models.tuci_transaction import TuciTransaction
from app.core.exceptions import BadRequestException, NotFoundException
from app.core.logger import get_logger

logger = get_logger(__name__)

# Okunabilir alfanumerik — karışan karakterler (I, O, 0, 1) çıkarıldı
_SAFE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_CODE_LEN = 7

REFERRER_BONUS = 50   # davet eden
REFERRED_BONUS = 10   # davet edilen


from datetime import datetime, timedelta, timezone

def generate_referral_code() -> str:
    return "".join(random.choices(_SAFE_CHARS, k=_CODE_LEN))


async def ensure_valid_referral_code(db: AsyncSession, user: User) -> dict:
    """
    Kullanıcının geçerli bir davet kodu var mı kontrol eder.
    Yoksa veya süresi dolmuşsa yeni bir tane üretir (3 gün geçerli).
    """
    now = datetime.now(timezone.utc)
    if user.referral_code and user.referral_code_expires_at and user.referral_code_expires_at > now:
        return {
            "code": user.referral_code,
            "expires_at": user.referral_code_expires_at.isoformat()
        }

    # Yeni kod üret
    for _ in range(10):
        code = generate_referral_code()
        existing = await db.scalar(select(User).where(User.referral_code == code))
        if not existing:
            # Kullanıcıya ata ve süresini 3 gün sonrası yap
            user.referral_code = code
            user.referral_code_expires_at = now + timedelta(days=3)
            db.add(user)
            await db.commit()
            await db.refresh(user)
            return {
                "code": user.referral_code,
                "expires_at": user.referral_code_expires_at.isoformat()
            }
    raise RuntimeError("Benzersiz referral kodu üretilemedi")


async def apply_referral(db: AsyncSession, current_user: User, referral_code: str, lang: str = "tr") -> dict:
    """
    Davet kodunu uygular:
      1. Kullanıcı daha önce kod kullanmamışsa devam et.
      2. Kodu bulan referrer'ı bul ve süresinin dolmadığından emin ol.
      3. Kullanıcı tam onaylı değilse (E-posta + Telefon) kodu pending_referred_by olarak kaydet ve bekle.
      4. Tam onaylıysa referrals tablosuna kayıt ekle, ödülleri dağıt, FCM bildirimi at.
    """
    from app.services.firebase_service import send_push
    t = _get_t(lang)
    
    code = referral_code.strip().upper()

    # Daha önce bu kullanıcı bir kod kullandı mı?
    already = await db.scalar(
        select(Referral).where(Referral.referred_id == current_user.id)
    )
    if already:
        raise BadRequestException(t.get("apiErrReferralUsed", "Daha önce bir davet kodu kullandınız. Her hesap yalnızca bir kez kullanabilir."))

    # Kendi kodunu giremez
    if current_user.referral_code and current_user.referral_code.upper() == code:
        raise BadRequestException(t.get("apiErrReferralSelf", "Kendi davet kodunuzu kullanamazsınız."))

    # Kodu bul
    referrer = await db.scalar(select(User).where(User.referral_code == code))
    if not referrer:
        raise NotFoundException(t.get("apiErrReferralInvalid", "Geçersiz davet kodu. Lütfen kontrol edip tekrar deneyin."))

    now = datetime.now(timezone.utc)
    if not referrer.referral_code_expires_at or referrer.referral_code_expires_at < now:
        raise BadRequestException(t.get("apiErrReferralExpired", "Bu davet kodunun süresi dolmuş (3 günlük geçerlilik süresi bitmiş)."))

    # Eğer e-posta veya telefon onaylı değilse: kodu pending olarak kaydet ve çık
    if not current_user.is_verified:
        current_user.pending_referred_by = code
        db.add(current_user)
        await db.commit()
        return {
            "ok": True,
            "is_pending": True,
            "message": t.get("apiMsgReferralSavedVerify", "Davet kodunuz kaydedildi! Ödül kazanmak için lütfen E-posta ve Telefon doğrulamanızı tamamlayın.")
        }

    # Eğer tam onaylıysa ve kodu başarıyla kullanıyorsa pending'i temizle
    if current_user.pending_referred_by == code:
        current_user.pending_referred_by = None
        db.add(current_user)

    # Kayıt ekle
    referral = Referral(
        referrer_id=referrer.id,
        referred_id=current_user.id,
        status="completed",
    )
    db.add(referral)

    # Referrer +50 TUCi
    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance + :amt WHERE id = :uid"),
        {"amt": REFERRER_BONUS, "uid": referrer.id},
    )
    db.add(TuciTransaction(
        user_id=referrer.id,
        amount=REFERRER_BONUS,
        transaction_type="referral_bonus",
    ))

    # Referred +10 TUCi
    await db.execute(
        sql_text("UPDATE users SET tuci_balance = tuci_balance + :amt WHERE id = :uid"),
        {"amt": REFERRED_BONUS, "uid": current_user.id},
    )
    db.add(TuciTransaction(
        user_id=current_user.id,
        amount=REFERRED_BONUS,
        transaction_type="welcome_bonus",
    ))

    await db.commit()
    await db.refresh(current_user)

    logger.info(
        "[REFERRAL] referrer=%s referred=%s | referrer+%d referred+%d TUCi",
        referrer.id, current_user.id, REFERRER_BONUS, REFERRED_BONUS,
    )

    # Referans sahibine bildirim gönder
    if referrer.fcm_token:
        try:
            import asyncio
            t_ref = _get_t(referrer.locale or "tr")
            asyncio.create_task(
                send_push(
                    token=referrer.fcm_token,
                    title=t_ref.get("notifReferralTitle", "Davet Ödülü!"),
                    body=t_ref.get("notifReferralBody", "Bir arkadaşınız ({username}) kodunuzu kullandı ve doğrulamasını tamamladı! {bonus} TUCi kazandınız.").format(username=current_user.username, bonus=REFERRER_BONUS),
                    notif_type="referral_bonus",
                )
            )
        except Exception as e:
            logger.error(f"[REFERRAL] Push notification failed for referrer {referrer.id}: {e}")

    # Davet edilene (yeni kullanıcıya) bildirim gönder
    if current_user.fcm_token:
        try:
            import asyncio
            t_cur = _get_t(current_user.locale or "tr")
            asyncio.create_task(
                send_push(
                    token=current_user.fcm_token,
                    title=t_cur.get("notifReferralTitle", "Davet Ödülü!"),
                    body=t_cur.get("apiMsgReferralSuccess", "Doğrulamalar tamamlandı! {referrer_username} sizi davet etti. Hesabınıza {your_bonus} TUCi eklendi.").format(referrer_username=referrer.username, your_bonus=REFERRED_BONUS),
                    notif_type="welcome_bonus",
                )
            )
        except Exception as e:
            logger.error(f"[REFERRAL] Push notification failed for referred user {current_user.id}: {e}")

    return {
        "ok": True,
        "is_pending": False,
        "referrer_username": referrer.username,
        "referrer_bonus": REFERRER_BONUS,
        "your_bonus": REFERRED_BONUS,
        "new_balance": current_user.tuci_balance,
        "message": t.get("apiMsgReferralSuccess", "Doğrulamalar tamamlandı! {referrer_username} sizi davet etti. Hesabınıza {your_bonus} TUCi eklendi.").format(referrer_username=referrer.username, your_bonus=REFERRED_BONUS),
    }
