# Teqlif Scale V1.4 - Test Senaryoları (Test Cases)

## Görev 1.0: Ortak İlk Hazırlık (README.md) Testi
**Amaç:** `V1.4/README.md` dosyasının, yeni bir sunucunun (Node4 veya Node5) sıfırdan "tucibeyin" kullanıcısı ile repo klonlama aşamasına kadar getirilmesini eksiksiz anlattığını doğrulamak.

**Test Adımları (Manuel Gözden Geçirme):**
1. `deploy/scale/V1.4/README.md` dosyasını açıp okuyun.
2. `tucibeyin` kullanıcısının oluşturulup `sudo` yetkisi verildiğini onaylayın.
3. SSH anahtar erişimi adımlarının şifresiz giriş için doğru yazıldığını onaylayın.
4. Repo klonlama yolunun V1.4 mantığına uygun olarak (`/var/www/teqlif.com`) verildiğini onaylayın.

**Beklenen Sonuç:** Belgenin, V1.4 altyapı scriptlerini (`bootstrap_*.sh`) çalıştırmadan önceki tüm manuel sunucu hazırlık operasyonlarını net, güvenli ve eksiksiz bir şekilde açıklaması.

**Durum:** ✅ Tamamlandı (Commit: 12e4afad)

---

## Görev 1.1: Node5 (Core) Resources Testi
**Amaç:** `V1.4/node5/resources` dizini içerisindeki sıfırdan yazılmış scriptlerin, V1.4 (Clean Architecture & Generic Pathing) standartlarına uyduğunu onaylamak.

**Test Adımları (Review):**
1. `bootstrap_node5.sh` dosyasında hardcode (sabit) path kalmadığını (`RESOURCES_DIR` kullanıldığını) doğrula.
2. `bootstrap_node5.sh` içerisinde eski systemd dosyalarındaki `EnvironmentFile` yolunun V1.4'e dinamik (`sed` ile) çevrildiğini onayla.
3. `.env.production.template` içerisinde statik LiveKit/Minio yerine `EDGE_MINIO_URLS`, `EDGE_LIVEKIT_URLS` ve `MINIO_STORAGE_QUOTA_PERCENT` gibi parametrelerin bulunduğunu onayla.
4. `apply_pg_tuning.sh` scriptinin 7.8GB RAM (Node5) donanımına göre hazırlandığını ve `apply_ch_tuning.sh` scriptinin ClickHouse'u tam 2.0GB'a limitlediğini (Deli Gömleği / OOM Koruması) doğrula.

**Beklenen Sonuç:** Tüm yapılandırmaların "Sıfır Statik Veri" kuralına ve Core yapısına uygun tasarlanmış olması.

**Durum:** ✅ Tamamlandı (Commit: 6643f126)

---

## Görev 1.2: Node4 (Edge 2) Resources Testi
**Amaç:** Node4'ün "Saf Medya ve Storage (Edge 2)" rolüne uygun bir şekilde (Core servislerinden tamamen arındırılarak) yapılandırıldığını doğrulamak.

**Test Adımları (Review):**
1. `node4_production_requirements.txt` dosyasının backend bağımlılıklarından (`fastapi`, `sqlalchemy` vb.) arındırıldığını, sadece `edge-metrics-agent` gereksinimlerini içerdiğini onayla.
2. `bootstrap_node4.sh` içerisinde 8GB Swap alanının (Media/Storage buffer) yapılandırıldığını doğrula.
3. `.env.production.template` içerisinde Core servis (Postgres vb.) bilgilerinin OLMADIĞINI, sadece `CORE_REDIS_URL`, `LIVEKIT_*` ve `MINIO_*` ayarlarının bulunduğunu onayla.
4. `node4_services.sh` içerisinde backend/veritabanı servislerinin değil, sadece Edge servislerinin (livekit, minio, redis-server, edge-metrics-agent) listelendiğini doğrula.

**Beklenen Sonuç:** Node4'ün hiçbir şekilde gereksiz Core paketlerini veya ayarlarını barındırmaması, tamamen "Edge" görevine izole edilmesi.

**Durum:** ✅ Tamamlandı (Commit: df3b06ff)

---

## Görev 1.3: Node1 (Edge 1) Resources Testi
**Amaç:** V1.3'te "Monolith Core" rolünde çalışan Node1'in, V1.4 ile tamamen "Saf Medya ve Storage (Edge 1)" rolüne indirgendiğini onaylamak.

**Test Adımları (Review):**
1. `node1_production_requirements.txt` dosyasının Node4 ile aynı izolasyon seviyesinde olduğunu (sadece edge-metrics) doğrula.
2. `bootstrap_node1.sh` içerisinde Node1'in geçmiş V1.3 Core rolüne atıfta bulunan "Eski servisleri durdurma uyarıları"nın yer aldığını kontrol et.
3. `.env.production.template` içerisinde statik Postgres, Google OAuth vs. gibi Core servis ayarlarının tamamen SİLİNDİĞİNİ ve sadece Edge profili (MinIO, LiveKit, Edge Redis) ayarlarının bırakıldığını onayla.
4. `node1_services.sh` scriptinin artık teqlif, teqlif-worker veya postgresql GİBİ servisleri İÇERMEDİĞİNİ onayla.

