# Teqlif VPS Kurulum — Görev Takibi

**Hedef VPS:** `135.125.175.223`  
**Başlangıç:** 2026-09-02  
**Durum:** ✅ Tamamlandı

> Her adımı tamamladıktan sonra çıktıyı paylaş → birlikte doğrulayıp bir sonraki adıma geçeceğiz.

---

## Faz 1 — Sistem Kurulumu

- [x] **1.1** `apt update && apt upgrade -y` + gerekli paketler kuruldu
- [x] **1.2** Python 3.13.5 kurulu (Debian 13 trixie native)
- [x] **1.3** Dizin yapısı oluşturuldu (`uploads/`, `backend/logs/`, `backend/certificates/`, `/var/backups/redis`)
- [x] **1.4** UFW güvenlik duvarı kuralları → aktif, SSH/HTTP/HTTPS/LiveKit/TURN/Grafana kuralları uygulandı
- [x] **1.5** Fail2ban → aktif, 3 jail: `nginx-botscan`, `nginx-req-limit`, `sshd`

## Faz 2 — Servis Kurulumları

- [x] **2.1** PostgreSQL 17 + pgvector kuruldu, online
- [x] **2.1b** DB `teqlif` ve kullanıcı oluşturuldu, `vector` + `pg_trgm` extension'ları aktif
- [x] **2.2** Redis 8.0.2 kuruldu, eski VPS config kopyalandı, `redis-cli ping` → PONG
- [x] **2.3** ClickHouse 26.9.1.530 kuruldu, systemd unit eski VPS'ten kopyalandı, aktif
- [x] **2.4** MinIO kuruldu, systemd aktif, `teqlif` bucket oluşturuldu
- [x] **2.5** Nginx kuruldu, config kopyalandı, SSL sertifikaları aktarıldı, `nginx -t` başarılı

## Faz 3 — Uygulama Kurulumu

- [x] **3.1** Git repo klonlandı (`/var/www/teqlif.com`)
- [x] **3.2-git** Git SSH kuruldu, ownership düzeltildi, `git pull` çalışıyor
- [x] **3.2** venv oluşturuldu, `pip install -r requirements.txt` tamamlandı (hatasız)
- [x] **3.3** `.env` oluşturuldu, `chmod 600` uygulandı, `APNS_USE_SANDBOX=False`
- [x] **3.4** Sertifika dosyaları kopyalandı (`AuthKey_C2PL2A2P6X.p8`, `voip_cert.pem`, `firebase-service-account.json`)
- [x] **3.5** DB şeması eski VPS'ten `pg_dump --schema-only` ile alındı, uygulandı, `alembic stamp head` ile işaretlendi
- [x] **3.5b** Tüm production verisi (`pg_dump --data-only`) eski VPS'ten aktarıldı — 8 kullanıcı, 12020 çeviri, 970 ilçe, 59 alt kategori
- [x] **3.6** Systemd unit'leri kuruldu ve enable edildi (teqlif, workers, redis-backup.timer, PartOf override'ları)

## Faz 4 — LiveKit

- [x] **4.1** LiveKit 1.13.3 binary eski VPS'ten kopyalandı
- [x] **4.2** `/etc/livekit/livekit.yaml` kopyalandı, `node_ip` → `135.125.175.223`
- [x] **4.3** Systemd unit kuruldu, `livekit` kullanıcısı oluşturuldu, servis aktif

## Faz 5 — Nginx + SSL

- [x] **5.1** Nginx config eski VPS'ten kopyalandı (`teqlif.com` + `live.teqlif.com`)
- [x] **5.2** SSL sertifikaları eski VPS'ten kopyalandı (`/etc/letsencrypt/`)
- [x] **5.3** `nginx -t` başarılı, reload yapıldı

## Faz 6 — Monitoring (Opsiyonel)

- [x] **6.1** Loki 3.6.7 kuruldu, aktif
- [x] **6.2** Promtail 3.0.0 kuruldu, aktif
- [x] **6.3** Grafana 13.2.0 kuruldu, aktif, grafana.db eski VPS'ten kopyalandı, ClickHouse plugin kuruldu
- [x] **6.4** Prometheus 2.51.0 kuruldu, aktif
- [x] **6.5** node_exporter 1.8.2 kuruldu, aktif
- [x] **6.6** prometheus-postgres-exporter 0.17.1 kuruldu, pg_up=1, Unix socket bağlantısı
- [x] **6.7** Promtail config kopyalandı, GeoIP DB aktarıldı, aktif — tüm log panelleri çalışıyor

