# Güvenlik Görevleri — V1.0

**Kaynak:** `documents/hack/V1.0/findings.md`  
**Verify tarihi:** 2026-09-13 — tüm bulgular kaynak kodda doğrulandı  
**Toplam görev:** 15 (5 HIGH · 7 MEDIUM · 3 LOW · 2 Kabul)

---

> **Uygulama Yöntemi**
>
> Her görev iki adımdan oluşur:
>
> 1. **Deploy adımı (otomatik):** Değişiklik `deploy/` veya `backend/` dizininde yapılır,
>    commit + push edilir. Bu adım mümkün olduğunca otomatikleştirilir — systemd service
>    dosyaları, nginx config, deploy scriptleri `deploy/` altında kaynak olarak tutulur.
>
> 2. **Node adımı (manuel):** VPS'lerde `git pull` + gerekiyorsa dosya kopyalama/reload/restart.
>    Backend değişiklikleri için `sudo teqlif-restart`, config değişiklikleri için servis
>    bazlı reload.
>
> Her görevde **`[Deploy]`** ve **`[Node]`** etiketleri bu iki adımı açıkça gösterir.
> `[Node]` adımı yoksa sadece git pull + teqlif-restart yeterlidir.

---

> **Mimari Not**
>
> Bu dokümandaki tüm backend görevleri `documents/teqlif_architectural_decisions.md`'deki
> clean architecture ve clean code prensiplerine uygun implemente edilmelidir:
>
> - **Sistem sınırlarında Pydantic:** Router'a gelen her dış veri `BaseModel` ile valide edilir;
>   `dict`, `Any`, ham query parametresi kabul edilmez.
> - **Parametre geçişi:** Ham SQL f-string yasak; SQLAlchemy `text()` + `bindparams` veya
>   ORM `case()` kullanılır.
> - **Hata yönetimi:** Yeni hata kodları `AppException` subclass'ı olarak tanımlanır;
>   düz `HTTPException` yazılmaz.
> - **Katman bağımlılığı:** Router → Use Case → Repository sırası korunur; router doğrudan
>   DB sorgusu çalıştırmaz.
> - **Tek sorumluluk:** Güvenlik düzeltmesi ek refactor içermez; mevcut davranış
>   değiştirilmeden sadece açık kapatılır.

---

## Faz 1 — Kritik (Bu Hafta)

---

### TASK-H1 · Second-order SQL Injection

**Bulgu:** H1 | **Önem:** 🔴 HIGH