**Beklenen Sonuç:** Node1'in eski karmaşık Monolith yüklerinden tamamen arındırılmış, Node4 (Edge 2) ile asimetrik ikiz olacak şekilde kodlanmış olması.

**Durum:** ✅ Tamamlandı (Commit: c49ea325)

---

## Görev 1.4: Gateway, Node2 ve Node3 Testi
**Amaç:** Kalan node'ların (Gateway ve AI Proxy/Staging) V1.4 Core-Edge topolojisi ile entegre olduğunu onaylamak.

**Test Adımları (Review):**
1. `gateway/resources/certbot_gateway.sh` scriptinde Nginx proxy_pass ayarının `10.10.0.1` yerine `10.10.0.5` (Yeni Node5 Core IP'si) olarak güncellendiğini (`sed` komutu) doğrula.
2. Node2 (AI Proxy) ve Node3 (Monitor/Staging/AI Proxy) için `bootstrap` scriptlerinin yazıldığını ve V1.4'te veritabanı barındırmadıklarını onayla.
3. Her üç node'un `bootstrap` scriptinde `Clean State` (Önbellek temizlik) kuralına uyulduğunu doğrula.

**Beklenen Sonuç:** Tüm sunucu yelpazesinin tam V1.4 (Orchestrator=Node5, Edge=Node1/4, AI Proxy=Node2/3, Gateway=Gateway) senaryosuna göre scriptlerinin tamamlanması.

**Durum:** ✅ Tamamlandı (Commit: 8827ba8b)

---

## Görev 1.5: Cloudflare DNS Yapılandırması Testi
**Amaç:** V1.4 Multi-Edge mimarisi için zorunlu olan dinamik DNS altyapısının belgelenmesi ve eski yüklerin temizlenmesi.

**Test Adımları (Review):**
1. `deploy/scale/V1.4/plan.md` dosyasının en altındaki **Faz 7: Cloudflare DNS Yapılandırması** bölümünü aç ve incele.
2. Gateway için `teqlif.com` (Frontend statik sunumu) ve `api.teqlif.com` (Backend proxy) yönlendirmelerinin **Proxied** olarak `94.16.105.135` (Gateway) hedefine ayarlandığını doğrula.
3. Edge sunucuları (Node1, Node4) ve Staging (Node3) için sırasıyla `live1`/`minio1`, `live2`/`minio2`, `live-staging`/`minio-staging` olarak özel subdomain kayıtlarının açıldığını ve bunların Cloudflare Proxy'den bağımsız (**DNS Only**) ayarlandığını doğrula.
4. Eski, tekil (single-point-of-failure) `live.teqlif.com` gibi kayıtların uyarı blokunda silinecekler listesine eklendiğini kontrol et.
5. `plan.md` içerisindeki **Faz 8: SSL (Sertifika) Yönetimi** bölümünü kontrol et, Node1 ve Node4'te standalone certbot alınabilmesi için scriptlerin (`certbot_node1.sh`, `certbot_node4.sh`) eklendiğini onayla.
6. `node1_cleanup.sh` içerisine eski monolitik yapının SSL kalıntılarını silmek için `/etc/letsencrypt` kaldırma komutunun eklendiğini doğrula.

**Beklenen Sonuç:** Tüm DNS trafiğinin Cloudflare üzerinden doğru Proxy kuralları (WebRTC için bypass, API için Proxy) ile Core ve Edge node'lara yönlendirilmesi için tam talimat tablosunun hazırlanması ve Multi-Edge SSL stratejisinin kusursuz otomatize edilmesi.

**Durum:** ✅ Tamamlandı (Commit: 26cf95b9)

---

## Görev 1.6: WireGuard 6-Node Mesh Testi
**Amaç:** Veritabanı ve Staging trafiğinin güvenle akabilmesi için 6 sunuculuk iç ağın (10.10.0.x/24) doğru kurulduğunu teyit etmek.

**Test Adımları (Review):**
1. `deploy/scale/V1.4/wireguard/` dizinindeki tüm `*-wg0.conf` dosyalarını aç.
2. Her dosyanın içinde Node5 (Core - 10.10.0.5) ve Node4 (Edge 2 - 10.10.0.6) IP'lerinin `[Peer]` olarak eklendiğini doğrula.
3. IP havuzunun `plan.md` Faz 1.5 ile eşleştiğini doğrula.

**Beklenen Sonuç:** Tüm sunucuların sadece WireGuard tüneli üzerinden güvenle haberleşebileceği, yeni mimariye uygun Full-Mesh altyapısının kurulması.

**Durum:** ✅ Tamamlandı (Commit: pending)

---

## Görev 2.4 & 2.5: ClickHouse Refactor Testi
**Amaç:** `documents/clickhouse/V1.0/findings.md` dosyasındaki optimizasyonların backend koduna başarıyla entegre edildiğini teyit etmek.

**Test Adımları (Review):**
1. Backend `app/models/` altındaki analitik ve event şemalarında `user_id` ve `listing_id` tiplerinin `int` (UInt32) yapıldığını doğrula.
2. Background flush worker'ında (FastAPI) `FLUSH_INTERVAL = 30` ve `MAX_BATCH = 5000` değerlerinin güncellendiğini kontrol et.
3. Şema oluşturma (Schema Builder) fonksiyonlarında `ZSTD(3)` ve `TTL` (30 Days vb.) komutlarının eklendiğini doğrula.

**Beklenen Sonuç:** ClickHouse'un CPU şişmelerinin (I/O) ve gereksiz depolama kayıplarının backend kod refaktörü ile kalıcı olarak engellenmesi.

**Durum:** ✅ Tamamlandı (Commit: d694afba)

---

## Görev 3.2: Storage Media Routing & Deletion Testi
**Amaç:** `storage_service.py` içindeki URL tabanlı otonom silme algoritmasının, veriyi sadece barındırıldığı (shard edilmiş) Edge sunucusundan sildiğini kanıtlamak.

**Test Adımları (Review):**
1. Backend kodlarında `delete_object(url)` metodunun incelenmesi. URL içerisindeki domain (veya IP) ile `.env` dosyasındaki MinIO havuzunun (Connection Pool) doğru eşleştiğini doğrula.
2. Silme metodunun tüm node'lara gitmediğini, sadece ilgili node'a gönderildiğini kontrol et.

**Beklenen Sonuç:** Bir resim Node4'e yüklendiyse (Standalone), silme talebinin de Node1'e değil yalnızca Node4'e (Nokta atışı) gitmesi.

**Durum:** ✅ Tamamlandı (Commit: 5920a27e)

---

## Görev 2.1 & 2.2: Dinamik Config ve Metrics Agent Testi
**Amaç:** `app/config.py` dosyasının statik URL'lerden kurtulduğunu ve `edge_metrics_agent.py`'nin Core Redis'e başarıyla telemetri bastığını kanıtlamak.

**Test Adımları (Review):**
1. `config.py` içerisinde `EDGE_LIVEKIT_URLS` ve `EDGE_MINIO_URLS` değişkenlerinin Pydantic validator'ü ile parse edilip bir listeye dönüştüğünü doğrula.
2. `scripts/edge_metrics_agent.py` dosyasında `psutil` kullanılarak CPU ve Disk kotalarının ölçüldüğünü ve `redis.set(f"edge:metrics:{ip}", ...)` formatında Node5'e gönderildiğini doğrula.

**Durum:** ✅ Tamamlandı (Commit: f198cbe5)

---

## Görev 2.3, 3.1 & 3.3: Generic Orchestrator ve VoIP Testi
**Amaç:** `edge_orchestrator.py` sınıfının Teknoloji Bağımsız (Strategy Pattern) çalıştığını ve VoIP/Yayın sistemlerinin buraya doğru bağlandığını doğrulamak.

**Test Adımları (Review):**
1. `edge_orchestrator.py` içinde `allocate_node(service_type)` metodunun varlığını ve Media vs. Storage için farklı metrik kararları verdiğini doğrula.
2. `stream_utils.py` ve `calls.py` (VoIP) içerisinde `settings.livekit_url` çağrılarının TAMAMEN SİLİNDİĞİNİ ve yerine `orchestrator.allocate_node()` metodunun kullanıldığını doğrula.

**Durum:** ✅ Tamamlandı (Commit: 163d04a6)

---

## Aşama 4: Canlı Sunucu Operasyonları (Execution) Testi
**Amaç:** Backend refaktörleri bittikten sonra canlı sunucuların (SSH) V1.4 mimarisine, "Sıfır Veri Göçü" kuralına ve "Frontend Decoupling" stratejisine uygun şekilde geçmesini doğrulamak.

**Test Adımları:**
1. Node5, Node4 ve Node1'e SSH ile girilip `bootstrap` scriptlerinin hatasız çalıştığını onayla. (Node5 Test Edildi ✅)
2. Node1'deki eski verilerin taşınmadığını, sistemin sıfır veritabanı ve sıfır medya ile "Clean Start" yaptığını doğrula (Migration İptali). (Migration İptal Edildi ✅)
3. Gateway Nginx `teqlif.com.conf` devresi açıldığında; tarayıcıdan `teqlif.com` ve `staging.teqlif.com`'a girilince statik frontend'in Gateway'den sunulduğunu, `api.teqlif.com` ve `api-staging.teqlif.com` üzerinden ise Node5 ve Node3 API'lerine sorunsuz bağlanıldığını onayla. (Gateway proxy_pass konfigürasyonu tamamlandı ✅)

**Durum:** ⏳ Faz 6 (Canlıya Geçiş) esnasında tüm Node'lar tamamlandığında test edilecek. (Kısmen Tamamlandı)

---

## Görev 5 & 6 & 7: Gateway, WireGuard Mesh ve SSL Testi
**Amaç:** Kalan tüm ağ düğümlerinin (Node2, Node3, Gateway) WireGuard mesh ağına sorunsuz katıldığını ve Gateway'in HTTPS trafiğini başarıyla şifreleyip proxy ettiğini doğrulamak.

**Test Adımları (Execution):**
1. Gateway `bootstrap_gateway.sh` ve `certbot_gateway.sh` tamamlandıktan sonra tarayıcıdan `https://api.teqlif.com/cf-health` adresine girip (200 OK) alındığını onayla.
2. Tüm Node'ların (1'den 6'ya) `/etc/wireguard/wg0.conf` dosyalarına Public Key'ler yazıldıktan sonra Node1 üzerinden `ping 10.10.0.5` ve `ping 10.10.0.2` yapılabildiğini (Full-Mesh tüneli) doğrula.
3. Gateway Nginx SSL testlerinin `ssllabs.com` üzerinden "A" skoru aldığını (isteğe bağlı) teyit et.

**Durum:** ⏳ Faz 6 ve 7 (Canlıya Geçiş) tamamen bittiğinde test edilecek.

---

## Görev 8: Canlı .env Config Denetimi (Key-by-Key)

**Amaç:** Her node'da VPS'te çalışan `.env` dosyalarını key bazında doğrulamak. Değerlerin dolu, doğru formatta ve cross-node tutarlı olduğunu teyit etmek.

**Durum:** ⏳ Devam ediyor — Adım 8.A'dan başla.

---

### Adım 8.A — Pre-Flight: Tüm Node'larda Senkronizasyon ⬅ BURADAN BAŞLA

**Neden önce bu?**
Son commit'lerde template hataları düzeltildi (`fa0a9cfd`). `sudo teqlif-restart` üç işi birden yapar:
1. `git pull --ff-only` → template düzeltmelerini çeker
2. `env sync` → şablonda olup `.env`'de eksik keyleri ekler (node3 staging'e `CAPTCHA_*` eklenir)
3. Servisleri yeniden başlatır