## Faz 6.5 — Squarespace DNS Yönetimi

- [x] **DNS.1** DNS Cloudflare üzerinden yönetiliyor (Squarespace değil)
- [x] **DNS.2** TTL — zaten 1 saat, trafik olmadığından direkt cutover yapıldı
- [x] **DNS.3** A kayıtları `135.125.175.223`'e güncellendi (Cloudflare dashboard):
  - `teqlif.com` (Proxied)
  - `www.teqlif.com` (CNAME → teqlif.com, Proxied)
  - `live.teqlif.com` (DNS only — WebRTC için)
- [x] **DNS.4** Yayılma doğrulandı, `curl https://teqlif.com/api/health` → 200 OK

> ⚠️ DNS cutover öncesi yeni VPS'teki tüm servisler çalışır durumda olmalı.

## Faz 7 — Canlıya Alma

- [x] **7.1** DNS direkt cutover yapıldı (trafik olmadığından TTL beklenmedi)
- [x] **7.2** Tüm servisler başlatıldı (teqlif, teqlif-worker, teqlif-worker-critical, livekit, minio, redis, postgresql, clickhouse)
- [x] **7.3** DNS A kayıtları Cloudflare'den güncellendi
- [x] **7.4** `curl https://teqlif.com/api/health` → 200 OK
- [x] **7.5** SSL sertifikaları geçerli, certbot.timer aktif (otomatik yenileme)

## Faz 8 — Dış Servis Kontrolleri

- [x] **8.1** Firebase service account → loglardan doğrulandı (`[FirebaseAdapter] hazır | project=teqlif-a24ee`)
- [ ] **8.2** APNs → production test (uygulama ile doğrulanacak)
- [x] **8.3** Brevo SPF kaydı temiz (`include:spf.brevo.com`, eski IP yok)
- [ ] **8.4** LiveKit bağlantı testi (uygulama ile doğrulanacak)

---

---

## Geliştirme Workflow'u

Her task için sıra şu şekildedir:
1. **Plan sun** — implementasyon öncesi ne yapılacağını özetle
2. **Onay bekle** — kullanıcı onaylamadan implementasyona geçme
3. **Implement et** — kodu yaz
4. **Task'ı tamamlandı işaretle** — `[ ]` → `[x]`
5. **Commit at** — açıklayıcı mesajla
6. **Commit hash'ini task'a yaz** — `[x] **9.1** ... _(commit: abc1234)_`

---

## Faz 9 — Referans Veri & Deploy Pipeline Refactor

**Hedef:** `main.py` lifespan'inden tüm seed verisini kaldır. Tek kaynak mimarisini tamamla.

### 9.1 JSON Dosyalarına `meta` Bölümü Ekle

Her `documents/categorization/*.json` dosyasına `meta` bölümü eklenir:

```json
{ "category": "vehicles", "meta": { "sort_order": 1, "is_listable": true }, "subcategories": {...} }
```

**Kararlar:**
- `meta` sadece `sort_order` ve `is_listable` içerir — `label` yok.
- Label OTA'dan gelir (`cat_{key}` → translations tablosu). DB `label` kolonu boş bırakılır.
- Analiz: DB label sadece `/api/categories`'de son fallback olarak kullanılıyor; OTA'da tüm `cat_*` key'leri mevcut → DB label hiç devreye girmiyor.
- ClickHouse, ML, feed, listing, search → yalnızca `key` kullanıyor, label'a bakmıyor.

| Dosya | sort_order | is_listable |
|-------|-----------|------------|
| `electronics.json` | 0 | true |
| `vehicles.json` | 1 | true |
| `real_estate.json` | 2 | true |
| `fashion.json` | 3 | true |
| `sports.json` | 4 | true |
| `books.json` | 5 | true |
| `home.json` | 6 | true |
| `other.json` | 7 | true |
| `chat.json` (yeni) | 99 | false |

- [x] **9.1** 8 mevcut JSON dosyasına `meta` bölümü ekle _(commit: c66d07d9)_
- [x] **9.2** `documents/stream/stream_categories.json` oluştur (`chat` stream-only kategorisi) _(commit: 0ea4f8d4)_

