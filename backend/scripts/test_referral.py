import asyncio
import os
import sys
import uuid
from datetime import datetime, timezone, timedelta

# Yol ayarları ve .env yükleme
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, backend_dir)
os.chdir(backend_dir)

from app.database import SessionLocal
from app.models.user import User
from app.models.referral import Referral
from app.models.tuci_transaction import TuciTransaction
from sqlalchemy import select, delete
from app.services.referral_service import apply_referral, REFERRER_BONUS, REFERRED_BONUS

async def run_test():
    print("--- Referans Sistemi Testi Başlıyor ---")
    
    async with SessionLocal() as db:
        try:
            # 1. Test kullanıcılarını oluştur
            referrer_username = f"test_ref_{uuid.uuid4().hex[:6]}"
            referred_username = f"test_user_{uuid.uuid4().hex[:6]}"
            
            referrer = User(
                email=f"{referrer_username}@test.com",
                username=referrer_username,
                full_name="Test Referrer",
                hashed_password="fake",
                email_verified=True,
                phone_verified=True,
                referral_code=referrer_username.upper()[:10],
                referral_code_expires_at=datetime.now(timezone.utc) + timedelta(days=3),
                tuci_balance=100
            )
            
            referred = User(
                email=f"{referred_username}@test.com",
                username=referred_username,
                full_name="Test User",
                hashed_password="fake",
                email_verified=False,
                phone_verified=False,
                tuci_balance=100
            )
            
            db.add(referrer)
            db.add(referred)
            await db.commit()
            await db.refresh(referrer)
            await db.refresh(referred)
            
            print(f"[1] Kullanıcılar oluşturuldu: Referans sahibi ({referrer.username}), Yeni Kullanıcı ({referred.username})")
            
            # 2. Davet Kodunu Uygula (Henüz Onay Yok)
            print("[2] Davet kodu uygulanıyor (is_verified = False)...")
            res = await apply_referral(db, referred, referrer.referral_code, "tr")
            print("    Sonuç:", res)
            assert res.get("is_pending") is True, "Kod beklemede durumuna (pending) geçmedi!"
            
            await db.refresh(referred)
            assert referred.pending_referred_by == referrer.referral_code, "pending_referred_by veritabanına işlenmedi!"
            print("    BAŞARILI: Kod pending_referred_by hücresine kaydedildi.")
            
            # 3. Sadece E-Posta Onayı Simülasyonu
            print("[3] Sadece E-posta doğrulaması yapılıyor...")
            referred.email_verified = True
            await db.commit()
            await db.refresh(referred)
            
            # Auth.py'deki kontrol mantığını manuel tetikliyoruz
            if referred.pending_referred_by and referred.is_verified:
                await apply_referral(db, referred, referred.pending_referred_by, "tr")
                
            await db.refresh(referred)
            await db.refresh(referrer)
            assert referred.pending_referred_by is not None, "Sadece e-posta onayıyla ödül dağıtıldı (HATA)!"
            assert referred.tuci_balance == 100, "Sadece e-posta onayıyla bakiye arttı (HATA)!"
            print("    BAŞARILI: Sadece e-posta onayı yetmedi, ödül dağıtılmadı ve kod beklemede kaldı.")
            
            # 4. Telefon Onayı Simülasyonu (Tam Onay)
            print("[4] Telefon doğrulaması da yapılıyor (is_verified = True)...")
            referred.phone_verified = True
            await db.commit()
            await db.refresh(referred)
            
            # Auth.py'deki kontrol mantığını manuel tetikliyoruz
            if referred.pending_referred_by and referred.is_verified:
                print("    Kullanıcı tam onaylı. apply_referral tekrar çağrılıyor...")
                res2 = await apply_referral(db, referred, referred.pending_referred_by, "tr")
                print("    Sonuç:", res2)
                assert res2.get("is_pending") is False, "Ödül dağıtılmadı!"
            
            await db.refresh(referred)
            await db.refresh(referrer)
            
            assert referred.pending_referred_by is None, "pending_referred_by temizlenmedi!"
            assert referrer.tuci_balance == 100 + REFERRER_BONUS, f"Davet eden ödülünü alamadı! (Bakiye: {referrer.tuci_balance})"
            assert referred.tuci_balance == 100 + REFERRED_BONUS, f"Yeni kullanıcı ödülünü alamadı! (Bakiye: {referred.tuci_balance})"
            
            print("    BAŞARILI: Bekleyen kod temizlendi, ödüller kusursuz şekilde hesaplara yattı!")
            print("--- Test Başarıyla Tamamlandı ---")
            
        except AssertionError as e:
            print(f"❌ TEST BAŞARISIZ: {e}")
        except Exception as e:
            print(f"❌ BEKLENMEYEN HATA: {e}")
        finally:
            # Temizlik
            print("[5] Test verileri veritabanından temizleniyor...")
            if 'referred' in locals() and getattr(referred, 'id', None):
                await db.execute(delete(TuciTransaction).where(TuciTransaction.user_id == referred.id))
                await db.execute(delete(Referral).where(Referral.referred_id == referred.id))
                await db.execute(delete(User).where(User.id == referred.id))
            if 'referrer' in locals() and getattr(referrer, 'id', None):
                await db.execute(delete(TuciTransaction).where(TuciTransaction.user_id == referrer.id))
                await db.execute(delete(User).where(User.id == referrer.id))
            await db.commit()

if __name__ == "__main__":
    asyncio.run(run_test())