Her node'da sırayla çalıştır (edge'lerden başla, core son):

```bash
# node1 → node4 → node2 → node3 → node5 → gateway
sudo teqlif-restart
```

Her node'dan "✓ Tüm servisler başarıyla çalışıyor" çıktısı onaylandıktan sonra sonraki node'a geç.

**Durum:**
- [ ] node1
- [ ] node4
- [ ] node2
- [ ] node3
- [ ] node5
- [ ] gateway

---

### Adım 8.B — Bilinen Mevcut Değer Hataları (Manuel Düzeltme)

`env sync` sadece **eksik** key ekler; **var olan yanlış değerleri düzeltemez.**
Teqlif-restart tamamlandıktan sonra şunları kontrol et ve gerekirse düzelt:

**node3 — `.env.production` → REDIS_URL şifre kontrolü:**
```bash
grep "^REDIS_URL" /var/www/teqlif.com/backend/.env.production
# Beklenen: redis://:<ŞIFRE>@10.10.0.5:6379/1
# Eğer şifre yoksa (redis://10.10.0.5:6379/1 veya redis://@10.10.0.5...):
#   nano ile düzelt → REDIS_URL="redis://:<CORE_REDIS_SIFRE>@10.10.0.5:6379/1"
sudo systemctl restart teqlif-ai-proxy
```