**9.2 Kararlar:**
- `chat` `documents/categorization/` içine **girmez** — listing kategorisi değil, stream-only
- `documents/stream/stream_categories.json` → `[{"key": "chat", "sort_order": 99}]`
- İleride yeni stream-only kategori = bu dosyaya satır ekle, başka değişiklik yok
- `is_listable` flag tamamen kaldırıldı — context endpoint ile ayrım yapılır
- Backend `/api/categories?context=stream` → listing kategorileri + stream_categories.json birleşimi döner
- İlan Ver `/api/categories` (context yok) → sadece listing kategorileri, chat yok
- Canlı sayfası filtreleri aktif yayınlardan türetilir (değişmez)
- Yayın Aç modal `/api/categories?context=stream` çağırır

### 9.2 `sync_category_fields.py` Genişlet

Script, JSON dosyalarını tararken önce `meta` bölümünden kategoriyi upsert eder, sonra subcategory/field sync'ini yapar.

**Kararlar:**
- `sync_categories()` yeni async fonksiyon olarak aynı dosyaya eklenir — ayrı dosya değil; JSON'u iki kez okumaya gerek yok, kategoriler ve alanlar her zaman birlikte çalışır
- `label` değeri `key` string'i olarak set edilir (`nullable=False` kısıtı nedeniyle boş bırakılamaz); OTA her zaman üstüne yazar, bu değer hiç görüntülenmez
- JSON'da olmayan DB kategorileri `PASSIVE` yapılır — silinmez, veri kaybı riski yok
- `sync_categories()` → `sync_fields()` sırasıyla çalışır (önce kategori, sonra alan sync)
- Her ikisi de ayrı DB session'ı kullanır; bağımsız ve idempotent

- [x] **9.3** `sync_category_fields.py`'ye `sync_categories()` fonksiyonu ekle (meta → categories tablosu upsert, önce çalışır) _(commit: 8c9b24cf)_
- [x] **9.4** VPS test: `python3 scripts/sync_category_fields.py` — 8 kategori upsert, 198 field, 1450 option, hata yok ✓

### 9.3 `Turkiye.json` Oluştur

`documents/international/countries/Turkiye.json` — ülke → il (state) → ilçe (district) yapısı. Source of truth.

```json
{
  "country": "Türkiye",
  "code": "TR",
  "sort_order": 1,
  "states": [
    {
      "code": "TR-34",
      "name": "İstanbul",
      "sort_order": 34,
      "districts": [
        { "name": "Adalar", "sort_order": 1 },
        { "name": "Arnavutköy", "sort_order": 2 }
      ]
    }
  ]
}
```

**Kararlar:**
- `documents/international/countries/` dizini source of truth — `sync_locations.py` sadece bu dizine bakar, dosya varsa DB'ye yazar, yoksa PASSIVE yapar. Script hiçbir dış API bilmez.
- Yeni ülke eklemek = dizine yeni JSON dosyası koymak; script otomatik alır.
- `code` alanı: ülke için ISO 3166-1 alpha-2 (`TR`), il için ISO 3166-2 (`TR-34`)
- `sort_order` il için plaka numarası — mevcut sistemle uyumlu, Türkiye'de standart
- Tüm 81 il ve mevcut 970 ilçe bu dosyaya taşınır; veri kaynağı mevcut DB dump'ı (yeniden API'den çekilmez)
- Aynı pattern `sync_category_fields.py`'nin `documents/categorization/*.json` ile kullandığı yaklaşımın birebiri

**9.3 Ek Kararlar:**
- `district.sort_order` yok — API zaten `ORDER BY name` (alfabetik) kullanıyor; 970 ilçeye anlamlı sıra vermek mümkün değil
- `state.sort_order` var — plaka numarası; app-specific ama Türkiye'de bilinir, mevcut DB ile uyumlu, endüstri standardı değil ama bilinçli tercih
- `country.sort_order` var — ileride "Türkiye ilk gelsin" gibi tercihe olanak tanır; kaldırmak migration gerektirir
- Çok dilli ad (`name_en` vb.) şimdilik yok — yer adları proper noun, çeviri gerektirmez
- JSON yapısı ISO 3166 uyumlu (`code: "TR"`, `code: "TR-34"`)

- [x] **9.5** `documents/international/countries/Turkiye.json` oluştur — 81 il, 971 ilçe, ISO TR ✓ commit: 7942ec11

### 9.4 DB Şeması Refactor — Uluslararası Lokasyon Modeli

