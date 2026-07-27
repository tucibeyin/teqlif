"""
Satıcı Rozeti Algoritması Kapsamlı Test Scripti (test_seller_badges_exhaustive.py)

Bu test scripti:
1. Hiç açık artırma açmamış, sadece normal ilan satışı (listing_sold, offer_accepted) yapmış
   mock satıcı etkinliklerini ClickHouse 'user_events' tablosuna yazar.
2. 'compute_seller_badges_task' worker görevini tetikler.
3. Redis üzerinde 'trusted_seller' ve 'active_seller' rozetlerinin oluştuğunu
   ve 25 saatlik (90.000 saniye) TTL değerinin korunduğunu doğrular.
4. Test bitiminde mock verileri ClickHouse ve Redis'ten temizler.

Kullanım:
    python3 documents/badge_algorithms/tests/test_seller_badges_exhaustive.py
"""

import asyncio
import os
import sys
from datetime import datetime, timezone, timedelta

# Backend dizinini sys.path'e ekle
root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
backend_dir = os.path.join(root_dir, "backend")
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from dotenv import load_dotenv
load_dotenv(os.path.join(backend_dir, ".env"))

from app.database_clickhouse import get_clickhouse_client
from app.utils.redis_client import get_redis
from app.worker import compute_seller_badges_task


MOCK_TRUSTED_SELLER_ID = 999901
MOCK_ACTIVE_SELLER_ID = 999902
MOCK_NO_BADGE_SELLER_ID = 999903


