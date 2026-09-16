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

**Durum:** ⏳ Kullanıcı onayı bekleniyor.