Mevcut `cities` tablosu `states` olarak rename edilir. `countries` tablosu eklenir. `listings` ve `users` tablolarına `country_id` eklenir.

**Kararlar:**
- `cities` → `states`: uluslararası terminoloji (ISO standardı); 0 gerçek kullanıcı, 3 ilan — kırılma riski kabul edilebilir
- **`country_code` (VARCHAR 2, ISO 3166-1 alpha-2) integer FK yerine kullanılır** — `countries.code` PK olur, `listings.country_code`, `states.country_code` string referans taşır; JOIN gerektirmez, API/ClickHouse/Redis'te anlamlı okunur
- `countries` tablosu: `code` (VARCHAR 2 PK), `sort_order`, `is_active` — `name` kolonu yok; ülke adı `babel` kütüphanesiyle türetilir
- **`babel` (BSD 3-Clause, ücretsiz, ticari kullanım serbest)** `requirements.txt`'e eklenir; `Locale('tr').territories['TR']` → "Türkiye", `Locale('ru').territories['TR']` → "Турция"
- Separation of concerns: **migration = şema + NOT NULL için minimum seed, sync_locations.py = tüm lokasyon verisi**
- `listings.country_code` ve `states.country_code` → **NOT NULL** — migration'da nullable ekle → backfill `'TR'` → NOT NULL kısıtı
- Migration minimum seed: `INSERT INTO countries (code, sort_order, is_active) VALUES ('TR', 1, true)`
- `sync_locations.py` Turkey'yi tekrar upsert eder (`ON CONFLICT (code) DO NOTHING`) — idempotent
- `users.country_code` nullable (VARCHAR 2) — Faz 10'da UI'dan set edilecek, backfill yapılmaz
- `districts.city_id` → `districts.state_id` rename
- asyncpg kuralı: her `op.execute()` tek SQL statement

Migration `zzzzm_intl_location.py` sırası:
1. `countries` tablosu oluştur (`code` VARCHAR 2 PK)
2. Turkey minimal seed (`INSERT INTO countries (code, sort_order, is_active) VALUES ('TR', 1, true)`)
3. `cities` → `states` rename
4. `states.country_code` VARCHAR 2 nullable ekle → backfill `'TR'` → NOT NULL
5. `districts.city_id` → `state_id` rename
6. `listings.country_code` VARCHAR 2 nullable ekle → backfill `'TR'` → NOT NULL
7. `users.country_code` VARCHAR 2 nullable ekle (backfill yok)

- [x] **9.6** Alembic migration `zzzzm_intl_location.py` yaz ✓ commit: 3dac22d5
- [x] **9.7** VPS DB'de test: `alembic upgrade head` → zzzzm_intl_location uygulandı, countries TR/Türkiye seed doğru ✓

### 9.4b `bootstrap.py` — Sıfırdan DB Kurulumu

Yeni bir ortam (developer makinesi, yeni VPS, CI) için tek komutla doğru DB oluşturur. Mevcut ortamlar (VPS, staging) bu scripti kullanmaz — onlar `alembic upgrade head` kullanır.

**Kararlar:**
- SQLAlchemy modelleri şemanın source of truth'u — `Base.metadata.create_all()` modelleri okur, tüm tabloları tek adımda oluşturur
- Alembic migration'lar incremental değişiklik geçmişidir; yeni DB'de tekrar oynatılmaz
- Model değişikliği ve Alembic migration her zaman birlikte üretilir (geliştirme Claude üzerinden yürütüldüğünden ayrı bir kural gerektirmez)
- `bootstrap.py` sonunda `alembic stamp head` çalışır → Alembic "zaten son versiyondayım" bilgisini alır

`bootstrap.py` akışı:
```
1. Base.metadata.create_all(engine)   ← tüm tablolar modellerden oluşur
2. alembic stamp head                 ← migration geçmişi işaretlenir
3. sync_main()                        ← kategori, lokasyon, çeviri verisi yüklenir
```

| Ortam | Komut |
|-------|-------|
| Yeni DB (sıfırdan) | `python bootstrap.py` |
| Mevcut DB (VPS/staging) | `alembic upgrade head` → restart → `sync_main.py` |

- [x] **9.7b** `backend/scripts/bootstrap.py` oluştur ✓ commit: 86c7c9bd

### 9.5 Backend Rename: `City` → `State`

