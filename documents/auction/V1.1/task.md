# Auction V1.1 - Görev Listesi (Task.md)

Bu dosya, `plan.md` ve `findings.md` belgelerindeki kararların Clean Architecture, MVVM ve V1.3 topolojisine sadık kalınarak adım adım uygulanmasını takip eder.

> **Kurallar:**
> 1. Her task adımı teqlif mimarisine qlif_archtectural_desicions.md, clean code, clean architecture ve MVVM prensiplerine ve teqlif mimarisine, deploy/resources ve deploy/scale/V.13'e uygun implemte edilmelidir.
> 2. Her task adımı implemente edildikten sonra onay alınmalıdır ve sonrasında commit ve push yapılmalıdır.
> 3. Her task adımı sonrasında VPS'lerde yapılacak olan manuel işlemler sunulmalıdır ve adım adım gerçekleştirilmelidir. Her adımda çıktı beklenmelidir.
> 4. 1-2-3 adımları tamamlandıktan sonra yapılabilecek testler test.md ye task adımı bağlantısıyla dökümante edilmeli ve test'in gerçekleştirilip gerçekleştirilmeyeceği sorulmalı, test çıktısı analiz edilmeli.
> 5. Testler bittikten sonra task.md de o task adımı Completed olarak commit numarası ve tarih-saat bilgisiyle işaretlenmelidir.
> 6. Bir sonraki adıma geçilebilir.

---

## `[x]` Adım 1: Nginx Gateway (Cloudflare Real IP) Düzeltmesi (Completed: b82fa6ac, 2026-09-14 13:06)
- `deploy/scale/V1.3/gateway/nginx/teqlif.conf` dosyasına Cloudflare IPv4 ve IPv6 bloklarının `set_real_ip_from` ile eklenmesi.
- `real_ip_header CF-Connecting-IP;` kuralının aktif edilmesi.
- VPS Adımı: Nginx sunucusuna (Node 2/Gateway) çıkılıp `nginx -t` ve `systemctl reload nginx` yapılması.

## `[x]` Adım 2: Fraud Skoru Güncellemesi (Mute Bug Kök Çözüm) (Completed: 7e4f7c5d, 2026-09-14 13:33)
- `app/services/fraud_detection_service.py` dosyasındaki `_SHILL_SCORE_IP_MATCH` değerinin 30'dan 15'e düşürülmesi.
- VPS Adımı: Node 1 (Backend Core) üzerinde `systemctl restart teqlif.service` çalıştırılması.

## `[x]` Adım 3: Clean Architecture - BidValidationService (Troll Teklif Refactoring) (Completed: 2134edcd, 2026-09-14 14:19)
- `app/services/bid_validation_service.py` servisinin oluşturulması.
- `auction_commands.py` içerisindeki Troll teklif limitlerinin (çarpanlar ve telefon onay kısıtları) bu servise taşınması (`validate_troll_bid` metodu).
- `place_bid` fonksiyonunun bu servisi çağıracak şekilde sadeleştirilmesi.

## `[ ]` Adım 4: Clean Architecture - AuctionRedisRepository (Dependency Injection)
- `app/repositories/auction_redis_repo.py` sınıfının oluşturulması.
- `get_redis()`, Lua Script tetiklemeleri ve Mute kontrollerinin bu repository arkasına gizlenmesi.
- `AuctionCommands` sınıfının bu repository'i kullanarak Redis'ten izole edilmesi (Mock/Test edilebilir hale getirilmesi).
- VPS Adımı (Adım 3 ve 4): Node 1 (Backend Core) üzerinde `systemctl restart teqlif.service` yapılması ve testlerin (eğer varsa) koşturulması.