**Sorun:**
`analytics_events.category` değeri (unauthenticated endpoint'ten geliyor) `user_interests`
tablosuna yazılıyor. Oradan `streams.py` ve `users.py`'de f-string ile SQL'e gömülüyor.

**Adımlar:**

1. **`backend/app/schemas/analytics.py:31` — Whitelist validation ekle**

   `category` alanına onboarding'deki geçerli kategori listesiyle validator ekle:

   ```python
   # Onboarding'deki sabit liste (örnek):
   _VALID_CATEGORIES: set[str] = {
       "arabalar", "emlak", "elektronik", "giyim", "spor",
       "ev_esyalari", "is_dunyasi", "hayvanlar", "diger"
   }

   @field_validator("category")
   @classmethod
   def validate_category(cls, v: str) -> str:
       if v and v not in _VALID_CATEGORIES:
           raise ValueError("Geçersiz kategori")
       return v
   ```

   Kategori listesi değişirse bu set güncellenir — sabit kodlanmış kategori sayısı azdır,
   whitelist yeterli ve güvenlidir.

2. **`backend/app/routers/streams.py:466–470` — f-string SQL kaldır**

   SQLAlchemy `case()` construct kullan; f-string'i tamamen sil:

   ```python
   from sqlalchemy import case, literal

   affinity_cases = [
       (literal(cat) == UserInterest.category, literal(score / max_score))
       for cat, score in top_cat_scores
   ]
   cat_affinity_expr = case(*affinity_cases, else_=literal(0.0))
   ```

3. **`backend/app/routers/users.py:154–158` — aynı pattern**

   Aynı değişikliği `users.py`'deki `cat_cases` f-string'ine uygula.

**`[Deploy]`** `backend/app/schemas/analytics.py`, `backend/app/routers/streams.py`,
`backend/app/routers/users.py` → commit + push

**`[Node]`** node1 (prod): `sudo teqlif-restart` | node3 (staging): `sudo teqlif-restart`

**Kabul kriterleri:**
- `category` alanına `'; DROP TABLE users; --` gönderildiğinde `422 Unprocessable Entity` döner
- `recommended-streamers` ve kullanıcı feed endpoint'leri hiçbir koşulda f-string SQL içermez
- `dart analyze` ve `pytest` yeşil

---

### TASK-H2 · Admin Şifre Endpoint Rate Limiting

**Bulgu:** H2 | **Önem:** 🔴 HIGH

**Sorun:**
`POST /api/admin-auth/verify-password` üzerinde `@limiter.limit()` yok.
Global `AntiBotMiddleware` dakikada 300 istek — admin brute force'a yetersiz.

**Adımlar:**

1. **`backend/app/routers/admin_auth.py:43` — Limiter decorator ekle**

   ```python
   @router.post("/verify-password")
   @limiter.limit("3/minute")
   async def verify_password(request: Request, ...):
   ```

2. **Opsiyonel: başarısız deneme sayacı**

   Redis key `admin_auth:failed:{ip}` — 3 başarısız denemede `admin_email`'e
   Telegram bildirimi. Bu adım TASK-H2 kapsamında değil; ayrı task olarak açılabilir.

**`[Deploy]`** `backend/app/routers/admin_auth.py` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- 4. denemede `429 Too Many Requests` döner
- Limiter import'u dosyanın en üstünde — mevcut `auth.py` pattern'ine bakılarak yapılır

---

### TASK-M4 · Admin Google Verify Rate Limiting

**Bulgu:** M4 | **Önem:** 🟡 MEDIUM  
_(H2 ile aynı dosya — birlikte yapılır)_

**Adımlar:**

1. **`backend/app/routers/admin_auth.py:18` — Limiter decorator ekle**

   ```python
   @router.post("/verify-google")
   @limiter.limit("5/minute")
   async def verify_google(request: Request, ...):
   ```

**`[Deploy]`** TASK-H2 ile aynı dosya — aynı committe yapılır

**`[Node]`** TASK-H2 ile aynı restart — ayrıca bir şey gerekmez

**Kabul kriterleri:**
- 6. denemede `429` döner
- Connection pool'u tüketecek flood'a karşı korunmuş

---

### TASK-H5 · Redis Backup Auth

**Bulgu:** H5 | **Önem:** 🔴 HIGH

**Sorun:**
`deploy/scripts/redis-backup.sh` `redis-cli`'ı `-a` flag'i olmadan çağırıyor.
`NOAUTH` string'i döner, exit code 0 — script eski `dump.rdb`'yi kopyaladığını sanıyor.

**Adımlar:**

1. **`deploy/scripts/redis-backup.sh:1–5` — Şifre okuma ve wrapper değişkeni ekle**

   ```bash
   REDIS_PASS=$(grep '^requirepass' /etc/redis/redis.conf | awk '{print $2}')
   REDIS_CLI="redis-cli -a $REDIS_PASS --no-auth-warning"
   ```

2. **Tüm `redis-cli` çağrılarını `$REDIS_CLI` ile değiştir (lines 13, 15, 18, vb.)**

   ```bash
   START=$($REDIS_CLI LASTSAVE)
   $REDIS_CLI BGSAVE
   ```

3. **NOAUTH kontrolü ekle — `set -e` yetmez**

   ```bash
   if echo "$START" | grep -q "NOAUTH\|ERR"; then
     echo "[redis-backup] HATA: Redis auth başarısız" >&2
     exit 1
   fi
   ```

**`[Deploy]`** `deploy/scripts/redis-backup.sh` → commit + push

**`[Node]`** node1: `git pull` yeterli — script cron'dan `/var/www/teqlif/deploy/scripts/redis-backup.sh`
olarak çalışıyor, yeni versiyon otomatik devreye girer. Manuel test: `sudo bash deploy/scripts/redis-backup.sh`

**Kabul kriterleri:**
- Script Redis şifresi olan ortamda çalışınca gerçek dump alır
- Auth başarısız olursa exit code 1 ile erken çıkar
- VPS'te test: `sudo bash deploy/scripts/redis-backup.sh` — başarı log'u görünmeli

---

### TASK-H3 · rsync StrictHostKeyChecking

**Bulgu:** H3 | **Önem:** 🔴 HIGH

**Sorun:**
`deploy/scripts/offsite-rsync.sh` `StrictHostKeyChecking=no` — node3 SSH host key
doğrulanmıyor, MITM saldırısında backup başka sunucuya gidebilir.

**Adımlar:**

1. **node1'de (root olarak) node3 host key'ini kaydet**

   VPS'te çalıştır:
   ```bash
   ssh-keyscan -H 10.10.0.4 >> /root/.ssh/known_hosts
   ```

2. **`deploy/scripts/offsite-rsync.sh:17,23` — StrictHostKeyChecking=no → yes**

   ```bash
   # Eski:
   -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

   # Yeni:
   -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=yes -o ConnectTimeout=10"
   ```

**`[Deploy]`** `deploy/scripts/offsite-rsync.sh` — `StrictHostKeyChecking=no → yes` → commit + push

**`[Node]`** node1'de **bir kez manuel** (root olarak):
```bash
ssh-keyscan -H 10.10.0.4 >> /root/.ssh/known_hosts
```
Bu adım bootstrap'e eklenemez (key değişirse stale kalır) — her yeni node3 kurulumunda
tekrarlanmalı. Sonrasında `git pull` yeterli, restart gerekmez.

**Kabul kriterleri:**
- Script node3'e başarıyla bağlanıyor (known_hosts ayarlı)
- `StrictHostKeyChecking=no` satırı kalmadı

---

## Faz 2 — Önemli (Önümüzdeki Sprint)

---

### TASK-H4 · .gitignore .env.* Exception Kaldır

**Bulgu:** H4 | **Önem:** 🔴 HIGH

**Sorun:**
`.gitignore:13` → `!deploy/scale/resources/.env.*` satırı dolu `.env.*` dosyalarının
git history'ye girmesine kapı açıyor.

**Adımlar:**

1. **`.gitignore:13` — İstisna satırını kaldır**

   ```diff
   - !deploy/scale/resources/.env.*
   ```

2. **Template dosyalarını yeniden adlandır**

   ```bash
   # node1
   mv deploy/scale/resources/node1/.env.production \
      deploy/scale/resources/node1/.env.production.template

   # node3
   mv deploy/scale/resources/node3/.env.production \
      deploy/scale/resources/node3/.env.production.template
   mv deploy/scale/resources/node3/.env.staging \
      deploy/scale/resources/node3/.env.staging.template
   ```

3. **`.gitignore`'a template uzantısını ekle**

   ```
   # Gerçek .env dosyaları asla git'te
   deploy/scale/resources/.env.*
   # Template'ler (boş değerler) git'te takip edilir
   !deploy/scale/resources/**/*.template
   ```

4. **Bootstrap scriptlerinde referansları güncelle**

   `bootstrap_node1.sh` ve `bootstrap_node3.sh` içinde `.env.production` → `.env.production.template`
   olarak kopyalama adımlarını güncelle (eğer varsa).

5. **`README.md` kurulum adımlarını güncelle** — `.env.production.template`'i kopyala, dolduran kişi adını değiştirsin.

**`[Deploy]`** `.gitignore`, `deploy/scale/resources/node1/.env.production.template`,
`deploy/scale/resources/node3/*.template`, `bootstrap_node1.sh` + `bootstrap_node3.sh`
(referans güncellemesi) → commit + push

**`[Node]`** VPS'lerdeki gerçek `.env.*` dosyaları (dolu, `/var/www/teqlif/deploy/scale/resources/`
altında) git'te artık izlenmeyeceği için dokunulmaz. `TEQLIF_ENV_FILE` tam path gösterdiği için
isim değişikliği VPS'i etkilemiyor. `git pull` yeterli.

