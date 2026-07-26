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

- [x] **T02** — `mock_01_listings.json` üretildi (600 ilan)
  - 50 kullanıcı × 12 ilan, 8 kategori, Türkçe başlık + açıklama
  - Gerçekçi TL fiyatları, picsum.photos URL'leri, extra_fields dolu
  - Üretici: `generate_mock_data.py`

- [x] **T03** — `mock_02_user_interactions.json` üretildi (~4.200 event)
  - PostgreSQL `user_interactions` tablosuna gidecek (BPR bug fix sonrası doğru tablo)
  - Alanlar: user_id, listing_idx, item_type, interaction_type, duration_seconds, created_at
  - Grup A kullanıcıları %~70 vasıta etkileşimi (tutarlı davranış sinyali)

- [x] **T04** — `mock_03_user_interests.json` üretildi (230 satır)
  - PostgreSQL `user_interests` tablosuna gidecek
  - (user_id, category) unique — her kullanıcı × 5 kategori (E grubu 3)
  - Grup skorları: A→vasita 0.85, B→emlak 0.82, C→elektronik 0.80, D→giyim 0.65

- [x] **T05** — `mock_04_feed_analytics.json` üretildi (~2.570 satır)
  - ClickHouse `feed_analytics` tablosuna gidecek
  - click/impression/skip dağılımı; kendi grubunda click oranı yüksek

- [x] **T06** — `mock_05_search_events.json` üretildi (~480 satır)
  - ClickHouse `search_events` tablosuna gidecek
  - Grup-spesifik Türkçe arama sorguları

- [x] **T07** — `mock_06_swipe_live.json` üretildi (~294 satır)
  - ClickHouse `swipe_live_events` tablosuna gidecek
  - Stream ID 4-33 kullanıldı (T01 sonucu)

---

## FAZ 2 — Insert Scriptleri

- [ ] **T08** — `insert_01_listings.py` yaz
  - JSON okur, `asyncpg` ile PostgreSQL'e toplu INSERT
  - Çakışmada (ON CONFLICT user_id+title) satırı atlar
  - Insert sonrası üretilen ID'leri `listing_ids.json` olarak kaydeder (sonraki scriptler kullanır)
  - Çıktı: `✓ X ilan eklendi, Y atlandı`

- [ ] **T09** — `insert_02_user_interactions.py` yaz
  - `listing_ids.json`'dan listing ID'lerini okur (T08 çıktısı)
  - Mock JSON'daki listing_idx'leri gerçek ID'lerle eşleştirir
  - `user_interactions`'a toplu INSERT (listing_idx → item_id)
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

- [ ] **T16** — Adım 2: user_interactions insert et
  ```bash
  python documents/mock_data/insert_02_user_interactions.py
  ```
  Doğrulama:
  ```sql
  SELECT interaction_type, COUNT(*) FROM user_interactions
  WHERE created_at > NOW() - INTERVAL '1 hour'
  GROUP BY interaction_type;
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