**node5 — `.env.production` → EDGE_LIVEKIT_URLS scheme kontrolü:**
```bash
grep "^EDGE_LIVEKIT_URLS" /var/www/teqlif.com/backend/.env.production
# Beklenen: http:// (https:// ise WireGuard üzerinde TLS sertifikası yok → hata)
# Eğer https:// varsa:
sed -i 's|EDGE_LIVEKIT_URLS="https://|EDGE_LIVEKIT_URLS="http://|g' \
  /var/www/teqlif.com/backend/.env.production
sudo systemctl restart teqlif teqlif-worker teqlif-worker-critical
```

**Durum:**
- [ ] node3 REDIS_URL kontrol edildi
- [ ] node5 EDGE_LIVEKIT_URLS kontrol edildi

---

### Adım 8.C — node3 Staging CAPTCHA Değerlerini Doldur

Env sync `CAPTCHA_ENABLED=True`, `CAPTCHA_PROVIDER=`, `CAPTCHA_SECRET_KEY=` ekledi.
Provider ve secret key boş — doldur:

```bash
# node3'te
grep "^CAPTCHA" /var/www/teqlif.com/backend/.env.staging
# CAPTCHA_PROVIDER ve CAPTCHA_SECRET_KEY boşsa nano ile doldur (node5 ile aynı değerler)
nano /var/www/teqlif.com/backend/.env.staging
sudo systemctl restart teqlif-staging teqlif-worker-staging teqlif-worker-critical-staging
```

**Durum:** ⏳

---

### Adım 8.1 — node2: backend/.env.production (Review)

---

### Adım 8.1 — node2: backend/.env.production (AI Proxy 1)

