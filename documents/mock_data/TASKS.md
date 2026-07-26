# Mock Data — Görev Listesi

**Plan:** `PLAN.md`
**Kural:** Her task tamamlanınca bu dosyada işaretlenir. Insert taskları sıra ile çalışır — bir önceki bitmeden sonraki başlamaz.

---

## FAZ 1 — JSON Üretimi

### Ön Hazırlık

- [x] **T00** — BPR ve quality_service bug düzeltmesi
  - `bpr_service.py`: `analytics_events` → `user_interactions`, `event_type` → `interaction_type`
  - `quality_service.py`: 3 LEFT JOIN'de aynı düzeltme + `AND item_type = 'listing'` eklendi
  - **Neden:** `analytics_events` tablosunda `item_id`/`item_type` kolonu yoktu; doğru tablo `user_interactions`

- [x] **T01** — Stream ID'leri kontrol edildi + kategorileri güncellendi
  - Stream ID'leri: 4–33 (30 stream, hepsi `is_live=false`)
  - Kategoriler güncellendi: vasita(4-8), elektronik(9-13), emlak(14-18), giyim-aksesuar(19-23), spor-outdoor(24-28), diger(29-33)
  - T07'de kullanılacak stream ID'leri: 4–33

### JSON Dosyaları

- [ ] **T02** — `mock_01_listings.json` üret (600 ilan)
  - 50 kullanıcı, her biri 12 ilan
  - Grup dağılımı: PLAN.md'deki kullanıcı gruplarına göre
  - Her ilan: title, description, price, category, subcategory, condition, brand, model_name, extra_fields, location, image_url, image_urls, status, quality_score
  - 8 kategori, tüm subcategory'ler temsil edilmiş
  - Türkçe başlık ve açıklama (en az 1-2 ilgili cümle)
  - Gerçekçi TL fiyatları
  - picsum.photos seed URL'leri