**Kabul kriterleri:**
- `git status` dolu `.env.*` dosyasını `Changes to be staged` olarak göstermiyor
- `.template` dosyaları git'te görünür, dolu `.env.*` dosyaları görünmez
- VPS'lerde gerçek dosya adları değişmedi (`TEQLIF_ENV_FILE` zaten tam path gösteriyor)

---

### TASK-M3 · wallet.py Pydantic Model + Bakiye Kontrolü

**Bulgu:** M3 | **Önem:** 🟡 MEDIUM

**Sorun:**
`transfer_tuci` fonksiyonu `dict` alıyor — tip yoklama yok, negatif/None amount mümkün.
Use case'de bakiye kontrolü `# Şimdilik bakiye yeterli varsayalım` TODO'su.

**Adımlar:**

1. **`backend/app/routers/wallet.py` — Pydantic model tanımla ve kullan**

   Router'ın hemen üstüne:
   ```python
   class TransferRequest(BaseModel):
       recipient_id: UUID
       amount: Decimal = Field(gt=Decimal("0"), le=Decimal("10000"))
   ```

   Endpoint imzasını güncelle:
   ```python
   async def transfer_tuci(data: TransferRequest, current_user = Depends(get_current_user), ...):
   ```

2. **`backend/app/use_cases/wallet/` — Bakiye kontrolü uygula**

   `TransferTuciCommand.execute()` içindeki TODO'yu gider:
   ```python
   if sender.tuci_balance < data.amount:
       raise InsufficientFundsException()  # AppException subclass
   ```

   `InsufficientFundsException` zaten `ErrorMapper`'da `INSUFFICIENT_FUNDS_STD` kodu var
   — Flutter tarafı bu hatayı tanır.