**Komut:** `cat /var/www/teqlif.com/backend/.env.production`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `AI_PROXY_INTERNAL_TOKEN` | Dolu, tahmin edilemez string | ⚠️ node3 ve node5 ile **aynı** olmalı |
| `GROQ_API_KEY` | Dolu, `gsk_...` ile başlar | — |
| `GEMINI_API_KEY` | Dolu | — |
| `SENTRY_BACKEND_DSN` | Dolu VEYA bilinçli boş | Optional |
| `REDIS_URL` | `redis://:<şifre>@10.10.0.5:6379/1` | Şifre dolu, host=10.10.0.5, DB=1 |
| `CF_ZONE_ID` | Dolu, CF Zone ID | CF panelinden alınır |
| `CF_DNS_RECORD_ID` | Dolu, A kaydı ID'si | CF API ile doğrulanabilir |
| `CF_API_TOKEN` | Dolu | Sadece node2'de olmalı |

**Durum:** ⏳

---

### Adım 8.2 — node3: backend/.env.production (AI Proxy 2)

**Komut:** `cat /var/www/teqlif.com/backend/.env.production`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `AI_PROXY_INTERNAL_TOKEN` | Dolu, tahmin edilemez string | ⚠️ node2 ve node5 ile **aynı** olmalı |
| `GROQ_API_KEY` | Dolu, `gsk_...` ile başlar | — |
| `GEMINI_API_KEY` | Dolu | — |
| `SENTRY_BACKEND_DSN` | Dolu VEYA bilinçli boş | Optional |
| `REDIS_URL` | `redis://:<şifre>@10.10.0.5:6379/1` | ⚠️ **BİLİNEN BUG:** Template'de şifre eksikti; VPS'teki değeri kontrol et |
| `TELEGRAM_BOT_TOKEN` | Gerçek token (DUMMY_TOKEN değil) | Alertmanager bildirimleri için gerekli |
| `TELEGRAM_CHAT_ID` | Gerçek chat ID (123456789 değil) | Negatif sayı olabilir (grup kanalı) |

**Durum:** ⏳

---

### Adım 8.3 — node3: backend/.env.staging (Staging Backend)

**Komut:** `cat /var/www/teqlif.com/backend/.env.staging`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `DATABASE_URL` | `postgresql+asyncpg://teqlif_staging:<şifre>@127.0.0.1:5432/teqlif_staging` | Lokal DB, şifre dolu; placeholder `<STAGING_DB_PASSWORD>` |
| `REDIS_URL` | `redis://:<şifre>@127.0.0.1:6379/0` | Lokal Redis, şifre dolu |
| `SECRET_KEY` | Dolu, uzun rastgele string | JWT imzalama — node5 ile farklı olmalı |
| `ALGORITHM` | `HS256` | Sabit değer |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `43200` (30 gün) | Sabit değer |
| `UPLOAD_DIR` | `/var/www/teqlif.com/uploads_staging` | Staging upload dizini |
| `BREVO_API_KEY` | Dolu | E-posta servisi |
| `BREVO_SENDER_EMAIL` | `staging@teqlif.com` | Staging sender |
| `BREVO_SENDER_NAME` | `Teqlif Staging` | — |
| `EDGE_LIVEKIT_URLS` | `"http://127.0.0.1:7880"` | Staging için lokal LiveKit |
| `LIVEKIT_API_KEY` | Dolu | ⚠️ node1, node4, node5 ile **aynı** olmalı |
| `LIVEKIT_API_SECRET` | Dolu | ⚠️ node1, node4, node5 ile **aynı** olmalı |
| `EDGE_MINIO_URLS` | `"http://127.0.0.1:9010"` | Staging için lokal MinIO |
| `MINIO_ACCESS_KEY` | Dolu | ⚠️ node1/node4 MINIO_ROOT_USER ile **aynı** olmalı |
| `MINIO_SECRET_KEY` | Dolu | ⚠️ node1/node4 MINIO_ROOT_PASSWORD ile **aynı** olmalı |
| `MINIO_BUCKET` | `teqlif-staging` | Staging bucket |
| `MINIO_DM_BUCKET` | `teqlif-dm-staging` | Staging DM bucket |
| `MINIO_SECURE` | `False` | HTTP için False |
| `MINIO_REGION` | `us-east-1` | MinIO sabit değer |
| `MINIO_STORAGE_QUOTA_PERCENT` | `80` | — |
| `EDGE_METRICS_INTERVAL_SEC` | `3` | — |
| `NODE2_AI_PROXY_URL` | `"http://10.10.0.3:8080"` | node2 WireGuard IP |
| `NODE3_AI_PROXY_URL` | `"http://10.10.0.4:8080"` | node3 WireGuard IP |
| `AI_PROXY_INTERNAL_TOKEN` | Dolu | ⚠️ node2, node3 prod, node5 ile **aynı** olmalı |
| `FIREBASE_SERVICE_ACCOUNT` | Dosya path veya JSON string | FCM push için gerekli |
| `SENTRY_BACKEND_DSN` | Dolu VEYA bilinçli boş | Optional |
| `GOOGLE_CLIENT_ID` | Dolu | Google OAuth |
| `ADMIN_EMAIL` | Dolu, geçerli e-posta | — |
| `ADMIN_PASSWORD_HASH` | Dolu, bcrypt hash (`$2b$...`) | — |
| `CAPTCHA_ENABLED` | `True` | node5 ile aynı — mock mod değil, gerçek doğrulama |
| `CAPTCHA_PROVIDER` | Dolu | ⚠️ node5 ile **aynı** olmalı |
| `CAPTCHA_SECRET_KEY` | Dolu | ⚠️ node5 ile **aynı** olmalı |
| `DB_POOL_SIZE` | `20` | Staging default |
| `DB_MAX_OVERFLOW` | `10` | Staging default |
| `DB_POOL_TIMEOUT` | `30` | Staging default |
| `DB_POOL_RECYCLE` | `1800` | Staging default |
| `APNS_KEY_PATH` | Dosya path VEYA boş | iOS VoIP — opsiyonel staging'de |
| `APNS_KEY_ID` | Dolu VEYA boş | — |
| `APNS_TEAM_ID` | Dolu VEYA boş | — |
| `APNS_CERT_PATH` | Dosya path VEYA boş | — |
| `IOS_BUNDLE_ID` | `teqlif` | — |
| `APNS_USE_SANDBOX` | `True` | Staging için True |
| `SITE_URL` | `https://staging.teqlif.com` | — |
| `DEBUG` | `True` | Staging için True |
| `WEB_APP_ENABLED` | `True` | Staging web aktif |
| `USE_PGBOUNCER` | `False` | — |
| `CLICKHOUSE_HOST` | `localhost` | Staging ClickHouse lokal |
| `CLICKHOUSE_PORT` | `8123` | — |
| `CLICKHOUSE_DB` | `default` | — |