- [ ] **T03** — `mock_02_analytics_events.json` üret (~5.000 event)
  - PostgreSQL `analytics_events` tablosuna gidecek
  - Alanlar: user_id, item_id (listing_id), item_type="listing", event_type, event_metadata, created_at
  - Event tipleri (BPR weight'leri): listing_impression (0.3), listing_view (1.0), listing_like (3.0), listing_favorite (5.0), listing_chat_open (6.0), listing_offer_submit (10.0), detail_dwell (2.0)
  - Grup davranışı: Vasıta grubundaki kullanıcılar ağırlıklı vasıta ilanlarıyla etkileşim
  - Zaman aralığı: Son 120 gün (BPR eğitim penceresi)
  - created_at: son 120 günde rastgele, son 30 güne doğru yoğunlaşan dağılım

- [ ] **T04** — `mock_03_user_interests.json` üret (~250 satır)
  - PostgreSQL `user_interests` tablosuna gidecek
  - Alanlar: user_id, category, subcategory (NULL veya değer), score
  - Her kullanıcı için: 2-3 top-level category skoru + 3-4 subcategory skoru
  - Grup A: vasita (score 0.85), vasita|otomobil (0.75), vasita|motosiklet (0.35)
  - Grup B: emlak (0.82), emlak|daire (0.70), emlak|mustakil-ev-villa (0.40)
  - Grup C: elektronik (0.80), elektronik|cep-telefonu (0.72), elektronik|bilgisayar-laptop (0.45)
  - Grup D: giyim-aksesuar (0.60), spor-outdoor (0.55), giyim-aksesuar|kadin-giyim (0.50)
  - Grup E: tüm skorlar 0.05–0.25 arası düşük (cold-start)

- [ ] **T05** — `mock_04_feed_analytics.json` üret (~3.000 satır)
  - ClickHouse `feed_analytics` tablosuna gidecek
  - Alanlar: timestamp, user_id (String), listing_id (String), event_type, dwell_time_ms, slot_index, listing_subcategory
  - Event tipleri: impression, click, skip
  - Dwell time: click → 5.000-30.000ms, impression → 1.000-8.000ms, skip → 0-500ms
  - Grup davranışı: click oranı kendi grubunun ilgi alanında yüksek
  - Zaman aralığı: Son 30 gün (ALS eğitim penceresi)

- [ ] **T06** — `mock_05_search_events.json` üret (~600 satır)
  - ClickHouse `search_events` tablosuna gidecek
  - Alanlar: timestamp, user_id (Nullable UInt32), query, category, subcategory, result_count, intent
  - Query örnekleri: "sedan araba", "2+1 daire kiralık", "iPhone 15", "bisiklet"
  - Intent: browse / buy / compare
  - Grup davranışı: Vasıta grubu "araba", "otomobil" gibi sorgular atar
  - Zaman aralığı: Son 30 gün

- [ ] **T07** — `mock_06_swipe_live.json` üret (~300 satır) *(T01 sonucuna bağlı)*
  - ClickHouse `swipe_live_events` tablosuna gidecek
  - Alanlar: user_id, stream_id, listing_id, event_type, dwell_ms, stream_category, stream_subcategory, listing_category, listing_subcategory, timestamp
  - Event tipleri: dwell, skip, stream_heart
  - Stream varsa: T01'den alınan ID'ler kullanılır
  - Stream yoksa: Bu task skip edilir

---

## FAZ 2 — Insert Scriptleri

- [ ] **T08** — `insert_01_listings.py` yaz
  - JSON okur, `asyncpg` ile PostgreSQL'e toplu INSERT
  - Çakışmada (ON CONFLICT user_id+title) satırı atlar
  - Insert sonrası üretilen ID'leri `listing_ids.json` olarak kaydeder (sonraki scriptler kullanır)
  - Çıktı: `✓ X ilan eklendi, Y atlandı`

- [ ] **T09** — `insert_02_analytics_events.py` yaz
  - `listing_ids.json`'dan listing ID'lerini okur (T08 çıktısı)
  - Mock JSON'daki listing sıra numaralarını gerçek ID'lerle eşleştirir
  - `analytics_events`'e toplu INSERT
  - Çıktı: `✓ X event eklendi`

- [ ] **T10** — `insert_03_user_interests.py` yaz
  - Mevcut kayıt varsa `ON CONFLICT DO UPDATE SET score = EXCLUDED.score`
  - Çıktı: `✓ X satır upsert edildi`

- [ ] **T11** — `insert_04_feed_analytics.py` yaz
  - ClickHouse bağlantısı: `clickhouse_connect` veya `httpx` ile HTTP interface
  - `listing_ids.json`'dan ID eşleştirmesi
  - Batch INSERT (1.000 satır/batch)
  - Çıktı: `✓ X feed_analytics satırı eklendi`

- [ ] **T12** — `insert_05_search_events.py` yaz
  - ClickHouse'a batch INSERT
  - Çıktı: `✓ X search_events satırı eklendi`

- [ ] **T13** — `insert_06_swipe_live.py` yaz *(T07 skip değilse)*
  - ClickHouse'a batch INSERT
  - Çıktı: `✓ X swipe_live_events satırı eklendi`

---

## FAZ 3 — VPS Uygulama

*Her adımı sırayla VPS'te çalıştır. Backend dizininde (`/var/www/teqlif.com/backend`).*

- [ ] **T14** — Script ve JSON dosyalarını VPS'e aktar
  - `git pull` ile (dosyalar repo'ya eklenirse)
  - Veya `scp` ile doğrudan transfer

- [ ] **T15** — Adım 1: Listings insert et
  ```bash
  python documents/mock_data/insert_01_listings.py
  ```
  Doğrulama:
  ```sql
  SELECT category, subcategory, COUNT(*) FROM listings
  WHERE created_at > NOW() - INTERVAL '1 hour'
  GROUP BY category, subcategory ORDER BY COUNT(*) DESC;
  ```

- [ ] **T16** — Adım 2: analytics_events insert et
  ```bash
  python documents/mock_data/insert_02_analytics_events.py
  ```
  Doğrulama:
  ```sql
  SELECT event_type, COUNT(*) FROM analytics_events
  WHERE created_at > NOW() - INTERVAL '1 hour'
  GROUP BY event_type;
  ```

- [ ] **T17** — Adım 3: user_interests insert et
  ```bash
  python documents/mock_data/insert_03_user_interests.py
  ```
  Doğrulama:
  ```sql
  SELECT user_id, category, subcategory, score FROM user_interests
  WHERE user_id IN (1, 16, 27, 390, 400) ORDER BY user_id, score DESC;
  ```

- [ ] **T18** — Adım 4: feed_analytics insert et
  ```bash
  python documents/mock_data/insert_04_feed_analytics.py
  ```
  Doğrulama (ClickHouse):
  ```sql
  SELECT listing_subcategory, count() FROM feed_analytics
  WHERE timestamp >= now() - INTERVAL 1 HOUR GROUP BY listing_subcategory;
  ```

- [ ] **T19** — Adım 5: search_events insert et
  ```bash
  python documents/mock_data/insert_05_search_events.py
  ```

- [ ] **T20** — Adım 6: swipe_live_events insert et *(opsiyonel)*
  ```bash
  python documents/mock_data/insert_06_swipe_live.py
  ```

---

## FAZ 4 — ML Modelleri Tetikle

*VPS'te ARQ worker üzerinden veya doğrudan Python ile.*

- [ ] **T21** — Quality model eğit
  ```bash
  python -c "
  import asyncio
  from app.services.ml.quality_service import train_quality_model
  # db_session gerekli — worker üzerinden tetikle
  "
  ```
  Veya ARQ worker'a enqueue et.

- [ ] **T22** — Feed ALS eğit
  ```bash
  python -c "
  import asyncio, redis.asyncio as aioredis
  r = aioredis.from_url('redis://localhost')
  asyncio.run(r.execute_command('ARQJOB', 'train_feed_als_task'))
  "
  ```

- [ ] **T23** — BPR eğit
  - ARQ worker'dan `train_bpr_task` enqueue

- [ ] **T24** — K-Means eğit
  - ARQ worker'dan `train_kmeans_task` enqueue

- [ ] **T25** — SwipeLive ALS eğit *(swipe_live_events varsa)*
  - ARQ worker'dan `train_swipe_live_als_task` enqueue

---

## FAZ 5 — Doğrulama

- [ ] **T26** — Redis vektörlerini kontrol et
  ```bash
  redis-cli keys "feed:als:user_vec:*" | wc -l   # > 0 olmalı
  redis-cli keys "bpr:rec:*" | wc -l              # > 0 olmalı
  redis-cli keys "ch_affinity:*" | wc -l          # kullanıcılar feed istedikçe dolar
  ```

- [ ] **T27** — Feed kalitesi test et
  - Grup A kullanıcısı (örn. user_id=1) için feed isteği gönder
  - Dönen ilanların büyük çoğunluğu vasıta olmalı
  - Grup E kullanıcısı (user_id=400) için feed isteği gönder
  - Cold-start → çeşitli kategorilerden ilan gelmeli

- [ ] **T28** — Price estimate test et
  - Bir vasıta ilanı için `/price-estimate` çağır
  - `subcategory` + `extra_fields` ile sonuç makul aralıkta mı?

- [ ] **T29** — TASKS.md güncelle, tamamlanan taskları işaretle