Model, router ve use case katmanlarında `City`/`city`/`cities` → `State`/`state`/`states`.

**Etkilenen dosyalar (11 adet):**

| Dosya | Değişiklik |
|-------|-----------|
| `app/models/city.py` | → `state.py`, `City` → `State` |
| `app/models/district.py` | `city_id` → `state_id`, `City` import kaldır |
| `app/models/__init__.py` | `City` → `State` import |
| `app/routers/cities.py` | → `states.py`, endpoint prefix `/cities` → `/states` |
| `app/routers/analytics.py` | `City` import → `State` |
| `app/worker.py` | `City` referansları → `State` |
| `app/routers/auth.py` | `City`/`city` referansları → `State`/`state` |
| `app/utils/migration_utils.py` | `City` referansları → `State` |
| `app/utils/schema_cache.py` | `City` referansları → `State` |
| `app/use_cases/listings/queries/listing_utils.py` | `city` → `state` field referansları |
| `app/use_cases/feed/queries/feed_queries.py` | `city` → `state` field referansları |

- [x] **9.8** Backend rename: City→State, /api/cities→/api/states, eski dosyalar silindi ✓ commit: 49f2a6f9

### 9.6 `sync_locations.py` Oluştur

`documents/international/countries/*.json` → `countries` + `states` + `districts` tabloları. Idempotent.

**Kararlar:**
- Country tanımlayıcı: `code` (TR, US...) — upsert `ON CONFLICT (code)`; `code` PK olduğundan integer id lookup yok
- State tanımlayıcı: `code` (TR-34...) — upsert `ON CONFLICT (code)`
- District tanımlayıcı: `state_id + name` — bu combination unique; "Merkez" birçok ilde var, il+ad birlikte tekil
- JSON'da olmayan state/district → **hard delete** (pasife alma yok — veri çöplüğü oluşmaz)
- Hard delete korumalı: o state/district'e bağlı ilan varsa silme, log'a yaz (`"Kadıköy silinemedi — 3 aktif ilan var"`); ilan silindiğinde kayıt da temizlenir
- Listings backfill: `UPDATE listings SET country_code = 'TR' WHERE country_code IS NULL`
- Ülke adı türetme: `babel.Locale(lang).territories[country_code]` — DB'de name kolonu yok

**Sync sırası:**
1. `countries/*.json` dosyalarını tara
2. Her dosya için `Country` upsert (code üzerinden)
3. Her `state` için `State` upsert (code üzerinden, country_id ile)
4. Her `district` için `District` upsert (state_id + name üzerinden)
5. JSON'da olmayan district → ilan kontrolü → güvenli ise sil, değilse logla
6. JSON'da olmayan state → ilan/district kontrolü → güvenli ise sil, değilse logla
7. `listings` backfill (country_id NULL olanları Turkey ile doldur)

- [x] **9.9** `backend/scripts/sync_locations.py` oluştur ✓ commit: 4da5b254

### 9.7 `sync_main.py` Oluştur

Tüm sync işlemlerinin merkezi orchestrator'ı. `ExecStartPre` ile çağrılır.

```
backend/scripts/
  ├── sync_main.py            ← Orchestrator
  ├── sync_category_fields.py ← JSON meta → categories + fields
  ├── sync_locations.py       ← countries JSON → countries + states + districts
  └── sync_translations.py    ← ARB → translations
```

`sync_main.py` çalışma sırası:
1. `alembic upgrade head` — schema migration (idempotent)
2. `sync_category_fields` — kategori + alan sync
3. `sync_locations` — lokasyon sync
4. `sync_translations` — çeviri sync

- [x] **9.10** `backend/scripts/sync_main.py` oluştur ✓ commit: e7691731

### 9.8 Systemd Güncelle

`teqlif.service` ve `teqlif-staging.service` dosyalarına `ExecStartPre` ekle:

```ini
ExecStartPre=/var/www/teqlif.com/venv/bin/python3 /var/www/teqlif.com/backend/scripts/sync_main.py
```

- [x] **9.11** VPS'te `teqlif.service`'e `ExecStartPre` eklendi ✓
- [ ] **9.12** VPS'te `teqlif-staging.service`'e `ExecStartPre` ekle (varsa)
- [x] **9.13** `sudo systemctl daemon-reload && sudo systemctl restart teqlif` ✓
- [x] **9.14** `journalctl` — alembic OK, 8 kategori, 198 field, 81 il, ilçeler sync ✓