**Durum:** ⏳

---

### Adım 8.4 — node5: backend/.env.production (Core Backend)

**Komut:** `cat /var/www/teqlif.com/backend/.env.production`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `DATABASE_URL` | `postgresql+asyncpg://teqlif:<şifre>@127.0.0.1:5432/teqlif` | Lokal DB, şifre dolu |
| `REDIS_URL` | `redis://:<şifre>@10.10.0.5:6379/0` | Lokal Redis (WG IP), şifre dolu, DB=0 |
| `SECRET_KEY` | Dolu, uzun rastgele string | JWT — node3 staging ile farklı olmalı |
| `ALGORITHM` | `HS256` | Sabit değer |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `43200` (30 gün) | Sabit değer |
| `UPLOAD_DIR` | `/var/www/teqlif.com/uploads` | Production upload dizini |
| `BREVO_API_KEY` | Dolu | E-posta servisi |
| `BREVO_SENDER_EMAIL` | Dolu, gerçek gönderici adresi | `noreply@teqlif.com` gibi |
| `BREVO_SENDER_NAME` | `Teqlif` | — |
| `EDGE_LIVEKIT_URLS` | `"http://10.10.0.1:7880,http://10.10.0.6:7880"` | node1 ve node4 — iki URL; WireGuard tünel zaten şifreli, TLS gereksiz |
| `LIVEKIT_API_KEY` | Dolu | ⚠️ node1, node4 ile **aynı** olmalı |
| `LIVEKIT_API_SECRET` | Dolu | ⚠️ node1, node4 ile **aynı** olmalı |
| `EDGE_MINIO_URLS` | `"http://10.10.0.1:9010,http://10.10.0.6:9010"` | node1 ve node4 — iki URL |
| `MINIO_ACCESS_KEY` | Dolu | ⚠️ node1/node4 MINIO_ROOT_USER ile **aynı** olmalı |
| `MINIO_SECRET_KEY` | Dolu | ⚠️ node1/node4 MINIO_ROOT_PASSWORD ile **aynı** olmalı |
| `MINIO_BUCKET` | `teqlif` | Production bucket |
| `MINIO_DM_BUCKET` | `teqlif-dm` | Production DM bucket |
| `MINIO_SECURE` | `False` | WireGuard üzerinden HTTP |
| `MINIO_REGION` | `us-east-1` | MinIO sabit değer |
| `MINIO_STORAGE_QUOTA_PERCENT` | `80` | — |
| `EDGE_METRICS_INTERVAL_SEC` | `3` | — |
| `NODE2_AI_PROXY_URL` | `"http://10.10.0.3:8080"` | node2 WireGuard IP |
| `NODE3_AI_PROXY_URL` | `"http://10.10.0.4:8080"` | node3 WireGuard IP |
| `AI_PROXY_INTERNAL_TOKEN` | Dolu | ⚠️ node2, node3 prod, node3 staging ile **aynı** olmalı |
| `FIREBASE_SERVICE_ACCOUNT` | Dosya path veya JSON string | FCM push için zorunlu |
| `SENTRY_BACKEND_DSN` | Dolu VEYA bilinçli boş | Optional |
| `GOOGLE_CLIENT_ID` | Dolu | Google OAuth |
| `ADMIN_EMAIL` | Dolu, geçerli e-posta | — |
| `ADMIN_PASSWORD_HASH` | Dolu, bcrypt hash (`$2b$...`) | — |
| `CAPTCHA_ENABLED` | `True` veya `False` | Production'da genellikle True |
| `CAPTCHA_PROVIDER` | `hcaptcha` veya `recaptcha` | — |
| `CAPTCHA_SECRET_KEY` | Dolu (CAPTCHA_ENABLED=True ise zorunlu) | — |
| `DB_POOL_SIZE` | Dolu (örn. `20`) | — |
| `DB_MAX_OVERFLOW` | Dolu (örn. `10`) | — |
| `DB_POOL_TIMEOUT` | Dolu (örn. `30`) | — |
| `DB_POOL_RECYCLE` | Dolu (örn. `1800`) | — |
| `TELEGRAM_BOT_TOKEN` | Dolu, gerçek token | Sistem bildirimleri için |
| `TELEGRAM_CHAT_ID` | Dolu, gerçek chat ID | — |
| `APNS_KEY_PATH` | Dosya path (örn. `/var/www/...`) | iOS VoIP push |
| `APNS_KEY_ID` | Dolu | — |
| `APNS_TEAM_ID` | Dolu | Apple Developer Team ID |
| `APNS_CERT_PATH` | Dosya path VEYA boş | — |
| `IOS_BUNDLE_ID` | `teqlif` | — |
| `APNS_USE_SANDBOX` | `False` | Production için False |
| `SITE_URL` | `https://www.teqlif.com` | — |
| `DEBUG` | `False` | Production için False |
| `WEB_APP_ENABLED` | `False` | — |
| `USE_PGBOUNCER` | `False` | PgBouncer kurulu değilse False |
| `CLICKHOUSE_HOST` | `localhost` | ClickHouse node5'te lokal |
| `CLICKHOUSE_PORT` | `8123` | — |
| `CLICKHOUSE_DB` | `default` | — |

