# Güvenlik Bulguları — V1.0

**Tarih:** 2026-09-13  
**Kapsam:** Backend (FastAPI) + Infrastructure (deploy/, nginx, systemd, scripts)  
**Yöntem:** Statik kod analizi — iki paralel tarama (backend kod güvenliği + altyapı/deploy)  
**Toplam bulgu:** 5 HIGH · 9 MEDIUM · 5 LOW

---

## Özet Tablosu

| ID | Önem | Başlık | Alan | Durum |
|----|------|--------|------|-------|
| H1 | 🔴 HIGH | Second-order SQL Injection (analytics → feed) | Backend | Açık |
| H2 | 🔴 HIGH | Admin şifre endpoint'inde rate limiting yok | Backend | Açık |
| H3 | 🔴 HIGH | rsync StrictHostKeyChecking=no | Infra | Açık |
| H4 | 🔴 HIGH | `.env.*` dosyaları git'te takip ediliyor | Infra | Açık |
| H5 | 🔴 HIGH | redis-backup.sh Redis auth yok | Infra | Açık |
| M1 | 🟡 MEDIUM | JWT token hata logunda plaintext | Backend | Açık |
| M2 | 🟡 MEDIUM | Analytics unauthenticated user_id injection | Backend | Açık |
| M3 | 🟡 MEDIUM | wallet.py dict alıyor, Pydantic yok; bakiye TODO | Backend | Açık |
| M4 | 🟡 MEDIUM | Admin Google verify endpoint rate limit yok | Backend | Açık |
| M5 | 🟡 MEDIUM | MinIO console tüm interface'lere bind | Infra | Açık |
| M6 | 🟡 MEDIUM | nginx'te CSP header eksik | Infra | Açık |
| M7 | 🟡 MEDIUM | alertmanager ExecStartPre root çalışıyor | Infra | Açık |
| M8 | 🟡 MEDIUM | OCSP stapling kapalı | Infra | Açık |
| L1 | ⚪ LOW | check-username user ID enumeration | Backend | Açık |
| L2 | ⚪ LOW | /api/client-log unauthenticated log injection | Backend | Açık |
| L3 | ⚪ LOW | systemd hardening direktifleri yok | Infra | Açık |
| L4 | ⚪ LOW | WireGuard topolojisi repo'da açık | Infra | Kabul |
| L5 | ⚪ LOW | Loki 0.0.0.0 bind | Infra | Kabul |

---

## 🔴 HIGH Bulgular

---

### H1 — Second-order SQL Injection (analytics → feed)

**Dosyalar:**
- `backend/app/routers/streams.py:466–470`
- `backend/app/routers/users.py:154–158`
- `backend/app/routers/analytics.py` (yazım noktası)
- `backend/app/worker.py:917–937` (ara kademe)
- `backend/app/schemas/analytics.py:29` (validation eksikliği)

**Saldırı Zinciri:**

```
1. POST /api/analytics/track-search   ← kimlik doğrulaması YOK
   Body: {"query": "x", "category": "' THEN 1.0 END); DROP TABLE users; --"}
   → analytics_events tablosuna yazılır (event_metadata->>'category')

2. Worker her 15 dakikada çalışır
   → analytics_events'ten category değerini çekip user_interests'e upsert eder

3. GET /api/streams/recommended-streamers  (herhangi bir kullanıcı)
   → user_interests.category değeri doğrudan SQL'e gömülür:

   cat_affinity_cases = " ".join(
       f"WHEN category = '{cat}' THEN {score:.4f}"   ← injection
       for cat, score in top_cat_scores
   )
```

**Neden middleware korumaz:**
- `InputSanitizationMiddleware` sadece query parametrelerini kontrol ediyor, request body'yi değil
- Keyword blacklist (`SELECT`, `DROP` gibi) tırnak karakterini yakalamıyor

**Saldırı gereksinimleri:**
- Kimlik doğrulaması gerektirmiyor
- Etki 15 dakika sonra aktif hale geliyor (worker döngüsü)
- Arbitrary PostgreSQL çalıştırma: veri okuma, silme, tablo bırakma

**Fix Seçenekleri:**
1. `category` alanını onboarding'deki `_VALID_CATEGORIES` whitelist'iyle validate et (tercih edilen)
2. CASE ifadesini parametre olarak ilet (`sqlalchemy.case` ile)
3. Minimum: `analytics.py`'de category regex validasyonu ekle `[a-z_]+`

---

### H2 — Admin Şifre Endpoint'inde Rate Limiting Yok