**`[Deploy]`** `backend/app/routers/wallet.py`, `backend/app/use_cases/wallet/` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- `{"recipient_id": null, "amount": -999}` → `422 Unprocessable Entity`
- Yetersiz bakiyede `400 + INSUFFICIENT_FUNDS_STD` döner
- Transfer sadece bakiye yeterliyse tamamlanır

---

### TASK-M1 · JWT Token Log Truncation

**Bulgu:** M1 | **Önem:** 🟡 MEDIUM

**Sorun:**
`auth.py:168` — decode hatasında tam JWT string log'a yazılıyor.

**Adımlar:**

1. **`backend/app/utils/auth.py:168` — Token'ı kırp**

   ```python
   # Eski:
   logger.error(f"[AUTH] get_current_user 401: Geçersiz token (raw_token={raw_token})")

   # Yeni:
   logger.error(f"[AUTH] get_current_user 401: Geçersiz token (raw_token={raw_token[:10]}...)")
   ```

**`[Deploy]`** `backend/app/utils/auth.py` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- Log'da token'ın sadece ilk 10 karakteri + `...` görünür
- Tek satır değişiklik — başka bir şeye dokunma

---

### TASK-M2 · Analytics Unauthenticated user_id Injection

**Bulgu:** M2 | **Önem:** 🟡 MEDIUM

**Sorun:**
Auth yoksa `payload.user_id` body'den alınıyor — başkasının profili manipüle edilebilir.

**Adımlar:**

1. **`backend/app/routers/analytics.py` — `track_interaction` endpoint'ini güncelle**

   `user_id` body'den gelen değer yerine yalnızca JWT'den türetilmeli:

   ```python
   # Eski mantık (body'den user_id):
   user_id = payload.user_id  # fallback

   # Yeni mantık:
   # Auth varsa → JWT'den al
   # Auth yoksa → None (anonim)
   # Client-supplied user_id asla kabul etme
   user_id: UUID | None = None
   if token := request.headers.get("Authorization", "").removeprefix("Bearer "):
       try:
           claims = decode_access_token(token)
           user_id = UUID(claims["sub"])
       except Exception:
           pass  # anonim devam et
   ```

2. **`backend/app/schemas/analytics.py` — `user_id` alanını request schema'dan kaldır**

   `TrackInteractionPayload.user_id` → sil veya `Annotated[UUID | None, Field(exclude=True)]`
   ile inputtan dışla.

**`[Deploy]`** `backend/app/routers/analytics.py`, `backend/app/schemas/analytics.py` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- Unauthenticated istek → `user_id=None` olarak kaydedilir
- Authenticated istek → `user_id` JWT'deki `sub`'dan alınır, body'den değil
- Body'ye başkasının `user_id`'si koymak artık etkisiz

---

### TASK-M5 · MinIO Console Bind Adresi Sabitle

**Bulgu:** M5 | **Önem:** 🟡 MEDIUM

**Sorun:**
`--console-address :9011` tüm interface'lere bağlı — UFW açıksa admin UI erişilebilir.

**Adımlar:**

1. **`deploy/scale/V1.3/node1/systemd/minio.service`**

   ```ini
   # Eski:
   --address :9010 --console-address :9011

   # Yeni (API WireGuard üzerinden, console sadece local):
   --address 10.10.0.1:9010 --console-address 127.0.0.1:9011
   ```