### 9.9 `main.py` Temizle

- [x] **9.15** `_SEED_CATEGORIES`, `_SEED_CITIES`, seed fonksiyonları, create_all bloğu kaldırıldı ✓ commit: 2b39048d
- [x] **9.16** lifespan'den seed çağrıları kaldırıldı (9.15 ile) ✓
- [x] **9.17** `ast.parse(main.py)` → OK ✓

### 9.10 Flutter Rename: `city` → `state`

`city_service.dart` → `state_service.dart`. Tüm modellerde `cityId`/`city` → `stateId`/`state`. API endpoint `/cities` → `/states`.

**Etkilenen dosyalar:** `city_service.dart` + ~40 dosyada field referansları (çoğu `listing.city` → `listing.state` ve `filter.cityId` → `filter.stateId`)

- [x] **9.18** Flutter: city_service.dart→state_service.dart, CityService→StateService, /api/states ✓ commit: 1fcf0b1b

### 9.11 Hardcoded Label Temizliği

**Backend — `analytics.py` (3 dict):**

| Değişken | Satır | Kullanıldığı endpoint |
|---|---|---|
| `_PRICE_CAT_LABELS` | 471 | price-estimate |
| `_CATEGORY_LABELS` | 850 | market-trends |
| `_CAT_LABELS_MAP` | 1163 | auction stats |

Her üçü `t.get("cat_{key}", fallback)` formatına dönüştürülür — `_get_t(lang)` zaten mevcut.

**Flutter — `category_service.dart`:**

`_fallbackLabels` hardcoded map → silinir. Fallback `CatalogCategory.labelKey = 'cat_$key'` üzerinden OTA'ya düşer.

- [x] **9.19** `analytics.py` — 4 hardcoded label dict kaldırıldı, t.get() kullanılıyor ✓ commit: 53bc5862
- [x] **9.20** `category_service.dart` temizliği — _listingExcluded/_fallbackLabels kaldırıldı, forStream→?context=stream ✓ commit: 4417cb5d
  - `_fallbackLabels` hardcoded map kaldırılır (OTA'ya bırakılır)
  - `_listingExcluded = {'chat'}` hardcode kaldırılır (backend karar verir)
  - `forStream: true` → `/api/categories?context=stream` çağırır; `forStream: false` → `/api/categories`
- [x] **9.21** Test: servis başarıyla ayakta, sync logları temiz ✓

**Stream kategorileri kararları:**
- `documents/stream/stream_categories.json` yeni dosya: `[{"key": "chat", "sort_order": 99}]`
- Backend `/api/categories?context=stream` → listing kategorileri + stream_categories.json birleşimi döner
- Canlı sayfası kategori filtreleri **değişmez** — aktif yayınlardan türetme doğru davranış (yayın yoksa filtre yok)
- Yayın Aç modal `forStream: true` ile `/api/categories?context=stream` çağırır
- İlan Ver `forStream: false` ile `/api/categories` çağırır — `chat` gelmez
- `cat_chat` ARB key'i tüm dillerde (TR/EN/RU/AR) eklenecek

### 9.12 Son Kontroller

- [x] **9.22** Commit + push ✓ (son commit: 4417cb5d)
- [x] **9.23** VPS'te `git pull && sudo systemctl restart teqlif` ✓
- [x] **9.24** `journalctl -u teqlif -n 80` — alembic OK, 8 kategori, 198 field, 81 il, +0 ilçe, servis ayakta ✓
- [x] **9.25** Servis başarıyla çalışıyor; `logs/` izin sorunu `chown www-data` ile düzeltildi ✓
  - **Açık:** `firebase-service-account.json` `www-data` tarafından okunamıyor → push bildirimleri devre dışı (pre-existing). Düzeltme: `sudo chown www-data:www-data /var/www/teqlif.com/backend/firebase-service-account.json && sudo chmod 640 ...`

---

> **Faz 10'a not:** GPS reverse geocoding → Nominatim → DB match. Flutter'da ülke seçici (kayıt, ayarlar, İlan Ver). teqFilter'a ülke filtresi. Feed kişiselleştirme country_id'ye göre. ClickHouse/ML event'lerine country_code ekleme.

---

## Tamamlananlar

_(adımlar tamamlandıkça buraya taşınacak)_

---

## Notlar

_(sorunlar, çözümler, önemli kararlar buraya)_
