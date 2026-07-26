# Mock Data — Plan

Son güncelleme: 2026-07-26

---

## Amaç

ML pipeline'ının (ALS, BPR, K-Means, Quality) anlamlı sinyal öğrenebilmesi için
gerçekçi, tutarlı davranış kalıpları içeren seed verisi üretmek.

Gerçek veri birikene kadar modeller bu mock data üzerinde ilk eğitimlerini yapar.

---

## Kullanıcı Grupları (50 kullanıcı)

Mevcut kullanıcı ID'leri iki kümede: 1–32 arası (26 kullanıcı) ve 386–488 arası.
Her grup bir ağırlıklı ilgi alanına sahiptir; ancak yüzde olarak diğer kategorilerde
de küçük miktarda etkileşim yapabilir (gerçekçilik için).

| Grup | İD'ler | Kişi | Ağırlıklı Kategori | İkincil Kategori |
|------|--------|------|--------------------|-----------------|
| A — Vasıta | 1, 2, 3, 4, 5, 6, 10, 11, 12, 13 | 10 | vasita → otomobil, motosiklet | elektronik |
| B — Emlak | 16, 17, 19, 20, 21, 22, 23, 24, 25, 26 | 10 | emlak → daire, mustakil-ev-villa | ev-yasam |
| C — Elektronik | 27, 28, 29, 30, 31, 32, 386, 387, 388, 389 | 10 | elektronik → cep-telefonu, bilgisayar-laptop | kitap-hobi |
| D — Giyim & Spor | 390, 391, 392, 393, 394, 395, 396, 397, 398, 399 | 10 | giyim-aksesuar + spor-outdoor | diger |
| E — Cold-start | 400, 401, 402, 403, 404, 405, 406, 407, 408, 409 | 10 | karışık (yeni kullanıcı simülasyonu) | — |

**Cold-start grubu (E):** Az ve dağınık etkileşim → ALS centroid fallback'in test edilmesi için.

---

## Dosya & Insert Sırası

```
ADIM 1 → mock_01_listings.json          → PostgreSQL: listings tablosu
ADIM 2 → mock_02_analytics_events.json  → PostgreSQL: analytics_events tablosu (BPR + Quality)
ADIM 3 → mock_03_user_interests.json    → PostgreSQL: user_interests tablosu (feed affinity seed)
ADIM 4 → mock_04_feed_analytics.json    → ClickHouse: feed_analytics tablosu (Feed ALS)
ADIM 5 → mock_05_search_events.json     → ClickHouse: search_events tablosu
ADIM 6 → mock_06_swipe_live.json        → ClickHouse: swipe_live_events tablosu (SwipeLive ALS)
```

**Sıra kritik:** listings önce gitmeli çünkü event dosyaları listing ID'lerine referans verir.
Her adım için ayrı bir Python insert scripti yazılacak.

---

## Hedef Hacimler

| Dosya | Hedef Satır | Minimum (ML eşiği) | Açıklama |
|-------|------------|---------------------|----------|
| listings | 600 | — | 50 kullanıcı × 12 ilan |
| analytics_events | 5.000 | 200 (BPR) | tıklama, favori, chat, impression |
| user_interests | 250 | — | kullanıcı başı 3-6 category/subcategory skoru |
| feed_analytics | 3.000 | 50 (ALS) | click, impression, skip, dwell |
| search_events | 600 | — | kategori + subcategory bazlı aramalar |
| swipe_live_events | 300 | 10 (ALS) | dwell, skip, heart (stream ID gerekli) |

---

## İlan Dağılımı (600 ilan, 8 kategori)

| Kategori | İlan | Temsil edilen subcategory'ler |
|----------|------|-------------------------------|
| vasita | 110 | otomobil, motosiklet, elektrikli-arac, kamyonet-minibus, vasita-yedek-parca |
| emlak | 100 | daire, mustakil-ev-villa, arsa, is-yeri-ofis |
| elektronik | 100 | cep-telefonu, bilgisayar-laptop, tablet, tv-monitor, oyun-konsolu |
| giyim-aksesuar | 70 | kadin-giyim, erkek-giyim, ayakkabi, canta-cuzdan, saat |
| ev-yasam | 70 | mobilya, beyaz-esya (bu subcategory elektronik altında ama ilan var), mutfak-pisirme |
| spor-outdoor | 60 | bisiklet, fitness-spor-salonu, outdoor-kamp, takim-sporlari |
| kitap-hobi | 50 | roman-hikaye, muzik-aleti, koleksiyon, ders-kitabi-akademik |
| diger | 40 | evcil-hayvan, oyuncak-cocuk-oyun, saglik-guzellik |

