# Auction V1.1 - Test Senaryoları (Test.md)

Bu dosya, `task.md` üzerindeki her bir adımın başarıyla uygulandığını kanıtlamak için gerçekleştirilecek testleri içerir.

## Adım 1: Nginx Gateway (Cloudflare Real IP) Testleri

**Test 1.1: Nginx Konfigürasyon Testi**
- **Amaç:** Nginx'in syntax hatası vermediğinden ve reload işleminin başarıyla tamamlandığından emin olmak.
- **Beklenen Çıktı:** `nginx: configuration file /etc/nginx/nginx.conf test is successful`

**Test 1.2: X-Forwarded-For Log Kontrolü**
- **Amaç:** Cloudflare üzerinden gelen isteklerin Nginx access log'larında veya Backend log'larında gerçek IP (CF-Connecting-IP) ile göründüğünü teyit etmek.
- **Nasıl Yapılır:** Uygulamaya dışarıdan (hücresel veri vb.) bir HTTP isteği (örn. `/api/health` veya herhangi bir endpoint) atılır. `tail -f /var/log/nginx/access.log` veya backend loglarında Cloudflare Edge IP'si yerine telefonun gerçek IP adresinin yazdığı gözlemlenir.
- **Beklenen Çıktı:** Cloudflare IP'leri yerine ISP'ye (Turkcell, Vodafone vb.) ait gerçek Public IP.

---

## Adım 2: Fraud Skoru Güncellemesi (Mute Bug Kök Çözüm) Testleri

**Test 2.1: Python Syntax Testi**
- **Amaç:** `fraud_detection_service.py` dosyasında syntax hatası olmadığını teyit etmek.
- **Nasıl Yapılır:** `python3 -m py_compile app/services/fraud_detection_service.py`
- **Beklenen Çıktı:** Hata vermeden (boş) dönmesi.

**Test 2.2: Canlı Test (Yeni Kullanıcı Mute)**
- **Amaç:** Aynı Wi-Fi / Hücresel (CGNAT) ağındaki yeni bir kullanıcının ilk teklifinde banlanmadığını görmek.
- **Nasıl Yapılır:** Yeni bir mobil cihaz veya emülatörden giriş yapıp, yayıncıyla aynı ağdayken (veya aynı IP maskesindeyken) bir teklif verilir.
- **Beklenen Çıktı:** Uygulama "Susturuldunuz" (MUTE) uyarısı göstermez, teklif yayına düşer. (Loglarda WARN verilebilir ama MUTE olmamalıdır).
