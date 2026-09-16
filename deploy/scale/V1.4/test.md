# Teqlif Scale V1.4 - Test Senaryoları (Test Cases)

## Görev 1.0: Ortak İlk Hazırlık (README.md) Testi
**Amaç:** `V1.4/README.md` dosyasının, yeni bir sunucunun (Node4 veya Node5) sıfırdan "tucibeyin" kullanıcısı ile repo klonlama aşamasına kadar getirilmesini eksiksiz anlattığını doğrulamak.

**Test Adımları (Manuel Gözden Geçirme):**
1. `deploy/scale/V1.4/README.md` dosyasını açıp okuyun.
2. `tucibeyin` kullanıcısının oluşturulup `sudo` yetkisi verildiğini onaylayın.
3. SSH anahtar erişimi adımlarının şifresiz giriş için doğru yazıldığını onaylayın.
4. Repo klonlama yolunun V1.4 mantığına uygun olarak (`/var/www/teqlif.com`) verildiğini onaylayın.

**Beklenen Sonuç:** Belgenin, V1.4 altyapı scriptlerini (`bootstrap_*.sh`) çalıştırmadan önceki tüm manuel sunucu hazırlık operasyonlarını net, güvenli ve eksiksiz bir şekilde açıklaması.

**Durum:** ⏳ Kullanıcı onayı bekleniyor.