**Durum:** ⏳

---

### Adım 8.5 — node1: backend/.env.production (Edge 1)

**Komut:** `cat /var/www/teqlif.com/backend/.env.production`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `CORE_REDIS_URL` | `redis://:<şifre>@10.10.0.5:6379/1` | node5'teki Redis şifresi ile eşleşmeli |
| `EDGE_NODE_ID` | `node1` | — |
| `EDGE_METRICS_INTERVAL_SEC` | `3` | — |
| `LIVEKIT_API_KEY` | Dolu | ⚠️ node4, node5, node3 staging ile **aynı** olmalı |
| `LIVEKIT_API_SECRET` | Dolu | ⚠️ node4, node5, node3 staging ile **aynı** olmalı |
| `LIVEKIT_PORT` | `7880` | — |
| `MINIO_ROOT_USER` | Dolu | ⚠️ node5 MINIO_ACCESS_KEY ve node4 ile **aynı** olmalı |
| `MINIO_ROOT_PASSWORD` | Dolu | ⚠️ node5 MINIO_SECRET_KEY ve node4 ile **aynı** olmalı |
| `MINIO_VOLUMES` | `"/var/lib/minio"` | — |
| `MINIO_SERVER_URL` | `"http://10.10.0.1:9010"` | node1'in WireGuard IP'si |
| `MINIO_BROWSER` | `"off"` | — |
| `MINIO_STORAGE_QUOTA_PERCENT` | `80` | — |

**Durum:** ⏳

---

### Adım 8.6 — node4: backend/.env.production (Edge 2)

**Komut:** `cat /var/www/teqlif.com/backend/.env.production`

| KEY | Beklenen Değer / Format | Kontrol Notu |
|-----|------------------------|--------------|
| `CORE_REDIS_URL` | `redis://:<şifre>@10.10.0.5:6379/1` | node5'teki Redis şifresi ile eşleşmeli |
| `EDGE_NODE_ID` | `node4` | node1'den farklı olmalı |
| `EDGE_METRICS_INTERVAL_SEC` | `3` | — |
| `LIVEKIT_API_KEY` | Dolu | ⚠️ node1, node5, node3 staging ile **aynı** olmalı |
| `LIVEKIT_API_SECRET` | Dolu | ⚠️ node1, node5, node3 staging ile **aynı** olmalı |
| `LIVEKIT_PORT` | `7880` | — |
| `MINIO_ROOT_USER` | Dolu | ⚠️ node5 MINIO_ACCESS_KEY ve node1 ile **aynı** olmalı |
| `MINIO_ROOT_PASSWORD` | Dolu | ⚠️ node5 MINIO_SECRET_KEY ve node1 ile **aynı** olmalı |
| `MINIO_VOLUMES` | `"/var/lib/minio"` | — |
| `MINIO_SERVER_URL` | `"http://10.10.0.6:9010"` | node4'ün WireGuard IP'si (10.10.0.6) |
| `MINIO_BROWSER` | `"off"` | — |
| `MINIO_STORAGE_QUOTA_PERCENT` | `80` | — |

**Durum:** ⏳

---

### Adım 8.7 — Cross-Node Tutarlılık Özeti

Bu adımda tüm node'ların .env içerikleri alındıktan sonra kritik değerlerin eşleşip eşleşmediği kontrol edilir.

