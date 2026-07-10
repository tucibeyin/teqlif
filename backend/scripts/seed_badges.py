"""
Gerçek verilerden badge/trending hesaplar ve feed cache'ini temizler.
Worker'ın 01:30'ı beklemeden anında tetikler.

VPS'de çalıştır:
  cd /var/www/teqlif.com/backend
  source /var/www/teqlif.com/venv/bin/activate
  python scripts/seed_badges.py
"""
import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


async def main():
    from app.worker import compute_seller_badges_task, compute_trending_categories_task
    from app.utils.redis_client import get_redis

    ctx: dict = {}

    # ── 1. Satıcı rozeti hesapla (ClickHouse auction verisinden) ──────────
    print("▶ compute_seller_badges_task çalışıyor...")
    try:
        await compute_seller_badges_task(ctx)
        print("✓ Satıcı rozetleri Redis'e yazıldı")
    except Exception as e:
        print(f"✗ compute_seller_badges_task başarısız: {e}")

    # ── 1b. ClickHouse listing event debug ────────────────────────────────
    try:
        from app.database_clickhouse import get_clickhouse_client
        ch = await get_clickhouse_client()
        if ch:
            r = await ch.query("""
                SELECT event_type, count() AS cnt
                FROM user_events
                WHERE item_type = 'listing' AND timestamp >= now() - INTERVAL 48 HOUR
                GROUP BY event_type ORDER BY cnt DESC
            """)
            print(f"  [ClickHouse] Son 48s listing event'leri: {r.result_rows or '(yok)'}")
            r2 = await ch.query("""
                SELECT count(DISTINCT item_id) FROM user_events
                WHERE item_type = 'listing' AND timestamp >= now() - INTERVAL 48 HOUR
            """)
            print(f"  [ClickHouse] Unique listing sayısı: {r2.result_rows[0][0] if r2.result_rows else 0}")
    except Exception as e:
        print(f"  [ClickHouse] Debug sorgusu başarısız: {e}")

    # ── 2. Trend kategorileri hesapla (PostgreSQL auction verisinden) ──────
    print("▶ compute_trending_categories_task çalışıyor...")
    try:
        await compute_trending_categories_task(ctx)
        print("✓ Trend kategoriler Redis'e yazıldı")
    except Exception as e:
        print(f"✗ compute_trending_categories_task başarısız: {e}")

    # ── 3. Feed cache'ini temizle → yeni badge'ler hemen görünsün ─────────
    redis = await get_redis()
    deleted = 0
    async for key in redis.scan_iter("feed:foryou:*"):
        await redis.delete(key)
        deleted += 1
    print(f"✓ {deleted} adet feed:foryou:* cache temizlendi")

    # ── 4. Özet ───────────────────────────────────────────────────────────
    badge_keys = []
    async for key in redis.scan_iter("seller:badge:*"):
        badge_keys.append(key)
    trending = await redis.smembers("trending:categories")
    trending_listings = await redis.smembers("trending:listings")

    print(f"\n{'─'*40}")
    print(f"Rozet sayısı   : {len(badge_keys)}")
    for k in badge_keys:
        v = await redis.get(k)
        print(f"  {k} → {v}")
    print(f"Trend kategoriler: {trending or '(yok)'}")
    print(f"Trend ilanlar    : {len(trending_listings)} ilan {('→ ' + str({int(v) for v in trending_listings})) if trending_listings else '(yok)'}")
    print(f"{'─'*40}")
    print("Uygulamayı kapat-aç veya pull-to-refresh → badge'leri göreceksiniz")


asyncio.run(main())