Her ilan zorunlu alanları içerir:
- `title`: 10-80 karakter, açıklayıcı
- `description`: en az 1-2 kategoriyle ilgili cümle
- `price`: gerçekçi TL fiyatı
- `category`, `subcategory`, `condition`
- `brand`, `model_name`: kategori uygunsa dolu
- `extra_fields`: araç için km/yıl/yakıt/vites, emlak için oda/m²/kat, elektronik için ram/depolama
- `location`: Türkiye'nin büyük şehirleri (İstanbul, Ankara, İzmir, Bursa, Antalya)
- `image_url`, `image_urls`: picsum.photos seed URL'leri
- `status`: "active"
- `quality_score`: rule-based ön hesap (0.4–0.9 arası)

---

## Görsel URL Formatı

```
image_url:   https://picsum.photos/seed/{kategori}{sıra}/800/600
image_urls:  ["https://picsum.photos/seed/{kategori}{sıra}/800/600",
              "https://picsum.photos/seed/{kategori}{sıra}b/800/600",
              "https://picsum.photos/seed/{kategori}{sıra}c/800/600"]
```

Örnek: `https://picsum.photos/seed/car42/800/600`

---

## Davranış Tutarlılığı Kuralları

1. **Grup A kullanıcısı (Vasıta):**
   - İlanlarının %70'i vasıta kategorisinde
   - analytics_events'te tıkladığı/favorilediği ilanların %70'i vasıta
   - feed_analytics'te uzun dwell süresi vasıta ilanlarında
   - user_interests'te `vasita|otomobil` en yüksek skor

2. **Grup B kullanıcısı (Emlak):**
   - Benzer şekilde emlak odaklı

3. **Grup C (Elektronik):**
   - Elektronik odaklı, özellikle cep-telefonu ve bilgisayar

4. **Grup D (Giyim & Spor):**
   - Giyim ve spor arası dağılmış

5. **Grup E (Cold-start):**
   - Toplam etkileşim sayısı 10'un altında (ALS min eşiğini zorlamak için)
   - Rastgele kategori dağılımı

---

## Swipe Live Ön Koşul

`swipe_live_events` için geçerli `stream_id` gerekli.
Insert adımından önce VPS'teki mevcut stream ID'leri kontrol edilmeli:

```sql
SELECT id, title, category, subcategory, status FROM live_streams LIMIT 20;
```

Stream yoksa:
- Ya mock stream eklenir (users tablosundaki bir kullanıcıya bağlı)
- Ya da bu adım skip edilir ve gerçek stream verisi birikene kadar beklenir

---

## Insert Script Yapısı

Her script aynı kalıbı izler:

```python
#!/usr/bin/env python3
"""
mock_insert_0X_xxxx.py — Açıklama
Çalıştırma: python mock_insert_0X_xxxx.py
VPS'te backend dizininde çalıştırılmalı.
"""
import json, asyncio
from pathlib import Path

DATA_FILE = Path(__file__).parent / "mock_0X_xxxx.json"
DB_URL = "postgresql+asyncpg://teqlif:Teqlif5664@127.0.0.1:5432/teqlif"

async def main():
    data = json.loads(DATA_FILE.read_text())
    # ... insert logic ...
    print(f"✓ {len(data)} satır eklendi")

asyncio.run(main())
```

---

## Sonraki Adımlar (mock data sonrası)

1. ML iş kuyruğunu tetikle (ARQ worker):
   - `train_quality_model_task`
   - `train_feed_als_task`
   - `train_bpr_task`
   - `train_kmeans_task`
   - `train_swipe_live_als_task`

2. Redis'te vektörlerin oluştuğunu doğrula:
   - `feed:als:user_vec:{uid}` → var mı?
   - `bpr:rec:{uid}` → var mı?

3. Feed endpoint'ini test et:
   - Grup A kullanıcısı → vasıta ilanları üstte mi?
   - Grup E kullanıcısı → cold-start çalışıyor mu?
