import asyncio
import logging
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import async_session
from app.models.user import User
from app.models.user_interest import UserInterest
from sqlalchemy import update as sa_update
from sqlalchemy.dialects.postgresql import insert as pg_insert

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def test_onboarding(email: str):
    async with async_session() as db:
        res = await db.execute(select(User).where(User.email == email))
        user = res.scalar_one_or_none()
        if not user:
            logger.error(f"Kullanıcı bulunamadı: {email}")
            return
        
        logger.info(f"--- KULLANICI BİLGİSİ ---")
        logger.info(f"Email: {user.email}")
        logger.info(f"onboarding_completed (DB): {user.onboarding_completed}")
        
        res = await db.execute(select(UserInterest).where(UserInterest.user_id == user.id))
        interests = res.scalars().all()
        logger.info(f"Şu anki ilgi alanı sayısı: {len(interests)}")
        for i in interests:
            logger.info(f" - {i.category} (Skor: {i.score})")

        logger.info(f"\n--- SENARYO 1: Manuel Onboarding Ekleme Testi ---")
        try:
            stmt = (
                pg_insert(UserInterest)
                .values([
                    {
                        "user_id": user.id,
                        "category": "elektronik",
                        "score": 0.70,
                        "raw_signals": {"raw_total": 0.70, "source": "onboarding"},
                    }
                ])
                .on_conflict_do_nothing(constraint="uq_user_interest")
            )
            await db.execute(stmt)
            await db.execute(
                sa_update(User).where(User.id == user.id).values(onboarding_completed=True)
            )
            await db.commit()
            logger.info("BAŞARILI: İlgi alanları DB'ye sorunsuz yazılabiliyor.")
        except Exception as e:
            logger.error(f"HATA (Senaryo 1): {e}")
            await db.rollback()
            return
            
        # Güncel durumu tekrar çek
        res = await db.execute(select(User).where(User.email == email))
        user = res.scalar_one_or_none()
        logger.info(f"Güncel onboarding_completed: {user.onboarding_completed}")
        
        logger.info("\nLütfen uygulamayı açın (veya silip tekrar yükleyip giriş yapın) ve widget'ın çıkıp çıkmadığına bakın.")

if __name__ == "__main__":
    import sys
    email = "teqlif@gmail.com"
    if len(sys.argv) > 1:
        email = sys.argv[1]
    asyncio.run(test_onboarding(email))