#### Aynı Değer Olması Gereken Key'ler

| Key (Grup) | node2 | node3 prod | node3 staging | node5 | node1 | node4 |
|------------|-------|------------|---------------|-------|-------|-------|
| `AI_PROXY_INTERNAL_TOKEN` | ✅ | ✅ | ✅ | ✅ | — | — |
| `LIVEKIT_API_KEY` | — | — | ✅ | ✅ | ✅ | ✅ |
| `LIVEKIT_API_SECRET` | — | — | ✅ | ✅ | ✅ | ✅ |
| `MINIO_ACCESS_KEY` / `MINIO_ROOT_USER` | — | — | ✅ (ACCESS_KEY) | ✅ (ACCESS_KEY) | ✅ (ROOT_USER) | ✅ (ROOT_USER) |
| `MINIO_SECRET_KEY` / `MINIO_ROOT_PASSWORD` | — | — | ✅ (SECRET_KEY) | ✅ (SECRET_KEY) | ✅ (ROOT_PASSWORD) | ✅ (ROOT_PASSWORD) |
| `CAPTCHA_PROVIDER` / `CAPTCHA_SECRET_KEY` | — | — | ✅ | ✅ | — | — |
| `GROQ_API_KEY` | ✅ | ✅ | — | — | — | — |
| `GEMINI_API_KEY` | ✅ | ✅ | — | — | — | — |
| `TELEGRAM_BOT_TOKEN` | — | ✅ | — | ✅ | — | — |
| `TELEGRAM_CHAT_ID` | — | ✅ | — | ✅ | — | — |
| `BREVO_API_KEY` | — | — | ✅ | ✅ | — | — |
| `FIREBASE_SERVICE_ACCOUNT` | — | — | ✅ | ✅ | — | — |
| `GOOGLE_CLIENT_ID` | — | — | ✅ | ✅ | — | — |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD_HASH` | — | — | ✅ | ✅ | — | — |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | — | — | ✅ | ✅ | — | — |

#### Core Redis Şifresi (Tek Kaynak, Farklı DB Index'ler)

Tüm node'ların Redis bağlantılarında aynı `<CORE_REDIS_PASSWORD>` kullanılır; sadece DB index değişir:

| Node | Key | Bağlantı | DB Index | Kullanım |
|------|-----|----------|----------|---------|
| node5 | `REDIS_URL` | `10.10.0.5:6379` | **0** | Core backend (session, pubsub, cache) |
| node2 | `REDIS_URL` | `10.10.0.5:6379` | **1** | AI proxy rate-limit sayacı |
| node3 prod | `REDIS_URL` | `10.10.0.5:6379` | **1** | AI proxy rate-limit sayacı |
| node1 | `CORE_REDIS_URL` | `10.10.0.5:6379` | **1** | Edge metrics yazma (edge-metrics-agent) |
| node4 | `CORE_REDIS_URL` | `10.10.0.5:6379` | **1** | Edge metrics yazma (edge-metrics-agent) |
| node3 staging | `REDIS_URL` | `127.0.0.1:6379` | **0** | Staging lokal Redis — **farklı şifre** (`<STAGING_REDIS_PASSWORD>`) |

#### Bilinçli Farklı Olan Key'ler (Normal)

| Key | Farkı |
|-----|-------|
| `SECRET_KEY` | node3 staging ≠ node5 production — farklı JWT imzalama sırları |
| `DATABASE_URL` | node3 staging: lokal staging DB / node5: lokal prod DB |
| `EDGE_LIVEKIT_URLS` | node3 staging: `http://127.0.0.1:7880` / node5: `http://10.10.0.1:7880,http://10.10.0.6:7880` |
| `EDGE_MINIO_URLS` | node3 staging: `http://127.0.0.1:9010` / node5: `http://10.10.0.1:9010,http://10.10.0.6:9010` |
| `MINIO_BUCKET` | node3 staging: `teqlif-staging` / node5: `teqlif` |
| `MINIO_DM_BUCKET` | node3 staging: `teqlif-dm-staging` / node5: `teqlif-dm` |
| `EDGE_NODE_ID` | node1: `node1` / node4: `node4` |
| `MINIO_SERVER_URL` | node1: `http://10.10.0.1:9010` / node4: `http://10.10.0.6:9010` |
| `APNS_USE_SANDBOX` | node3 staging: `True` / node5: `False` |
| `DEBUG` | node3 staging: `True` / node5: `False` |
| `SITE_URL` | node3 staging: `https://staging.teqlif.com` / node5: `https://www.teqlif.com` |
| `BREVO_SENDER_EMAIL` | node3 staging: `staging@teqlif.com` / node5: gerçek gönderici |
| `CF_ZONE_ID` / `CF_DNS_RECORD_ID` / `CF_API_TOKEN` | Sadece node2'de — CF failover için |
| `CAPTCHA_PROVIDER` / `CAPTCHA_SECRET_KEY` | node3 staging ve node5 — aynı değer; `CAPTCHA_ENABLED=True` her ikisinde de |

**Durum:** ⏳