**Dosya:** `backend/app/routers/admin_auth.py:43–64`

**Sorun:**
`POST /api/admin-auth/verify-password` üzerinde `@limiter.limit()` dekoratörü yok.

Kıyaslama:
- `POST /api/auth/login` → `@limiter.limit("5/minute")` ✅
- `POST /api/admin-auth/verify-password` → limit yok ❌

Global `AntiBotMiddleware` dakikada 300 isteğe izin veriyor. Bu da dakikada 300 şifre denemesi = 10 dakikada 4500 deneme anlamına geliyor. Başarılı girişte tam yetkili admin JWT döner.

**Fix:**
```python
@limiter.limit("3/minute")
async def verify_password(request: Request, ...):
```
Opsiyonel: Redis'te başarısız deneme sayacı, N denemeden sonra `admin_email`'e bildirim.

---

### H3 — rsync StrictHostKeyChecking=no

**Dosya:** `deploy/scripts/offsite-rsync.sh:17,23`

```bash
-e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
```

**Sorun:**
Backup transferi node3'ün SSH host key'ini doğrulamıyor. WireGuard mesh içinde `10.10.0.4` için route manipülasyonu yapılırsa backup (PostgreSQL dump + Redis dump) başka bir sunucuya gider — bağlantı kesilmeden, hata vermeden.

**Fix:**
```bash
# node3'ün host key'ini root'un known_hosts'una önceden ekle:
ssh-keyscan -H 10.10.0.4 >> /root/.ssh/known_hosts

# rsync'te StrictHostKeyChecking=no kaldır, yes yap:
-e "ssh -i $SSH_KEY -o StrictHostKeyChecking=yes -o ConnectTimeout=10"
```

---

### H4 — `.env.*` Dosyaları Git'te Takip Ediliyor

**Dosya:** `.gitignore:13`

```
!deploy/scale/resources/.env.*   # bu istisna template'leri git'e ekliyor
```

**Durum:** Şu an bu dosyalar boş değerler içeriyor — aktif sızıntı yok.

**Risk:**
VPS'lerde repo `/var/www/teqlif.com/` altında ve `TEQLIF_ENV_FILE` bu dizindeki `.env.*` dosyalarını gösteriyor. Herhangi bir operatör dolu `.env.*` dosyalarıyla `git add -A` veya `git commit -a` çalıştırırsa şunlar history'ye girer:
- `DATABASE_URL` (PostgreSQL şifreleri)
- `SECRET_KEY` (JWT imzalama)
- `GROQ_API_KEY`, `GEMINI_API_KEY`
- `TELEGRAM_BOT_TOKEN`
- `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`
- `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`
- `CF_API_TOKEN` (Cloudflare)
- `APNS_KEY_PATH` (Apple Push)

GitHub'a push edilirse history'den silmek zor (BFG Repo Cleaner + force push).

**Fix:**
```
# .gitignore'dan şu satırı sil:
!deploy/scale/resources/.env.*

# Template'leri *.env.template adıyla izlenmeye devam et:
deploy/scale/resources/node1/.env.production.template
deploy/scale/resources/node3/.env.production.template
deploy/scale/resources/node3/.env.staging.template
```
Mevcut template içerikleri `.env.production.template` olarak taşınır; gerçek `.env.*` dosyaları gitignore'da kalır.

---

### H5 — redis-backup.sh Redis'e Auth Olmadan Bağlanıyor

**Dosya:** `deploy/scripts/redis-backup.sh:13–18`

```bash
START=$(redis-cli LASTSAVE)   # ← NOAUTH hatası alır ama exit 0
redis-cli BGSAVE              # ← NOAUTH hatası alır ama exit 0
```

**Sorun:**
Redis `requirepass` ile korumalı ama backup script'i şifresiz bağlanıyor. Redis `NOAUTH` string'i döndürüyor (exit code: 0), `set -e` yakalamıyor.

Ardından:
```bash
[ "$STATUS" -gt "$START" ]  # "NOAUTH..." > "NOAUTH..." karşılaştırması — bash bunu 0 sayar
```
Wait loop broken. Script eski `dump.rdb`'yi kopyalayıp "başarılı" rapor ediyor.

**Sonuç:** Aylar boyunca stale backup alınıyor olabilir, monitoring panelinde hep "OK" görünür.

**Fix:**
```bash
REDIS_PASS=$(grep '^requirepass' /etc/redis/redis.conf | awk '{print $2}')
REDIS_CLI="redis-cli -a $REDIS_PASS --no-auth-warning"

START=$($REDIS_CLI LASTSAVE)
$REDIS_CLI BGSAVE
```

