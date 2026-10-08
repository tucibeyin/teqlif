# Teqlif — Veri Yaşam Döngüsü Analizi

**Kapsam:** Kullanıcı · İlan · Bildirim · DM · Story · VoIP · Canlı Yayın · Analitik · ML/Embedding · MinIO · ClickHouse · Redis · PostgreSQL · Mail · Backup  
**Hedef:** Her veri parçasının TTL'si, kim yönetiyor, backup lifecycle'ı  
**Kaynak:** Canlı kod analizi + tüm node'lara SSH erişimi  
Son güncelleme: 2026-10-08

---

## İçindekiler

1. [Genel Bakış — Özet Tablo](#genel-bakış--özet-tablo)
2. [Kullanıcı Verisi](#kullanıcı-verisi)
3. [İlan Verisi](#ilan-verisi)
4. [Doğrudan Mesaj (DM) Verisi](#doğrudan-mesaj-dm-verisi)
5. [Bildirim Verisi](#bildirim-verisi)
6. [Story Verisi](#story-verisi)
7. [Canlı Yayın & Kayıt Verisi](#canlı-yayın--kayıt-verisi)
8. [VoIP / Çağrı Verisi](#voip--çağrı-verisi)
9. [Ticaret Verisi (Açık Artırma, Doğrudan Satış, Satın Alma)](#ticaret-verisi)
10. [Analitik Verisi](#analitik-verisi)
11. [ML / Embedding Verisi](#ml--embedding-verisi)
12. [Kalıcı Tablolar (TTL Yok)](#kalıcı-tablolar-ttl-yok)
13. [MinIO — Nesne Yaşam Döngüsü](#minio--nesne-yaşam-döngüsü)
14. [ClickHouse — Analytics TTL](#clickhouse--analytics-ttl)
15. [Redis — Ephemeral Veri](#redis--ephemeral-veri)
16. [Mail — Stalwart](#mail--stalwart)
17. [Backup Yaşam Döngüsü](#backup-yaşam-döngüsü)
18. [ARQ Worker vs teqlif-agent Farkları](#arq-worker-vs-teqlif-agent-farkları)
19. [V1.1'de Tespit ve Düzeltilen Sorunlar](#v11de-tespit-ve-düzeltilen-sorunlar)
20. [Açık Kalan Konular](#açık-kalan-konular)

---

## Genel Bakış — Özet Tablo

| Veri Kategorisi | TTL / Sonlanma | Kim Yönetiyor |
|----------------|---------------|---------------|
| Kullanıcı hesabı | Kalıcı (silinince anonimize) | Kullanıcı + auth router |
| İlan (aktif) | 30 gün → pasif | ARQ (listing_tasks) |
| İlan (pasif) | 60 gün → silindi + MinIO temizlendi | ARQ (listing_tasks) |
| DM (metin, okunmuş) | Silinmiyor | — |
| DM (metin, okunmamış) | 365 gün | ARQ (worker.py) |
| DM (medya) | 7 gün + MinIO silme | ARQ (worker.py) |
| DM (gizlenmiş) | 60 gün | ARQ (worker.py) |
| Bildirim | 30 gün | ARQ + teqlif-agent |
| Story | 24 saat + MinIO silme | ARQ (saatlik cron) |
| Canlı yayın (ended) | 10 yıl (PG) | ARQ + teqlif-agent (6ay) |
| Kayıt (available) | 24 saat | ARQ |
| Kayıt (MinIO dosyası) | transferred_at + 2 gün | MinIO ILM (node2_confirmed_at ile güvenli) |
| Kayıt (DB satırı) | archived_at + 15 gün | teqlif-agent |
| Çağrı (ended/missed) | 2 yıl (ARQ) / 90 gün (agent) | ARQ + teqlif-agent |
| Açık artırma | Kalıcı | — |
| Doğrudan satış | Kalıcı | — |
| Satın alma geçmişi | Kalıcı | — |
| analytics_events (PG) | 90 gün | ARQ + teqlif-agent |
| user_interactions (PG) | 365 gün (ARQ) / 90 gün (agent) | ARQ + teqlif-agent |
| ClickHouse tüm tablolar | 365 gün (engine TTL) | ClickHouse |
| preference_embedding | Kullanıcıyla birlikte yaşar | ARQ (reaktif güncelleme) |
| listing embedding | İlanla birlikte yaşar | ARQ (reaktif güncelleme) |
| MinIO uploads/ | Kalıcı (ilan/DM ile birlikte silinir) | listing/message cleanup |
| MinIO recordings/ | 2 gün (ILM) | MinIO ILM policy (node2_confirmed_at guard) |
| Redis (genel) | 24h–30g key bazlı | TTL parametresi |
| Loki log | 30 gün (yerel) / 90 gün (backup) | Loki retention + node2 |
| Uptime Kuma DB | Silinmiyor | node2 backup 180g |
| Stalwart mail | Silinmiyor | — |

---

## Kullanıcı Verisi

### Aktif Hesap

`users` tablosu — 47 kolon. TTL yok; kullanıcı aktif kaldıkça kalıcıdır.

| Alan | Yönetim |
|------|---------|
| `profile_image_url`, `profile_image_thumb_url` | Kullanıcı değiştirince eski MinIO nesnesi silinir |
| `preference_embedding` (Vector 384) | ARQ `update_user_preference_embedding` reaktif günceller |
| `fcm_token`, `voip_token` | Hesap silince `NULL` yapılır |
| `notification_prefs` (JSON) | Kalıcı; kullanıcı günceller |

### Hesap Silme (`DELETE /auth/delete-account`)

Soft-delete + anonymization; satır DB'den silinmez, içerik anonimleştirilir.

```
1. Kimlik bilgileri anonimize edilir:
   email       → "purged_<id>@deleted.invalid"
   username    → "deleted_<id>"
   full_name   → "Deleted Account"
   phone, bio, tüm URL'ler, sosyal linkler → NULL
   hashed_password → ""
   fcm_token, voip_token → NULL
   preference_embedding, max_budget → NULL
   is_premium, plan_type, referral_code → sıfırlanır
   status      → UserStatus.DELETED

2. Kullanıcının aktif ilanları → status='passive'

3. Profil fotoğrafı ve küçük resim MinIO'dan silinir

4. Kullanıcının diğer verileri (DM, bildirim, ticaret geçmişi)
   kendi TTL kurallarına göre bağımsız yaşar
```

**Sonuç:** `users` satırı kalır, FK bütünlüğü bozulmaz. Ticaret geçmişi korunur.

---

## İlan Verisi

### Yaşam Döngüsü

```
[active]
    ↓ expires_at geçince VEYA 30 gün dolunca
    ↓ deactivate_expired_listings_task (ARQ, günlük 04:00)
[passive]  ←── deactivated_at set
    ↓ deactivated_at + 60 gün
    ↓ delete_expired_inactive_listings_task (ARQ, günlük 04:30)
[DELETED]
    ↓ aynı anda:
    ├── MinIO: tüm fotoğraflar + video + thumbnail silinir
    ├── Redis: ALS item vektörü + listing cache silinir
    └── Bildirimler: related_id eşleşen new_listing/search_alert/... silinir
```

| Sabit | Değer | Dosya |
|-------|-------|-------|
| `_FREE_LISTING_DAYS` | 30 gün | `listing_tasks.py:29` |
| `_INACTIVE_DELETE_DAYS` | 60 gün | `listing_tasks.py:30` |

**Premium listeler:** `expires_at` alanı set edilmiş olanlar `deactivate_expired_listings_task` kapsamı dışındadır (`expires_at == None` koşuluyla sadece süresi belirsiz ilanlar hedeflenir).

**Manuel silme:** Kullanıcı veya admin ilanı silerse aynı MinIO + Redis + bildirim temizliği anında çalışır (`listing_cleanup_resources`).

### İlan MinIO Dosyaları

| Dosya Türü | Bucket | Silinme Zamanı |
|-----------|--------|----------------|
| Fotoğraflar (image_url, image_urls) | `teqlif/uploads/` | İlan silinince |
| Video | `teqlif/uploads/` | İlan silinince |
| Thumbnail | `teqlif/uploads/` | İlan silinince |

---

## Doğrudan Mesaj (DM) Verisi

### Metin Mesajları

| Kategori | TTL | Koşul |
|---------|-----|-------|
| Okunmuş normal metin | **Silinmiyor** ← Açık konu A2 | — |
| Okunmamış, gizlenmemiş | 365 gün | `is_read=FALSE AND is_hidden=FALSE AND created_at <` |
| Gizlenmiş (moderasyon) | 60 gün | `is_hidden=TRUE AND created_at <` |

**Normal okunmuş metin mesajları hiç silinmiyor** — int4 PK sınırı ve sonsuz büyüme riski V1.0/S1 bulgusudur. V2.0'a ertelendi.

### Medya Mesajları

| Medya Türü | TTL | MinIO |
|-----------|-----|-------|
| image, video, voice, file (tüm non-text) | **7 gün** | MinIO nesnesi (`media_url`, `thumbnail_url`) da silinir |

Görev: `cleanup_old_media_messages_task` (ARQ, günlük 06:30).

### DM Ekleri MinIO (`teqlif-dm` bucket)

- Medya mesajı 7 günde silinince MinIO nesnesi de silinir — **bağlantılı**.
- Mesaj silme olmadan orphan nesne birikimi yok.
- Ancak kullanıcı DM iş parçacığını silerken medya nesnesini silme mekanizması **yok** → açık konu A1.

---

## Bildirim Verisi

| Kaynak | TTL | Koşul |
|--------|-----|-------|
| ARQ Worker (cleanup_old_notifications_task) | 30 gün | `created_at <` — tüm bildirimler |
| teqlif-agent ScheduledCleaner (00:00 UTC) | 30 gün | `created_at < AND is_read=true` — yalnızca okunmuşlar |
| İlan silinince | Anında | `related_id` eşleşen listing bildirimleri |

ARQ tüm bildirimleri, agent yalnızca okunmuşları siler — komplementer katman.

---

## Story Verisi

### Yaşam Döngüsü

```
Story yüklenir
    ↓ expires_at = NOW() + 24 saat
[aktif]
    ↓ expires_at geçince
    ↓ cleanup_expired_stories_task (ARQ, her saat başı)
MinIO'dan video/thumbnail silinir + DB satırı silinir
```

- `story_views` satırları parent `stories` satırı silinince cascade ile gider.
- Sahibi manuel silerse aynı MinIO + DB temizliği anında çalışır.

---

## Canlı Yayın & Kayıt Verisi

### live_streams Tablosu

| Kayıt | ARQ | teqlif-agent |
|-------|-----|--------------|
| `status='ended' AND ended_at <` | 10 yıl (3650d) | 180 gün |

Agent daha agresif; iki katman örtüşüyor. 10 yıl ARQ değeri kasıtlı mı belirsiz (bkz. A3).

### live_stream_viewers Tablosu

Uzun vadeli fraud/analitik için tutulur:

| | TTL |
|-|-----|
| ARQ Worker | 10 yıl (`left_at IS NOT NULL AND joined_at <`) |
| teqlif-agent | 10 yıl (V1.1'de düzeltildi) |

### stream_recordings — Yaşam Döngüsü

```
[recording]        recording_started_at=NOW()
    ↓ FFmpeg WHEP biter (recorder.py)
[encoding]         encoding_started_at=NOW()
    ↓ FFmpeg H.264 encode (encoder.py) — raw sil
[encoded]          encoded_at=NOW()
    ↓ Transfer penceresi 03:00-08:00 UTC, mc cp → node1 MinIO
[transferring]
    ↓ mc cp tamamlanır → node1 MinIO'da mevcut
[available]        transferred_at=NOW(), available_at=NOW(), expires_at=NOW()+24h
    ↓ expire_recordings_task (ARQ, her 30 dk)
    ↓ koşul: expires_at < NOW()
[expired]
    ↓ [node2 minio_backup.sh günlük mirror başarılı]
    ↓ node2_confirmed_at=NOW() — node2'nin dosyayı aldığı onayı
    ↓ archive_recordings_task (ARQ, her 15 dk)
    ↓ koşul: node2_confirmed_at IS NOT NULL
    ↓         AND transferred_at < NOW() - 2 days  (ILM guard)
    ↓ (MinIO ILM transferred_at+2 gün'de dosyayı siler)
[archived]         archived_at=NOW()
    ↓ teqlif-agent janitor (stream_recordings_15d)
    ↓ koşul: archived_at < NOW() - 15 days
[DB'den silindi]
```

**Zaman damgaları özeti:**
| Sütun | Ne zaman set edilir | Kim set eder |
|-------|--------------------|-----------:|
| `recording_started_at` | FFmpeg başladığında | recorder.py |
| `encoding_started_at` | FFmpeg bitip encode başlarken | recorder.py |
| `encoded_at` | Encode tamamlandığında | encoder.py |
| `transferred_at` | mc cp node1 MinIO'ya tamamlandığında | encoder.py |
| `available_at` | transferred_at ile aynı anda | encoder.py |
| `expires_at` | transferred_at + 24 saat | encoder.py |
| `node2_confirmed_at` | node2 mirror başarılı olduğunda | minio_backup.sh |
| `archived_at` | archive_recordings_task çalıştığında | ARQ worker |

**MinIO ILM Kuralı** (`teqlif` bucket, `recordings/` prefix):
- Kural ID: `db0usckkndqcpvdusp30` (node1'de aktif)
- Expiry: **2 gün** (önceki: 4 gün — node2_confirmed_at ile kör bekleme kalktı)

**Güvenlik garantisi:**
- node2 backup başarısız → `node2_confirmed_at` set edilmez → `archive_recordings_task` bekler → node1 MinIO dosyası silinmez → ertesi gün backup tekrar dener
- node2 backup başarılı ama PG güncellemesi başarısız → aynı sonuç: güvenli bekler
- ILM guard (2 gün): node2 onaylanmış olsa bile MinIO ILM'nin çalışmasına izin verir

---

## VoIP / Çağrı Verisi

| Tablo | ARQ TTL | teqlif-agent TTL | Notlar |
|-------|---------|-----------------|--------|
| `calls` | 2 yıl (ended/missed, ended_at) | 90 gün (created_at) | Farklı kolon — agent daha agresif |
| `call_participants` | cascade (calls ile) | — | Üst satır silinince gider |

LiveKit oda state'i: RAM içi, kalıcı değil. Egress dosyası aktarım sonrası MinIO `recordings/` altına yazılır.

---

## Ticaret Verisi

Ticaret verileri **kasıtlı olarak kalıcıdır** — hukuki yükümlülük, anlaşmazlık çözümü ve analitik için.

| Tablo | TTL | Notlar |
|-------|-----|--------|
| `auctions` | **Kalıcı** | Tüm teklifler dahil |
| `direct_sales` | **Kalıcı** | — |
| `direct_sale_orders` | **Kalıcı** | — |
| `purchases` | **Kalıcı** | — |
| `tuci_transactions` | **Kalıcı** | Platform iç para birimi hareketleri |
| `gift_events` | **Kalıcı** | Yayın içi hediye geçmişi |
| `ad_campaigns` | **Kalıcı** | — |
| `listing_offers` | 365 gün (ARQ, created_at) / 60 gün (agent, updated_at) — sadece declined/expired | Aktif teklifler dokunulmaz |

---

## Analitik Verisi

### PostgreSQL Analitik Tabloları

| Tablo | ARQ TTL | teqlif-agent TTL |
|-------|---------|-----------------|
| `analytics_events` | 90 gün (created_at) | 90 gün (created_at) |
| `user_interactions` | 365 gün (created_at) | 90 gün (created_at) |
| `listing_impressions` | 30 gün (seen_at) | 30 gün (seen_at) |
| `search_alerts` | 180 gün (created_at) | 90 gün (last_match_at) — komplementer |

**Redis → PG flush:** `flush_interactions_to_db` (ARQ, her 5 dakika) — Redis `interaction_queue` kuyruğunu okuyup `user_interactions` tablosuna bulk-insert eder. Redis kuyruğu tüketildikten sonra silinir.

### ClickHouse Analitik Tabloları

Engine TTL — uygulama kodu devreye girmez.

| Tablo | TTL |
|-------|-----|
| `feed_events` | 365 gün (timestamp) |
| `search_events` | 365 gün (timestamp) |
| `user_events` | 365 gün (timestamp) |
| `listing_hype` | 365 gün (timestamp) |
| `listing_market` | 365 gün (timestamp) |

ClickHouse TTL merge'leri asenkron; silme garantili, anlık değil.

---

## ML / Embedding Verisi

| Veri | Nerede | TTL | Güncelleme |
|------|--------|-----|-----------|
| `users.preference_embedding` (Vector 384) | PostgreSQL | Kullanıcıyla birlikte yaşar | `update_user_preference_embedding` — kullanıcı etkileşim yapınca ARQ tetikler |
| `listings.embedding` (Vector 384) | PostgreSQL | İlanla birlikte yaşar | `generate_listing_embedding_task` — ilan oluşturulunca/güncellenince ARQ tetikler |
| ALS item vektörü | Redis (`feed:als:item_vec:<id>`) | İlan silinince | `cleanup_listing_redis` tarafından silinir |
| ALS kullanıcı vektörü | Redis | TTL parametreli | Cron ile yeniden hesaplanır |

---

## Kalıcı Tablolar (TTL Yok)

Bu tablolar hiçbir cleanup gorevi tarafından temizlenmez; veri yaşam döngüsü boyunca kalıcıdır.

| Tablo | Neden Kalıcı |
|-------|-------------|
| `users` | Hesap silince anonimize — satır kalmaya devam eder (FK bütünlüğü) |
| `auctions` | Hukuki/ticaret kaydı |
| `direct_sales` | Hukuki/ticaret kaydı |
| `direct_sale_orders` | Hukuki/ticaret kaydı |
| `purchases` | Hukuki/ticaret kaydı |
| `tuci_transactions` | Platform ekonomisi kaydı |
| `gift_events` | Ticaret kaydı |
| `ad_campaigns` | Reklam raporları için |
| `ratings`, `rating_history` | Kullanıcı itibar sistemi |
| `follows` | Sosyal graf |
| `favorites` | Kullanıcı tercihleri |
| `user_blocks` | Güvenlik |
| `user_interests` | Onboarding verileri |
| `reports` | Moderasyon kaydı |
| `referrals` | Ödül sistemi kaydı |
| `categories`, `subcategories` | Statik katalog |
| `states`, `districts`, `countries` | Statik coğrafi veri |
| `app_configs` | Uygulama konfigürasyonu |
| `translations` | Lokalizasyon |

---

## MinIO — Nesne Yaşam Döngüsü

### Bucket Yapısı

| Bucket | İçerik | ILM | Silinme Mekanizması |
|--------|--------|-----|---------------------|
| `teqlif` | `uploads/` (ilan foto/video) | Yok | İlan silinince `listing_cleanup_resources` |
| `teqlif` | `recordings/` (yayın kayıtları) | **2 gün expiry** (ID: `db0usckkndqcpvdusp30`) | MinIO ILM otomatik |
| `teqlif-dm` | DM ekleri | Yok | Medya mesajı 7 günde silinince `cleanup_old_media_messages_task` |
| `teqlif-staging` | Staging uploads/recordings | — | — |
| `teqlif-dm-staging` | Staging DM ekleri | — | — |

**ILM kurulum scripti:** `deploy/scale/V2.1/scripts/setup_minio_ilm.sh` (idempotent)

---

## Redis — Ephemeral Veri

| Veri | TTL | Notlar |
|------|-----|--------|
| JWT access token (blacklist) | ~1 saat | Çıkış yapılınca blacklist'e eklenir |
| JWT refresh token | ~30 gün | |
| Email doğrulama kodu | ~10 dakika | |
| Rate limiting | dakika/saat | Sliding window |
| Auction state cache | Stream süresi + buffer | |
| Live stream viewer count | Stream bitince expire | |
| ARQ job queue | Görev süresi | |
| Hype/skor cache | ~24 saat | |
| interaction_queue | 5 dakika (flush) | ARQ `flush_interactions_to_db` tüketir |
| feed:als:item_vec:<id> | İlan silinince | `cleanup_listing_redis` |
| ALS kullanıcı vektörü | Cron yeniler | |
| i18n çeviri cache | Manuel invalidation | `sync_translations.py` temizler |

Redis maxmemory: 4GB, politika: `allkeys-lru`.

---

## Mail — Stalwart

nodeMonitor'da çalışır.

| Veri | TTL |
|------|-----|
| Gelen/giden mail | Kullanıcı silmedikçe kalıcı |
| SMTP queue | Gönderim sonrası temizlenir |
| DKIM/config | Kalıcı (nodeMonitor config backup'ında) |

---

## Backup Yaşam Döngüsü

Tüm backup'lar node2'de merkezi olarak toplanır.

| Servis | Saat (UTC) | Retention | Script |
|--------|-----------|-----------|--------|
| PostgreSQL | 02:00 | 90 gün | `pg_backup.sh` |
| MinIO | 03:00 | 90 gün | `minio_backup.sh` |
| Redis | 04:00 | 90 gün | `redis_backup.sh` |
| ClickHouse | 04:30 | 90 gün | `clickhouse_backup.sh` |
| Loki chunks | 06:00 | 90 gün | `loki_backup.sh` *(V1.1)* |
| Uptime Kuma | 06:05 | 180 gün | `uptime_kuma_backup.sh` *(V1.1)* |
| nodeMonitor config | 06:10 | Kalıcı | `nodemonitor_config_backup.sh` *(V1.1)* |

Backup sağlığı: `teqlif-agent health.py` her backup için 25h eşikli Telegram alarmı.

---

## ARQ Worker vs teqlif-agent Farkları

| Tablo | ARQ Worker | teqlif-agent | Durum |
|-------|-----------|--------------|-------|
| `notifications` | 30d (tümü) | 30d (is_read=true) | Komplementer |
| `analytics_events` | 90d | 90d | ✅ Uyumlu |
| `user_interactions` | 90d (created_at) | 90d (created_at) | ✅ Düzeltildi (V1.1) |
| `stream_likes` | 7d | — | ARQ tek yönetici |
| `live_stream_viewers` | 10y | 10y | ✅ Düzeltildi (V1.1) |
| `listing_offers` | 365d (created_at) | 60d (updated_at) | ⚠️ Farklı kolon + TTL |
| `exchange_rates` | 10y | 365d | Agent daha agresif |
| `live_streams` | 10y | 180d | Agent daha agresif |
| `calls` | 2y (ended_at) | — (kaldırıldı) | ✅ Düzeltildi (V1.1) — agent'tan silindi, ARQ tek yönetici |
| `message_threads` | 30d (boş, created_at) | 180d (boş, updated_at) | Farklı kolon |
| `search_alerts` | 180d (created_at) | 90d (last_match_at) | Komplementer |
| `listing_impressions` | 30d (seen_at) | 30d (seen_at) | ✅ Düzeltildi (V1.1) |
| `stream_recordings` | — | 15d (archived_at) | teqlif-agent tek yönetici |

---

## V1.1'de Tespit ve Düzeltilen Sorunlar

### S1 [DÜZELTİLDİ] — MinIO ILM Hiç Tanımlanmamıştı

`archive_recordings_task` "MinIO'nun dosyayı sildiğini kabul eder" diyor ama `mc ilm add` hiç çalıştırılmamıştı. Kayıtlar node1'de birikiyor, terabyte'lara ulaşma riski.

**Düzeltme:** `setup_minio_ilm.sh` oluşturuldu, kural aktive edildi (ID: `db0usckkndqcpvdusp30`).

### S2 [DÜZELTİLDİ] — nodeMonitor Backup'ı Yoktu

Loki log chunk'ları, Uptime Kuma DB ve monitoring konfigürasyonu hiç backup'lanmıyordu.

**Düzeltme:** 3 script + 6 systemd unit node2'de eklendi, aktive edildi.

### S3 [DÜZELTİLDİ] — live_stream_viewers TTL Uyumsuzluğu

agent: 90 gün → ARQ: 10 yıl. Hizalandı: 10 yıl.

### S4 [DÜZELTİLDİ] — listing_impressions TTL Uyumsuzluğu

agent: `created_at < 90 gün` → ARQ: `seen_at < 30 gün`. Hizalandı: `seen_at < 30 gün`.

---

## Açık Kalan Konular

| # | Konu | Öncelik | Not |
|---|------|---------|-----|
| A1 | `teqlif-dm` bucket — kullanıcı thread silince orphan nesne riski | Düşük | Medya mesajı 7g'de silinince MinIO da siliniyor; thread silme ayrı mekanizma gerektirir |
| A2 | `direct_messages` (okunmuş metin) silinmiyor | Orta | **V1.1 kapsamı:** (1) id int4 → BigInt, (2) hot tier: PG'de son 1 yıl, (3) cold tier: 1y+ mesajlar MinIO'ya gzip JSON arşiv, PG'den silinir, (4) UI "eski mesajları yükle" |
| A3 | `user_interactions` ARQ/agent farkı (365d vs 90d) | Düşük | ✅ Düzeltildi: ARQ 365d → 90d (ClickHouse'da zaten 365d var, PG kopyasının uzun tutulması gereksiz) |
| A4 | `calls` ARQ/agent farkı (2y ended_at vs 90d created_at) | Düşük | ✅ Düzeltildi: agent'tan kaldırıldı, ARQ (2y, ended_at) tek yönetici |
| A5 | Stalwart mail backup yok | Düşük | Config backup var, mail kendisi yok |