2. **`deploy/scale/V1.3/node3/systemd/minio.service`**

   ```ini
   # Yeni (node3 local only):
   --address 127.0.0.1:9010 --console-address 127.0.0.1:9011
   ```

3. **VPS'lerde servis dosyasını güncelle ve restart et**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart minio
   ```

**`[Deploy]`** `deploy/scale/V1.3/node1/systemd/minio.service`,
`deploy/scale/V1.3/node3/systemd/minio.service` → commit + push

**`[Node]`** Her iki node'da (güncellenen dosyayı sisteme kopyala ve restart et):
```bash
# node1:
sudo cp /var/www/teqlif/deploy/scale/V1.3/node1/systemd/minio.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl restart minio

# node3:
sudo cp /var/www/teqlif/deploy/scale/V1.3/node3/systemd/minio.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl restart minio
```

**Kabul kriterleri:**
- node1'den `curl http://10.10.0.1:9010/minio/health/live` → 200 (WireGuard üzerinden erişilir)
- Dışarıdan (gateway IP'si üzerinden) `9010` ve `9011` erişilemez
- node3 console sadece `127.0.0.1:9011` üzerinden erişilebilir

---

## Faz 3 — Hardening (Sonraki İterasyon)

---

### TASK-M6 · nginx Content-Security-Policy Header

**Bulgu:** M6 | **Önem:** 🟡 MEDIUM

**Sorun:**
`deploy/scale/V1.3/gateway/nginx/teqlif.conf`'ta CSP header yok — stored XSS için
execution context sınırlanmıyor.

**Adımlar:**

1. **`teqlif.conf` security headers bloğuna CSP ekle**

   ```nginx
   add_header Content-Security-Policy
     "default-src 'self';
      script-src 'self';
      object-src 'none';
      frame-ancestors 'none';"
     always;
   ```

   > **Not:** Flutter Web veya web panel varsa `script-src` ayarlanmalı. Şu an sadece
   > mobile API ise bu policy güvenli. Web dashboard açılırsa inline script ihtiyacı
   > `'nonce-{random}'` ile çözülür — `'unsafe-inline'` yazılmaz.

2. **gateway'de nginx reload et**

   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

3. **Browser'da `curl -I https://teqlif.com` → `content-security-policy` header'ı doğrula**

**`[Deploy]`** `deploy/scale/V1.3/gateway/nginx/teqlif.conf` → commit + push

**`[Node]`** gateway'de:
```bash
git pull
sudo nginx -t && sudo systemctl reload nginx
```

**Kabul kriterleri:**
- `curl -I` çıktısında `content-security-policy` görünür
- Mevcut mobile API endpoint'leri çalışmaya devam eder (CSP API response'ları etkilemez)

---

### TASK-M7 · alertmanager ExecStartPre Root Kaldır

**Bulgu:** M7 | **Önem:** 🟡 MEDIUM

**Sorun:**
`alertmanager.service`'te `+/bin/bash` ExecStartPre root olarak çalışıyor ve
`TELEGRAM_BOT_TOKEN` içeren dosyayı `/etc/alertmanager/` altına yazıyor.

**Adımlar:**

1. **`deploy/scale/V1.3/node3/systemd/alertmanager.service` — Template render adımını kaldır**

   ```ini
   # Kaldır:
   ExecStartPre=+/bin/bash -c 'envsubst < .../alertmanager.yml.template > /etc/alertmanager/alertmanager.yml'
   ```

2. **alertmanager'ı `--config.expand-env` ile başlat**

   ```ini
   ExecStart=/usr/local/bin/alertmanager \
     --config.file=/etc/alertmanager/alertmanager.yml.template \
     --storage.path=/var/lib/alertmanager \
     --config.expand-env
   ```

   `--config.expand-env` flag'i YAML içindeki `$TELEGRAM_BOT_TOKEN` ve
   `$TELEGRAM_CHAT_ID`'yi process environment'tan okur — render edilmiş dosyaya gerek kalmaz.

3. **Env var'ları systemd service'e ekle**

   ```ini
   EnvironmentFile=/etc/environment
   ```

   `/etc/environment`'ta zaten `TEQLIF_ENV_FILE` var; alertmanager token'ları da
   aynı mekanizmaya eklenir (bootstrap ile).

**`[Deploy]`** `deploy/scale/V1.3/node3/systemd/alertmanager.service` — `ExecStartPre` satırı
kaldırılır, `ExecStart`'a `--config.expand-env` eklenir, `EnvironmentFile=/etc/environment`
eklenir → commit + push