---

## 🟡 MEDIUM Bulgular

---

### M1 — JWT Token Hata Logunda Plaintext Yazılıyor

**Dosya:** `backend/app/utils/auth.py:168`

```python
logger.error(f"[AUTH] get_current_user 401: Geçersiz token (raw_token={raw_token})")
```

Biraz malformed (claim format hatası, yanlış algoritma header'ı vb.) ama süresi dolmamış bir token hata alırsa `raw_token` tam uzunlukta log'a yazılır. Log aggregator'ı (Loki/Grafana) erişimi olan herkes bu token'ı replay edebilir.

**Fix:**
```python
logger.error(f"[AUTH] get_current_user 401: Geçersiz token (raw_token={raw_token[:10]}...)")
```

---

### M2 — Analytics Unauthenticated user_id Injection

**Dosya:** `backend/app/routers/analytics.py:98–116`

Auth header yoksa `payload.user_id` body'den alınıyor ve kayıt ediliyor. Saldırgan başka bir kullanıcının `user_id`'sini body'ye koyarsa o kullanıcının ilgi profili (ve dolayısıyla feed'i) manipüle edilebilir.

**Fix:** `user_id` body parametresini kaldır. Auth yoksa anonim session ID kullan (server-side üretilmiş), client-supplied `user_id` hiçbir zaman kabul etme.

---

### M3 — wallet.py `dict` Alıyor, Pydantic Validation Yok

**Dosya:** `backend/app/routers/wallet.py:96–108`

```python
async def transfer_tuci(data: dict, ...):
    recipient_id = data.get("recipient_id")  # type yok, None olabilir
    amount = data.get("amount")              # type yok, "abc" olabilir
    # TransferTuciCommand'da bakiye kontrolü yok: "# Şimdilik bakiye yeterli varsayalım"
```

`{"recipient_id": null, "amount": -999}` göndermek unhandled exception veya negatif transfer üretebilir.

**Fix:**
```python
class TransferRequest(BaseModel):
    recipient_id: UUID
    amount: Decimal = Field(gt=0, le=10000)

async def transfer_tuci(data: TransferRequest, ...):
```
Ve worker.py'deki bakiye kontrolü TODO'su giderilmeli.

---

### M4 — Admin Google Verify Endpoint Rate Limit Yok

**Dosya:** `backend/app/routers/admin_auth.py:18–37`

`POST /api/admin-auth/verify-google` üzerinde limit yok. Google token doğrulaması outbound HTTPS çağrısı yapıyor — flood'da connection pool'u tüketebilir.

**Fix:** `@limiter.limit("5/minute")`

---

### M5 — MinIO Console Tüm Interface'lere Bind

**Dosya:** `deploy/scale/V1.3/node1/systemd/minio.service` ve node3 eşdeğeri

```ini
ExecStart=... --address :9010 --console-address :9011
```

MinIO admin console `:9011`'de tüm interface'lere bind. UFW default DENY ise dışarıdan erişilemiyor — ama UFW kuralı yanlış yazılırsa admin UI ve API açık kalır.

**Fix:**
```ini
# node3 (sadece local erişim):
--address 127.0.0.1:9010 --console-address 127.0.0.1:9011

# node1 (gateway WireGuard üzerinden erişiyor):
--address 10.10.0.1:9010 --console-address 127.0.0.1:9011
```

---

### M6 — nginx'te Content-Security-Policy Eksik

**Dosya:** `deploy/scale/V1.3/gateway/nginx/teqlif.conf`

X-Frame-Options, HSTS, X-Content-Type-Options var. CSP yok.

Kullanıcı içerikli bir platformda stored XSS varsa (profil, mesaj, ilan açıklaması) CSP olmadan execution context sınırsız.

**Fix:**
```nginx
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; object-src 'none'; frame-ancestors 'none';" always;
```
Not: Flutter Web / React Native Web uygulamanın inline script ihtiyaçlarına göre ayarlanması gerekebilir.

---

### M7 — alertmanager ExecStartPre Root Olarak Çalışıyor

**Dosya:** `deploy/scale/V1.3/node3/systemd/alertmanager.service`

```ini
ExecStartPre=+/bin/bash -c 'envsubst < .../alertmanager.yml.template > /etc/alertmanager/alertmanager.yml'
```

