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
**Amaç:** Kalan node'ların (Gateway ve Async Worker'lar) V1.4 Core-Edge topolojisi ile entegre olduğunu onaylamak.

**Test Adımları (Review):**
1. `gateway/resources/certbot_gateway.sh` scriptinde Nginx proxy_pass ayarının `10.10.0.1` yerine `10.10.0.5` (Yeni Node5 Core IP'si) olarak güncellendiğini (`sed` komutu) doğrula.
2. Node2 ve Node3 (Worker'lar) için `bootstrap` scriptlerinin yazıldığını ve V1.4'te veritabanı (Postgres vb.) barındırmadıklarını onayla.
3. Her üç node'un `bootstrap` scriptinde `Clean State` (Önbellek temizlik) kuralına uyulduğunu doğrula.

**Beklenen Sonuç:** Tüm sunucu yelpazesinin tam V1.4 (Orchestrator=Node5, Edge=Node1/4, Workers=Node2/3, Proxy=Gateway) senaryosuna göre scriptlerinin tamamlanması.

**Durum:** ✅ Tamamlandı (Commit: 8827ba8b)

---

## Görev 1.5: Cloudflare DNS Yapılandırması Testi
**Amaç:** V1.4 Multi-Edge mimarisi için zorunlu olan dinamik DNS altyapısının belgelenmesi ve eski yüklerin temizlenmesi.

**Test Adımları (Review):**
1. `deploy/scale/V1.4/plan.md` dosyasının en altındaki **Faz 7: Cloudflare DNS Yapılandırması** bölümünü aç ve incele.
2. Gateway (Core trafiği) için `teqlif.com` ve `api.teqlif.com` yönlendirmelerinin **Proxied** olarak `94.16.105.135` (Gateway) hedefine ayarlandığını doğrula.
3. Edge sunucuları (Node1 ve Node4) için sırasıyla `live1`/`minio1` ve `live2`/`minio2` olarak her makineye özel yeni subdomain kayıtlarının açıldığını ve bunların Cloudflare Proxy'den bağımsız (**DNS Only**) ayarlandığını doğrula.
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

**Durum:** ⏳ Backend kodlaması esnasında test edilecek.

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

**Durum:** ⏳ Kısmen Tamamlandı (Commit: 4d5af235) - Görev 3.3 (VoIP Refactor) bekleniyor.

---

## Aşama 4: Canlı Sunucu Operasyonları (Execution) Testi
**Amaç:** Backend refaktörleri bittikten sonra canlı sunucuların (SSH) V1.4 mimarisine sıfır veri kaybı ile geçmesini doğrulamak.

**Test Adımları:**
1. Node5, Node4 ve Node1'e SSH ile girilip `bootstrap` scriptlerinin hatasız çalıştığını onayla.
2. Node1'den alınan `pg_dump` ve MinIO arşivinin başarıyla Node5 ve Node4'e kopyalandığını (Migration) doğrula.
3. Gateway Nginx `teqlif.com.conf` devresi açıldığında mobil uygulamanın sorunsuz API (Node5) ve Staging (Node3) bağlantısı kurduğunu onayla.

**Durum:** ⏳ Faz 6 (Canlıya Geçiş) esnasında test edilecek.