**`[Node]`** node3'te:
```bash
git pull
sudo cp /var/www/teqlif/deploy/scale/V1.3/node3/systemd/alertmanager.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl restart alertmanager
```
`/etc/alertmanager/alertmanager.yml.template` dosyasında token placeholder'ları
`$TELEGRAM_BOT_TOKEN` formatında olduğunu doğrula — değilse güncelle.

**Kabul kriterleri:**
- `sudo systemd-analyze security alertmanager` → daha yüksek skor
- `/etc/alertmanager/` altında render edilmiş token içeren dosya yok
- Alertmanager başarıyla başlıyor ve Telegram bildirimleri çalışıyor

---

### TASK-M8 · OCSP Stapling Aç

**Bulgu:** M8 | **Önem:** 🟡 MEDIUM

**Adımlar:**

1. **`deploy/scale/V1.3/gateway/nginx/teqlif.conf:45–46` — Stapling aktifleştir**

   ```nginx
   # Eski:
   ssl_stapling off;
   ssl_stapling_verify off;

   # Yeni:
   ssl_stapling on;
   ssl_stapling_verify on;
   ssl_trusted_certificate /etc/letsencrypt/live/teqlif.com/chain.pem;
   resolver 1.1.1.1 8.8.8.8 valid=300s;
   resolver_timeout 5s;
   ```

2. **Staging vhost bloğunu da güncelle (lines 187–188)**

