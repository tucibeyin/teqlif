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


def generate_referral_code() -> str:
    return "".join(random.choices(_SAFE_CHARS, k=_CODE_LEN))


async def get_unique_referral_code(db: AsyncSession) -> str:
    """Çakışma olmayan benzersiz bir kod döner (max 10 deneme)."""
    for _ in range(10):
        code = generate_referral_code()
        existing = await db.scalar(select(User).where(User.referral_code == code))
        if not existing:
            return code
    # 10 denemede oluşmazsa — pratikte imkansız, yine de güvenli fallback
    raise RuntimeError("Benzersiz referral kodu üretilemedi")


async def apply_referral(db: AsyncSession, current_user: User, referral_code: str) -> dict:
    """
    Davet kodunu uygular:
      1. Kullanıcı daha önce kod kullanmamışsa devam et.
      2. Kodu bulan referrer'ı bul.
      3. referrals tablosuna kayıt ekle.
      4. Referrer'a +50 TUCi, referred'a +10 TUCi yatır.
    """
    code = referral_code.strip().upper()

    # Daha önce bu kullanıcı bir kod kullandı mı?
    already = await db.scalar(
        select(Referral).where(Referral.referred_id == current_user.id)
    )
    if already:
        raise BadRequestException("Daha önce bir davet kodu kullandınız. Her hesap yalnızca bir kez kullanabilir.")

    # Kendi kodunu giremez
    if current_user.referral_code and current_user.referral_code.upper() == code:
        raise BadRequestException("Kendi davet kodunuzu kullanamazsınız.")

    # Kodu bul
    referrer = await db.scalar(select(User).where(User.referral_code == code))
    if not referrer:
        raise NotFoundException("Geçersiz davet kodu. Lütfen kontrol edip tekrar deneyin.")

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

    return {
        "ok": True,
        "referrer_username": referrer.username,
        "referrer_bonus": REFERRER_BONUS,
        "your_bonus": REFERRED_BONUS,
        "new_balance": current_user.tuci_balance,
        "message": f"Davet kodu kabul edildi! {referrer.username} sizi davet etti. "
                   f"Hesabınıza {REFERRED_BONUS} TUCi eklendi.",
    }