async def run_test():
    print("🚀 [Test 3.1] Satıcı Rozeti Kapsamlı Testi Başlıyor...\n")
    
    ch = await get_clickhouse_client()
    redis = await get_redis()

    # 1. Önceki mock verileri temizle
    print("🧹 Önceki mock veriler temizleniyor...")
    await redis.delete(
        f"seller:badge:{MOCK_TRUSTED_SELLER_ID}",
        f"seller:badge:{MOCK_ACTIVE_SELLER_ID}",
        f"seller:badge:{MOCK_NO_BADGE_SELLER_ID}"
    )
    try:
        await ch.execute(
            f"ALTER TABLE user_events DELETE WHERE user_id IN ({MOCK_TRUSTED_SELLER_ID}, {MOCK_ACTIVE_SELLER_ID}, {MOCK_NO_BADGE_SELLER_ID})"
        )
    except Exception as exc:
        print(f"⚠️ ClickHouse temizleme uyarısı (ilk çalışma olabilir): {exc}")

    # 2. Mock verileri ClickHouse 'user_events' tablosuna yaz
    print("📦 Mock satıcı etkinlikleri ClickHouse'a ekleniyor...")
    now_dt = datetime.now(timezone.utc)
    ch_rows = []

    # Trusted Seller (999901): 10 işlem, 10 başarılı satış (conv = 1.0 >= 0.75)
    for i in range(8):
        ch_rows.append([
            MOCK_TRUSTED_SELLER_ID, 1000 + i, "listing", "listing_sold",
            150.0, 0.0, "{}", now_dt - timedelta(hours=i+1)
        ])
    for i in range(2):
        ch_rows.append([
            MOCK_TRUSTED_SELLER_ID, 1100 + i, "listing", "offer_accepted",
            200.0, 0.0, "{}", now_dt - timedelta(hours=i+1)
        ])

    # Active Seller (999902): 51 işlem, 1 başarılı satış (conv ~ 0.02 < 0.75, total = 51 >= active_threshold)
    ch_rows.append([
        MOCK_ACTIVE_SELLER_ID, 2000, "listing", "listing_sold",
        100.0, 0.0, "{}", now_dt - timedelta(hours=2)
    ])
    for i in range(50):
        ch_rows.append([
            MOCK_ACTIVE_SELLER_ID, 2001 + i, "listing", "listing_offer_submit",
            90.0, 0.0, "{}", now_dt - timedelta(minutes=i*10)
        ])

    # No Badge Seller (999903): 1 işlem (total = 1 < 2, eşik altı)
    ch_rows.append([
        MOCK_NO_BADGE_SELLER_ID, 3000, "listing", "listing_offer_submit",
        50.0, 0.0, "{}", now_dt - timedelta(hours=5)
    ])

    await ch.insert(
        "user_events",
        ch_rows,
        column_names=[
            "user_id", "item_id", "item_type",
            "event_type", "price_point",
            "duration_seconds", "metadata", "timestamp",
        ],
    )
    print(f"✅ {len(ch_rows)} mock etkinlik eklendi.\n")

    # ClickHouse mutation'larının ve insert'ün tam görünmesi için çok kısa bekleme
    await asyncio.sleep(1)

    # 3. Worker görevini tetikle
    print("⚙️ compute_seller_badges_task() çalıştırılıyor...")
    await compute_seller_badges_task()
    print("✅ Worker görevi tamamlandı.\n")

    # 4. Redis rozetlerini ve TTL değerlerini doğrula
    print("🔍 Redis rozet atamaları doğrulanıyor...")
    
    # 999901 -> trusted_seller
    badge_trusted = await redis.get(f"seller:badge:{MOCK_TRUSTED_SELLER_ID}")
    ttl_trusted = await redis.ttl(f"seller:badge:{MOCK_TRUSTED_SELLER_ID}")
    print(f"  🧑‍💼 User {MOCK_TRUSTED_SELLER_ID} (Trusted): Badge = {badge_trusted}, TTL = {ttl_trusted}s")
    
    assert badge_trusted == "trusted_seller", f"Beklenen: 'trusted_seller', Alınan: '{badge_trusted}'"
    assert ttl_trusted > 89000, f"TTL değeri 25 saate yakın (90000s) olmalı, Alınan: {ttl_trusted}s"

    # 999902 -> active_seller
    badge_active = await redis.get(f"seller:badge:{MOCK_ACTIVE_SELLER_ID}")
    ttl_active = await redis.ttl(f"seller:badge:{MOCK_ACTIVE_SELLER_ID}")
    print(f"  🧑‍💼 User {MOCK_ACTIVE_SELLER_ID} (Active): Badge = {badge_active}, TTL = {ttl_active}s")
    
    assert badge_active == "active_seller", f"Beklenen: 'active_seller', Alınan: '{badge_active}'"
    assert ttl_active > 89000, f"TTL değeri 25 saate yakın (90000s) olmalı, Alınan: {ttl_active}s"

    # 999903 -> None
    badge_none = await redis.get(f"seller:badge:{MOCK_NO_BADGE_SELLER_ID}")
    print(f"  🧑‍💼 User {MOCK_NO_BADGE_SELLER_ID} (Under threshold): Badge = {badge_none}")
    assert badge_none is None, f"Beklenen: None, Alınan: '{badge_none}'"

    print("\n✨ TÜM DOĞRULAMALAR BAŞARILI! (Hiç açık artırma açmayan satıcılar rozetlendi)")

    # 5. Temizlik
    print("\n🧹 Test sonrası mock veriler temizleniyor...")
    await redis.delete(
        f"seller:badge:{MOCK_TRUSTED_SELLER_ID}",
        f"seller:badge:{MOCK_ACTIVE_SELLER_ID}",
        f"seller:badge:{MOCK_NO_BADGE_SELLER_ID}"
    )
    try:
        await ch.execute(
            f"ALTER TABLE user_events DELETE WHERE user_id IN ({MOCK_TRUSTED_SELLER_ID}, {MOCK_ACTIVE_SELLER_ID}, {MOCK_NO_BADGE_SELLER_ID})"
        )
    except Exception as exc:
        print(f"⚠️ ClickHouse temizleme uyarısı: {exc}")
    print("✅ Temizlik tamamlandı.")


if __name__ == "__main__":
    asyncio.run(run_test())
