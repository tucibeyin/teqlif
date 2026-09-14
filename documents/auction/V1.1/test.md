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