3. **Test ve reload**

   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   openssl s_client -connect teqlif.com:443 -status | grep -A 10 "OCSP Response"
   ```

**`[Deploy]`** `deploy/scale/V1.3/gateway/nginx/teqlif.conf` → TASK-M6 ile aynı dosya,
aynı committe yapılabilir → push

**`[Node]`** gateway'de TASK-M6 ile aynı reload:
```bash
git pull
sudo nginx -t && sudo systemctl reload nginx
```

**Kabul kriterleri:**
- `openssl` çıktısında `OCSP Response Status: successful` görünür
- TLS handshake süresinde ölçülebilir iyileşme (OCSP round-trip ortadan kalkar)

---

### TASK-L3 · systemd Servis Hardening

**Bulgu:** L3 | **Önem:** ⚪ LOW

**Sorun:**
Hiçbir systemd servisinde sandbox direktifleri yok — compromised process kullanıcının
tüm dosyalarına erişebilir.

**Adımlar:**

1. **`deploy/scale/V1.3/node1/systemd/` ve `deploy/scale/V1.3/node3/systemd/` altındaki
   tüm `.service` dosyalarına ekle:**

   ```ini
   [Service]
   NoNewPrivileges=yes
   PrivateTmp=yes
   ProtectSystem=strict
   ProtectHome=yes
   ```

   > `ProtectSystem=strict` yazma iznini kısıtlar. Uygulama `/var/www`, `/etc` altına
   > yazıyorsa bu dizinler `ReadWritePaths=` ile açılmalı.
   >
   > Örnek (teqlif main service):
   > ```ini
   > ProtectSystem=strict
   > ReadWritePaths=/var/www/teqlif.com /var/log/teqlif
   > ```

2. **Her servis için restart sonrası `sudo systemd-analyze security <service>` çalıştır**
   — 4.0 üstü hedef.

**`[Deploy]`** `deploy/scale/V1.3/node1/systemd/*.service` ve
`deploy/scale/V1.3/node3/systemd/*.service` — tüm service dosyalarına direktifler eklenir
→ commit + push

**`[Node]`** Her node'da (servis başına):
```bash
git pull
# Değişen her .service dosyası için:
sudo cp /var/www/teqlif/deploy/scale/V1.3/<node>/systemd/<service>.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart <service>
```
`ProtectSystem=strict` eklendiğinde `ReadWritePaths` listesini doğrula — uygulama log/upload
dizinlerine yazabilmeli.

**Kabul kriterleri:**
- Tüm production servislerinde `NoNewPrivileges=yes` ve `PrivateTmp=yes` var
- `systemd-analyze security teqlif` → exposure level düşük
- Mevcut servis davranışı değişmedi (log, upload, DB dosyalarına erişim korundu)

---

### TASK-L1 · check-username Kimlik Doğrulama Guard

**Bulgu:** L1 | **Önem:** ⚪ LOW

**Sorun:**
`GET /api/auth/check-username?exclude_id=42` unauthenticated — user ID enumeration.

**Adımlar:**

1. **`backend/app/routers/auth.py:304` — `exclude_id` parametresini koru, auth guard ekle**

   ```python
   async def check_username(
       request: Request,
       username: str = "",
       exclude_id: int | None = None,
       db: AsyncSession = Depends(get_db),
       current_user = Depends(get_optional_user),  # None olabilir
   ):
       # exclude_id sadece authenticated user'ın kendi ID'si olabilir
       if exclude_id is not None:
           if current_user is None or current_user.id != exclude_id:
               exclude_id = None  # yetkisiz exclude_id → yoksay
   ```

   `get_optional_user` dependency zaten varsa kullan, yoksa `get_current_user`'dan türet.

**`[Deploy]`** `backend/app/routers/auth.py` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- Unauthenticated istek `exclude_id` ile → `exclude_id` yoksayılır, ID sızdırılmaz
- Authenticated istek kendi `exclude_id`'si ile → normal çalışır (profil edit use case)
- Başka birinin `exclude_id`'si → yoksayılır

---

### TASK-L2 · client-log Auth + Sanitization

**Bulgu:** L2 | **Önem:** ⚪ LOW

**Sorun:**
`/api/client-log` unauthenticated — newline injection ile sahte server log satırı üretilebilir.

**Adımlar:**

1. **`backend/app/routers/client_log.py` — String sanitizasyonu ekle**

   Log alanlarına gelen değerlerde newline ve control character temizle:

   ```python
   def _sanitize(value: str, max_len: int = 500) -> str:
       return re.sub(r'[\r\n\t\x00-\x1f\x7f]', ' ', value)[:max_len]
   ```

   `tag`, `message`, `error`, `details` alanlarını kaydetmeden önce `_sanitize()` ile geçir.

2. **Opsiyonel (düşük öncelik): static app secret ile minimal auth**

   ```python
   X_CLIENT_SECRET = Header(None)

   async def log_client_event(..., x_client_secret: str | None = X_CLIENT_SECRET):
       if x_client_secret != settings.client_log_secret:
           raise HTTPException(401)
   ```

   `CLIENT_LOG_SECRET` `.env.*` template'e eklenir.

**`[Deploy]`** `backend/app/routers/client_log.py` → commit + push

**`[Node]`** node1: `sudo teqlif-restart`

**Kabul kriterleri:**
- Newline içeren `message` değeri log'da tek satır olarak görünür
- Log injection ile sahte satır üretilemiyor

---

## Durum Tablosu

| ID | Görev | Faz | Durum |
|----|-------|-----|-------|
| TASK-H1 | SQL Injection — whitelist + SQLAlchemy case() | 1 | ⬜ Bekliyor |
| TASK-H2 | Admin şifre rate limit | 1 | ⬜ Bekliyor |
| TASK-M4 | Admin Google verify rate limit | 1 | ⬜ Bekliyor |
| TASK-H5 | Redis backup auth | 1 | ⬜ Bekliyor |
| TASK-H3 | rsync StrictHostKeyChecking | 1 | ⬜ Bekliyor |
| TASK-H4 | .gitignore .env.* exception kaldır | 2 | ⬜ Bekliyor |
| TASK-M3 | wallet.py Pydantic + bakiye kontrolü | 2 | ⬜ Bekliyor |
| TASK-M1 | JWT log truncation | 2 | ⬜ Bekliyor |
| TASK-M2 | Analytics user_id injection | 2 | ⬜ Bekliyor |
| TASK-M5 | MinIO bind adresi | 2 | ⬜ Bekliyor |
| TASK-M6 | nginx CSP header | 3 | ⬜ Bekliyor |
| TASK-M7 | alertmanager root ExecStartPre kaldır | 3 | ⬜ Bekliyor |
| TASK-M8 | OCSP stapling | 3 | ⬜ Bekliyor |
| TASK-L3 | systemd hardening | 3 | ⬜ Bekliyor |
| TASK-L1 | check-username auth guard | 3 | ⬜ Bekliyor |
| TASK-L2 | client-log sanitization | 3 | ⬜ Bekliyor |
| — | L4 WireGuard topoloji | Kabul | ✅ Değiştirilmeyecek |
| — | L5 Loki 0.0.0.0 | Kabul | ✅ Değiştirilmeyecek |