`+` prefix systemd'ye bu adımı root olarak çalıştır diyor — `User=tucibeyin` direktifini bypass ediyor. Render edilen dosya (`/etc/alertmanager/alertmanager.yml`) içinde `TELEGRAM_BOT_TOKEN` açık metin olarak yazılıyor.

**Fix:** `alertmanager`'ı `--config.expand-env` flag'iyle başlat ve env var'ları doğrudan geçir. Template render adımına gerek kalmaz, `+` root satırı kalkar.

---

### M8 — OCSP Stapling Kapalı

**Dosya:** `deploy/scale/V1.3/gateway/nginx/teqlif.conf`

```nginx
ssl_stapling off;
ssl_stapling_verify off;
```

Her TLS handshake'te browser Let's Encrypt'e ayrı OCSP sorgusu yapıyor: +100ms latency ve kullanıcı ziyaretleri CA'ya sızıyor. Sertifika revoke edilirse client'lar bunu öğrenemez.

**Fix:**
```nginx
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;
```

---

## ⚪ LOW Bulgular

---

### L1 — check-username User ID Enumeration

**Dosya:** `backend/app/routers/auth.py:302–312`

`GET /api/auth/check-username?username=alice&exclude_id=42` — unauthenticated. `exclude_id=42` döndüğünde "available: true" yanıtı, username `alice`'in user ID'sinin 42 olduğunu ifşa eder. Diğer saldırılar için hedef tespiti.

**Fix:** `exclude_id` parametresini sadece authenticated endpoint'te kabul et, ve JWT'deki user ID ile eşleştiğini doğrula.

---

### L2 — /api/client-log Unauthenticated Log Injection

**Dosya:** `backend/app/routers/client_log.py:65–92`

Kimlik doğrulaması olmadan `tag`, `message`, `error`, `details` alanlarına newline karakteri gömülürse sahte server log satırları üretilebilir. Incident response'u yanıltmak için kullanılabilir.

**Fix:** Kimlik doğrulaması ekle (en azından static app secret) ve string alanlarda newline/control character sanitizasyonu yap.

---

### L3 — systemd Hardening Direktifleri Yok

**Dosya:** Tüm `deploy/scale/V1.3/*/systemd/*.service` dosyaları

Hiçbir service'te şunlar yok:
- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectSystem=full`
- `ProtectHome=yes`
- `CapabilityBoundingSet=`

Servisler `tucibeyin` kullanıcısıyla çalışıyor (root değil, bu iyi). Ama compromised uygulama process'i kullanıcının tüm dosyalarına (`~/.ssh`, tüm `.env.*` dosyaları dahil) erişebilir.

**Fix:** En azından şunları ekle:
```ini
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
```

---

### L4 — WireGuard Topolojisi Repo'da Açık *(Kabul Edilmiş)*

Public key'ler + IP adresleri + node rolleri repo'da görünür. Public key'ler kriptografik sır değil, ifşası doğrudan exploitation'a yol açmaz. Ama mesh topolojisi (hangi IP'de ne var) hedefli saldırı için yol haritası sunar.

**Karar:** Operasyonel kolaylık > teorik risk. Değiştirilmeyecek.

---

### L5 — Loki 0.0.0.0 Bind *(Kabul Edilmiş)*

`http_listen_address: 0.0.0.0` — node3'ün kendi promtail'i `localhost:3100` kullandığı için `10.10.0.4` bind'ına geçilemiyor (test scripti de `localhost:3100` kullanıyor). UFW wg0 kısıtlaması yeterli koruma sağlıyor.

**Karar:** Değiştirilmeyecek.

---

## Öncelik Sırası (Önerilen Çalışma Planı)

### Faz 1 — Kritik (Bu hafta)
1. **H1** — analytics category whitelist + SQL injection fix
2. **H2 + M4** — admin endpoint rate limiting (iki satır)
3. **H5** — redis-backup.sh auth fix
4. **H3** — rsync known_hosts + StrictHostKeyChecking fix

### Faz 2 — Önemli (Önümüzdeki sprint)
5. **H4** — .gitignore .env.* exception + template rename workflow
6. **M3** — wallet.py Pydantic model + bakiye kontrolü
7. **M1** — JWT token log truncation
8. **M2** — analytics user_id body injection fix
9. **M5** — MinIO bind adresi sabitleme

### Faz 3 — Hardening (Sonraki iterasyon)
10. **M6** — nginx CSP header
11. **M7** — alertmanager root ExecStartPre → env var geçiş
12. **M8** — OCSP stapling
13. **L3** — systemd hardening direktifleri
14. **L1** — check-username auth guard
15. **L2** — client-log auth + sanitization
