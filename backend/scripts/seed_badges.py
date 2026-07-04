"""
Badge test seed scripti.
VPS'de çalıştır:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/seed_badges.py
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import text
from app.database import AsyncSessionLocal
from app.utils.redis_client import get_redis


async def main():
    redis = await get_redis()
    async with AsyncSessionLocal() as db:

        # ── 1. Mevcut ilanları ve sahiplerini çek ──────────────────────────
        rows = (await db.execute(text("""
            SELECT DISTINCT u.id, u.username, l.category
            FROM listings l
            JOIN users u ON u.id = l.user_id
            WHERE l.is_active = TRUE AND l.is_deleted = FALSE
              AND (l.expires_at IS NULL OR l.expires_at > NOW())
            ORDER BY u.id
            LIMIT 20
        """))).fetchall()

        if not rows:
            print("Hiç aktif ilan bulunamadı. Önce ilan ekleyin.")
            return

        user_ids   = list({r[0] for r in rows})
        categories = list({r[2] for r in rows if r[2]})

        print(f"Bulunan kullanıcılar: {user_ids}")
        print(f"Bulunan kategoriler : {categories}")

        # ── 2. seller_badge: trusted_seller → ilk kullanıcıya ──────────────
        if len(user_ids) >= 1:
            uid = user_ids[0]
            await redis.setex(f"seller:badge:{uid}", 90_000, "trusted_seller")
            print(f"✅ trusted_seller  → user_id={uid}")

        # ── 3. seller_badge: active_seller → ikinci kullanıcıya ────────────
        if len(user_ids) >= 2:
            uid = user_ids[1]
            await redis.setex(f"seller:badge:{uid}", 90_000, "active_seller")
            print(f"⭐ active_seller   → user_id={uid}")

        # ── 4. seller_is_premium → üçüncü kullanıcıyı premium yap ─────────
        premium_uid = user_ids[2] if len(user_ids) >= 3 else user_ids[0]
        await db.execute(
            text("UPDATE users SET is_premium = TRUE WHERE id = :uid"),
            {"uid": premium_uid},
        )
        await db.commit()
        print(f"👑 is_premium=TRUE  → user_id={premium_uid}")

        # ── 5. is_trending → varsa ilk iki kategoriyi trending yap ─────────
        key = "trending:categories"
        await redis.delete(key)
        trending = categories[:2] if len(categories) >= 2 else categories
        if trending:
            await redis.sadd(key, *trending)
            await redis.expire(key, 21_600)
            print(f"🔥 trending         → {trending}")
        else:
            print("⚠️  Kategori bulunamadı, trending ayarlanmadı.")

        # ── 6. is_highlight → aktif bir yayın odası gerektiriyor ────────────
        # Mevcut stream room_id varsa aşağıdaki satırı uncomment et:
        # ROOM_ID  = 1          # <-- gerçek room_id
        # HOST_UID = user_ids[0]
        # await db.execute(text("""
        #     INSERT INTO listings (user_id, title, video_url, is_active, is_deleted,
        #                          is_highlight, active_room_id, expires_at, created_at)
        #     VALUES (:uid, 'Canlı Yayın Anı — Test', '/highlights/test.mp4',
        #             TRUE, FALSE, TRUE, :rid, NOW() + INTERVAL '2 hours', NOW())
        #     ON CONFLICT DO NOTHING
        # """), {"uid": HOST_UID, "rid": ROOM_ID})
        # await db.commit()
        # print(f"🔴 is_highlight     → room_id={ROOM_ID}")
        print("🔴 is_highlight     → aktif bir yayın başlatıldığında otomatik oluşur")

        # ── 7. Özet ────────────────────────────────────────────────────────
        # for-you feed Redis cache'ini temizle ki yeni badge'ler hemen görünsün
        async for key in redis.scan_iter("feed:foryou:*"):
            await redis.delete(key)
        print("\n✓ feed:foryou:* cache temizlendi")
        print("✓ Uygulamayı kapat-aç → badge'leri göreceksiniz")


asyncio.run(main())
