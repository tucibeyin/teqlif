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

**Durum:** ⏳ Kullanıcı onayı bekleniyor.
