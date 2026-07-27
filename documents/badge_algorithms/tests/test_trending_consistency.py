"""
Trend İlanlar Tutarlılık Test Scripti (test_trending_consistency.py)

Bu test scripti:
1. 'trending:listings' (6 saatlik yavaş küme) ve 'trending:listings:velocity' (30 dakikalık hızlı küme)
   Redis kümelerine farklı test ilan ID'leri yazar.
2. 'listing_utils._fetch_seller_meta()' fonksiyonunu çağırarak iki kümenin
   UNION (birleşim) biçiminde eksiksiz döndürüldüğünü doğrular.
3. Sunum katmanı yardımcı fonksiyonu ('_row_dict') üzerinden, her iki kümedeki ilanların da
   istemciye (mobil/web) 'is_trending=True' olarak sunulduğunu doğrular.
4. Test bitiminde Redis üzerindeki test üyelerini temizler.

Kullanım:
    python3 documents/badge_algorithms/tests/test_trending_consistency.py
"""

import asyncio
import os
import sys
from unittest.mock import MagicMock

# Backend dizinini sys.path'e ekle
root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
backend_dir = os.path.join(root_dir, "backend")
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from dotenv import load_dotenv
load_dotenv(os.path.join(backend_dir, ".env"))

from app.utils.redis_client import get_redis
from app.use_cases.listings.queries.listing_utils import _fetch_seller_meta, _row_dict
from app.models.enums import ListingStatus


MOCK_SLOW_LISTING_ID = 888801   # Sadece 6 saatlik kümede
MOCK_FAST_LISTING_ID = 888802   # Sadece 30 dakikalık velocity kümesinde
MOCK_BOTH_LISTING_ID = 888803   # Her iki kümede de var
MOCK_NONE_LISTING_ID = 888804   # Hiçbir trend kümesinde yok


async def run_test():
    print("🚀 [Test 3.2] Trend İlanlar Tutarlılık Testi Başlıyor...\n")
    
    redis = await get_redis()

    # 1. Önceki test kalıntılarını temizle
    print("🧹 Önceki test üyeleri temizleniyor...")
    await redis.srem("trending:listings", str(MOCK_SLOW_LISTING_ID), str(MOCK_BOTH_LISTING_ID))
    await redis.srem("trending:listings:velocity", str(MOCK_FAST_LISTING_ID), str(MOCK_BOTH_LISTING_ID))

    # 2. Redis kümelerine test ilan ID'lerini ekle
    print("📦 Test ilan ID'leri Redis kümelerine (slow & velocity) ekleniyor...")
    await redis.sadd("trending:listings", str(MOCK_SLOW_LISTING_ID), str(MOCK_BOTH_LISTING_ID))
    await redis.sadd("trending:listings:velocity", str(MOCK_FAST_LISTING_ID), str(MOCK_BOTH_LISTING_ID))
    print(f"  🐢 Slow Set ('trending:listings'): [{MOCK_SLOW_LISTING_ID}, {MOCK_BOTH_LISTING_ID}]")
    print(f"  ⚡ Fast Set ('trending:listings:velocity'): [{MOCK_FAST_LISTING_ID}, {MOCK_BOTH_LISTING_ID}]\n")

    # 3. _fetch_seller_meta() fonksiyonunu çalıştır
    print("⚙️ _fetch_seller_meta() çağrılarak birleşik trend kümesi çekiliyor...")
    badge_map, trending_cats, trending_listing_ids, trust_map, influence_map = await _fetch_seller_meta([1])
    print(f"  📊 Çekilen Birleşik Küme ('trending_listing_ids'): {trending_listing_ids}\n")

    # 4. Küme birleşimini doğrula (UNION kontrolü)
    print("🔍 UNION birleşim doğrulaması yapılıyor...")
    assert MOCK_SLOW_LISTING_ID in trending_listing_ids, f"HATA: {MOCK_SLOW_LISTING_ID} (slow set) birleşimde bulunamadı!"
    print(f"  ✅ İlan {MOCK_SLOW_LISTING_ID} (sadece Yavaş Kümede) -> birleşik trend kümesinde mevcut.")

    assert MOCK_FAST_LISTING_ID in trending_listing_ids, f"HATA: {MOCK_FAST_LISTING_ID} (velocity set) birleşimde bulunamadı!"
    print(f"  ✅ İlan {MOCK_FAST_LISTING_ID} (sadece Hızlı/Velocity Kümede) -> birleşik trend kümesinde mevcut.")

    assert MOCK_BOTH_LISTING_ID in trending_listing_ids, f"HATA: {MOCK_BOTH_LISTING_ID} (her iki kümede) birleşimde bulunamadı!"
    print(f"  ✅ İlan {MOCK_BOTH_LISTING_ID} (her iki kümede) -> birleşik trend kümesinde mevcut.")

    assert MOCK_NONE_LISTING_ID not in trending_listing_ids, f"HATA: {MOCK_NONE_LISTING_ID} (trend olmayan ilan) yanlışlıkla trendlerde!"
    print(f"  ✅ İlan {MOCK_NONE_LISTING_ID} (trend olmayan) -> birleşik trend kümesinde YOK (doğru).\n")

    # 5. Sunum katmanı (_row_dict) bütünlüğünü doğrula
    print("🎨 Sunum katmanı (_row_dict) 'is_trending' çıktıları doğrulanıyor...")
    mock_user = MagicMock()
    mock_user.id = 1
    mock_user.username = "test_user"
    mock_user.full_name = "Test User"
    mock_user.profile_image_url = None
    mock_user.profile_image_thumb_url = None
    mock_user.is_premium = False
    mock_user.is_verified = False

    for lid, expected_trending in [
        (MOCK_SLOW_LISTING_ID, True),
        (MOCK_FAST_LISTING_ID, True),
        (MOCK_BOTH_LISTING_ID, True),
        (MOCK_NONE_LISTING_ID, False),
    ]:
        mock_listing = MagicMock()
        mock_listing.id = lid
        mock_listing.title = f"Test İlan {lid}"
        mock_listing.description = ""
        mock_listing.price = 100.0
        mock_listing.category = "test"
        mock_listing.subcategory = "test"
        mock_listing.brand = ""
        mock_listing.condition = ""
        mock_listing.extra_fields = {}
        mock_listing.image_url = None
        mock_listing.image_urls = None
        mock_listing.thumbnail_url = None
        mock_listing.video_url = None
        mock_listing.location = "Istanbul"
        mock_listing.status = ListingStatus.ACTIVE
        mock_listing.created_at = None
        mock_listing.updated_at = None
        mock_listing.deactivated_at = None
        mock_listing.expires_at = None
        mock_listing.is_highlight = False
        mock_listing.buy_it_now_price = None

        is_trend_flag = lid in trending_listing_ids
        row_res = _row_dict(mock_listing, mock_user, is_trending=is_trend_flag)
        
        assert row_res["is_trending"] == expected_trending, (
            f"İlan {lid} için beklenen is_trending={expected_trending}, fakat {row_res['is_trending']} alındı!"
        )
        print(f"  🎯 İlan {lid} sunum çıktısı -> is_trending={row_res['is_trending']} (Beklenen: {expected_trending})")

    print("\n✨ TÜM DOĞRULAMALAR BAŞARILI! (Trend listeleri yavaş/hızlı küme fark etmeksizin eksiksiz sunuluyor)")

    # 6. Temizlik
    print("\n🧹 Test sonrası Redis kalıntıları temizleniyor...")
    await redis.srem("trending:listings", str(MOCK_SLOW_LISTING_ID), str(MOCK_BOTH_LISTING_ID))
    await redis.srem("trending:listings:velocity", str(MOCK_FAST_LISTING_ID), str(MOCK_BOTH_LISTING_ID))
    print("✅ Temizlik tamamlandı.")


if __name__ == "__main__":
    asyncio.run(run_test())
