# teqlif Platformu — SRE & Güvenilirlik Bulguları Raporu (V1.0)

**Tarih:** 26 Ekim 2026  
**Kapsam:** `backend/app/services/`, `backend/app/tasks/`, `backend/app/use_cases/`, `backend/app/worker.py`, `backend/main.py`, `backend/app/database_clickhouse.py`, `deploy/scale/V2.1/`  
**Amaç:** Sistemin ölçeklenme, yüksek eşzamanlılık (concurrency), bellek tüketimi (OOM), veri bütünlüğü, iki aşamalı mutabakat (2PC/desync), dağıtık yönlendirme ve arıza toleransı (fault tolerance) açısından kod tabanında tespit edilen zaaflarını Claude / yazılım ekibinin doğrudan uygulayabileceği netlikte belgelemek.

---

## 📌 Önceliklendirme ve Özet Tablosu

| ID | Seviye | Bileşen / Dosya | Zaaf / Hata Türü | Etki Alanı |
| :---: | :---: | :--- | :--- | :--- |
| **SRE-01** | 🔴 **P0 (Kritik)** | `stream_concat_task.py` | "Zehirli Hap" (Poison Pill) Sonsuz Döngüsü | CPU & Disk I/O tükenmesi |
| **SRE-02** | 🔴 **P0 (Kritik)** | `faiss_service.py` | Atomik Olmayan Index Yazımı & Yarış Durumu (Race Condition) | Canlı arama çökmesi (Segfault) |
| **SRE-03** | 🟠 **P1 (Yüksek)** | `worker.py` & `stream_concat_task.py` | ARQ Timeout (300s) vs Video Süresi Çelişkisi | Görevlerin yarıda kesilip ölmesi |
| **SRE-04** | 🟠 **P1 (Yüksek)** | `bpr_service.py` & `feed_als_ml.py` | Sınırsız Veri Çekimi (Unbounded Query) & OOM Riski | Linux OOM Killer, worker çökmesi |
| **SRE-05** | 🟠 **P1 (Yüksek)** | `foryou_worker.py` | N+1 Sıralı Ağ Çağrısı & Pasif Kullanıcı Hesaplaması | Worker thread kilitlenmesi, Redis RAM israfı |
| **SRE-06** | 🟠 **P1 (Yüksek)** | `feed_als_ml.py` & `swipe_live_ml.py` | Sınırsız Redis Pipeline Yüklemesi (Buffer Bloat) | Redis event-loop donması, socket timeout |
| **SRE-07** | 🟡 **P2 (Orta)** | `transfer_teqlik.py` | Karşılıklı Para Transferinde Deadlock (40P01) | Kullanıcı bakiyesinde işlem iptali |
| **SRE-08** | 🟡 **P2 (Orta)** | `wallet_tasks.py` | Açık Transaction İçinde Binlerce Döngüsel SQL | Postgres WAL şişmesi, satır kilitlenmeleri |
| **SRE-09** | 🟡 **P2 (Orta)** | `schedule.yaml` | Pazar Günü "Süper Fırtına" Yığılması (Schedule Storm) | CPU %100, canlı kullanıcı gecikmesi |
| **SRE-10** | 🟢 **P3 (Düşük)** | ML Eğitim Servisleri | ML Eğitimlerinde Dağıtık Kilit (Distributed Lock) Eksikliği | Çift çalışma, kaynak israfı |
| **SRE-11** | 🔴 **P0 (Kritik)** | `auction_commands.py` | Açık Artırmada İki Aşamalı Tutarsızlık ve Reddedilen Tekliflerin DB'de Kalması | Finansal manipülasyon, hatalı ihale kazananı |
| **SRE-12** | 🔴 **P0 (Kritik)** | `main.py` & `teqlif.service` | Uvicorn 8 Worker Çoğaltması Nedeniyle Arka Plan Scheduler ve Flush Görevlerinin 8 Kat Çalışması | 8 kat DB polling, ClickHouse batch kirliliği, CPU israfı |
| **SRE-13** | 🟠 **P1 (Yüksek)** | `database_clickhouse.py` | ClickHouse Buffer Boşaltımında Sessiz Veri Kaybı ve Finansal Event Riski | Doğrudan satış sipariş ve stok denetim loglarının yok olması |
| **SRE-14** | 🟠 **P1 (Yüksek)** | `thompson_sampling.py` | Thompson Sampling Redis Read-Modify-Write Yarış Durumu | Kullanıcı ilgi alanı parametrelerinin ezilmesi (Lost Updates) |
| **SRE-15** | 🟠 **P1 (Yüksek)** | `send_direct_message.py` | Kapatılmış SQLAlchemy Session'ı Üzerinde Çalıştırma ve İşlem Sızıntısı | `InvalidRequestError` / sessiz connection kirliliği |
| **SRE-16** | 🟠 **P1 (Yüksek)** | `churn_ml_service.py` | Churn Modelinde Atomik Olmayan Model (Pickle) Kaydı | Canlı tahmin anında truncated pickle ve crash |
| **SRE-17** | 🟡 **P2 (Orta)** | `listing_tasks.py` | İlan Pasifleştirmede ORM Nesne Şişmesi & IN Parametre Patlaması | Bellek şişmesi, Postgres parse darboğazı |
| **SRE-18** | 🟡 **P2 (Orta)** | `analytics_tasks.py` | Churn Airdrop Dağıtımında Toplu Kilit ve Tablo Blokajı | `users` tablosunda uzun satır kilitleri, login blokajı |
| **SRE-19** | 🟠 **P1 (Yüksek)** | `moderation_service.py` | Canlı Yayın Katılımcı Çıkarma / Moderasyonda Yanlış Edge Node Yönlendirmesi | Moderatörün trolleri canlı yayından atamaması |
| **SRE-20** | 🔴 **P0 (Kritik)** | `referral_service.py` & `referral.py` | Davet (Referral) Sisteminde Çift Harcama / Race Condition ile Sınırsız Teqlik Kazanımı | Sınırsız karşılıksız para/teqlik basımı |
| **SRE-21** | 🔴 **P0 (Kritik)** | `teqlif.service`, `rate_limit.py`, `auction.py` | Ters Proxy (Nginx) Arkasında İstemci IP Kaybı ve Küresel Rate Limit / Sahte Shill Kilidi | Tüm kullanıcıların 127.0.0.1 sayılması, masum teklifçilerin engellenmesi |
| **SRE-22** | 🟠 **P1 (Yüksek)** | `story_service.py` | Hikaye Yüklemede Senkron FFmpeg Sıkıştırması ve API Worker Blokajı | Web worker'ın 2dk donması, 504 Gateway Timeout, CPU %100 |
| **SRE-23** | 🟠 **P1 (Yüksek)** | `direct_sale_commands.py` | Doğrudan Satışta DB Hatalarında Redis Stok Sızıntısı (Missing Compensating Tx) | Stokların havaya uçması, satılmamış ürünün sold-out kalması |
| **SRE-24** | 🟠 **P1 (Yüksek)** | `ad_service.py` | Reklam Tıklamalarında Negatif Bütçe ve Karşılıksız Tıklama Sızıntısı | Bütçe 0 altındayken tıklama almaya devam etme, ciro kaybı |
| **SRE-25** | 🟠 **P1 (Yüksek)** | `stream_listener.py` | Stream Fan-Out Listener'da `os.getpid()` ile Restart Anında Mesaj Kaybı | Worker yeniden başladığında aradaki DM, arama ve eventlerin yok olması |
| **SRE-26** | 🟡 **P2 (Orta)** | `storage_service.py` & `edge_orchestrator.py` | Çoklu Node MinIO Okumasında Rastgele Node Seçimi (Get Object 404) | Dosya node1'deyken node2'den okunmaya çalışılıp bulunamaması |
| **SRE-27** | 🟡 **P2 (Orta)** | `recommendation_service.py` | Keşfet Akışında Her İstekte Dinamik `SELECT DISTINCT category` Sorgusu | Veritabanında her sayfa kaydırmada full scan, 50ms gereksiz gecikme |
| **SRE-28** | 🟡 **P2 (Orta)** | `stream_finalizer.py` | Canlı Yayın Sohbet Dump'ında asyncpg Parametre Limiti (32767) Çökmesi | 3.500+ mesajlı yayınlarda finalizer crash, Redis RAM sızıntısı |
| **SRE-29** | 🟢 **P3 (Düşük)** | `stream_finalizer.py` & `edge_orchestrator.py` | Canlı Ortamda O(N) `redis.keys()` Kullanımı ve Event-Loop Blokajı | Redis tek iş parçacığının onlarca ms donması, API gecikmesi |
| **SRE-30** | 🟡 **P2 (Orta)** | `hype_manager.py` | Hype Manager Süreç İçi (In-Memory) Durum ve 8 Worker Arasında Senkronizasyon Yokluğu | İzleyici ekranında hype skorunun iş parçacığına göre zıplaması/tutarsızlığı |
| **SRE-31** | 🔴 **P0 (Kritik)** | `verify_purchase_command.py` & `wallet.py` | IAP Satın Alma Doğrulamasında Eksik `commit()` Nedeniyle Gerçek Parayla Alınan Bakiyenin Rollback Olması | Kullanıcının kartından para çekilmesi ancak Teqlik bakiyesinin veritabanına asla işlenmemesi |
| **SRE-32** | 🔴 **P0 (Kritik)** | `handle_store_refund_command.py` & `wallet_tasks.py` | Apple Store İadelerinde Eksik `commit()` Nedeniyle İade Bakiyesinin Düşürülememesi ve Sonsuz Para Açığı | Kullanıcının Apple'dan parasını geri alıp Teqlik'i harcamaya devam etmesi (sınırsız bakiye exploit'i) |
| **SRE-33** | 🟠 **P1 (Yüksek)** | `wallet_tasks.py` | Google Play RTDN Webhook Bildirimlerinin Worker Tarafından Desteklenmeyip Yutulması | Android abonelik yenilemeleri, iptalleri ve iadelerinin sisteme işlenememesi |
| **SRE-34** | 🟠 **P1 (Yüksek)** | `analytics.py` | `track_event` Endpoint'inde Kapatılmış DB Oturumunun (Closed Session) BackgroundTasks'e Verilmesi | Tüm web analitik eventlerinin `IllegalStateChangeError` ile sessizce yok olması |
| **SRE-35** | 🟠 **P1 (Yüksek)** | `calls.py` & `ws_manager.py` | Korunmasız ve Tahmin Edilebilir `POST /calls/{id}/ack` ile Çağrı İşaretleşmesinin Bozulması | Saldırganın ardışık ID'lerle aranan kişinin FCM/APNs push bildirimlerini bastırması (DoS) |
| **SRE-36** | 🟠 **P1 (Yüksek)** | `livekit.yaml` & `bootstrap_node3.sh` | Canlı Yayın Düğümlerinde (node3/node4) `livekit.yaml` İçinde Olmayan Yerel Redis'e (`127.0.0.1:6379`) Bağlanma | LiveKit servisinin açılamaması (`connect: connection refused`), streaming altyapısının çökmesi |
| **SRE-37** | 🟠 **P1 (Yüksek)** | `leads.py` | `send-blast` Endpoint'inde Senkron Döngüde 10.000'e Varan FCM Push Gönderimi ve Gateway Timeout | HTTP iş parçacığının 30+ sn kilitlenmesi, 504 Timeout ve mükerrer bakiye kesintisi |
| **SRE-38** | 🟡 **P2 (Orta)** | `auth.py` | `refresh_token` İçinde Grace Period Olmayan `redis.getdel` Nedeniyle Mobil Kullanıcıların Rastgele Oturumdan Atılması | Mobil/web eşzamanlı isteklerde yarış durumu (race condition) ve zorunlu oturum kapatma |
| **SRE-39** | 🔴 **P0 (Kritik)** | `teqlif.conf` | `client_max_body_size 5m` Nedeniyle Story, Video ve Medya Yüklemelerinin HTTP 413 ile Reddedilmesi | 5MB'tan büyük video yüklemelerinin Nginx tarafından engellenmesi, story ve medyanın çalışmaması |
| **SRE-40** | 🔴 **P0 (Kritik)** | `runbook.sh` | Node1 Kurtarma Runbook'unun DNS'i FastAPI/Nginx/MinIO Olmayan Node2'ye Yönlendirip Sistemi Çökertmesi | Felaket anında tüm kullanıcıların 502/Connection Refused alması, tam erişim kaybı |
| **SRE-41** | 🟠 **P1 (Yüksek)** | `minio_backup.sh` | MinIO Yedekleme Scriptinde Hardcoded ve Geçersiz ILM Kural ID'si Nedeniyle Kayıt Silinmesi Riski | Yedekleme başarısız olduğunda 7 günlük koruma süresinin set edilemeyip kayıtların 2 günde silinmesi |
| **SRE-42** | 🟠 **P1 (Yüksek)** | `teqlif-redis-replica.service` & `bootstrap_node2.sh` | Node2 Redis Replica Konfigürasyonunun (`/etc/redis/redis-replica.conf`) Bulunmaması | Replica'nın ayağa kalkamaması, otomatik failover mekanizmasının çökmesi |
| **SRE-43** | 🟠 **P1 (Yüksek)** | `healer.py` & `teqlif-agent.service` | `teqlif-agent` Self-Healer Modülünün Yetkisiz Kullanıcı Nedeniyle Servisleri Yeniden Başlatamaması | `systemctl reset-failed` / `start` çağrılarının `Access Denied` alması, kendini iyileştirmenin çalışmaması |
| **SRE-44** | 🟠 **P1 (Yüksek)** | `cluster.yaml` & `schedule.yaml` | Pazar Gecesi 02:00 UTC Ağ Darboğazı: `pg_basebackup` ile Video Transferinin Aynı Anda Başlatılması | 1 Gbps portun tıkanması, WireGuard paket kaybı, transfer ve backup zaman aşımı |
| **SRE-45** | 🟡 **P2 (Orta)** | `.env.production.template` | Üretim Ortamında 30 Günlük Access Token (`ACCESS_TOKEN_EXPIRE_MINUTES=43200`) Güvenlik Açığı | Çalınan token'ın 1 ay boyunca iptal edilememesi, refresh token mimarisinin baypas edilmesi |
| **SRE-46** | 🟡 **P2 (Orta)** | `leader.py` | `LeaderElector` Basit HTTP Ping Algoritmasında Split-Brain ve Çift Temizlik Riski | Ağ gecikmesinde iki liderin aynı anda janitor/reporter çalıştırıp DB'de çakışma yaratması |
| **SRE-47** | 🔴 **P0 (Kritik)** | `store/factory.py` | `StoreVerifierFactory` İçinde Google Play Verifier Bulunmaması ve Android Satın Alımlarının Çökmesi | Android kullanıcılarının Teqlik satın alamaması, HTTP 500 çökmesi ve gelir kaybı |
| **SRE-48** | 🔴 **P0 (Kritik)** | `apple_verifier.py` | Üretim Ortamında Apple Sandbox Dekontlarının Kabul Edilmesi ve Sınırsız Karşılıksız Teqlik İstismarı | Saldırganların test hesaplarıyla sonsuz bedava Teqlik üretmesi ve nakde çevirmesi |
| **SRE-49** | 🟠 **P1 (Yüksek)** | `apns_service.py` | 60 Saniyelik Global Circuit Breaker Nedeniyle Tek Hatada Tüm iOS VoIP Aramalarının Düşmesi | Bir kullanıcının ağ hatası yüzünden sistemdeki tüm iOS kullanıcılarının telefonunun çalmaması |
| **SRE-50** | 🟠 **P1 (Yüksek)** | `like_service.py` & `streams.py` | Canlı Yayın Kalp Dokunuşlarında Senkron PostgreSQL Commit ve 150.000 WS/sn Mesaj Bombardımanı | Canlı yayında seri kalp basıldığında Postgres connection pool tükenmesi ve worker çökmesi |
| **SRE-51** | 🟠 **P1 (Yüksek)** | `worker.py` & `webhooks.py` | `delayed_close_stream_task` İçinde LiveKit Ağ Hatasında Yayının Haksız Yere Kapatılması | Geçici ağ titremesinde aktif canlı yayınların zorla kapatılıp izleyicilerin düşürülmesi |
| **SRE-52** | 🟠 **P1 (Yüksek)** | `encoder.py` | FFmpeg ve `mc cp` Alt Süreçlerinde Timeout Olmaması Nedeniyle Encoding Kuyruğunun Kilitlenmesi | Bozuk yayında FFmpeg'in askıda kalması, encoding ve transfer slotlarının kalıcı felç olması |
| **SRE-53** | 🟠 **P1 (Yüksek)** | `redis_failover.sh` | Eksik İstemci Yönlendirmesi Nedeniyle Sahte Failover (False Failover) ve Sistem Duruşu | Node1 çöktüğünde Node2'nin master olması ancak hiçbir client'ın buraya bağlanamaması |
| **SRE-54** | 🟡 **P2 (Orta)** | `clickhouse_backup.sh` | Sözdizim Hatası Nedeniyle Snapshot Başarısızlığı ve Fallback Modunda Eksik Tablo Yedeklenmesi | ClickHouse yedeğinin native fallback'e düşmesi ve yeni analitik tablolarının yedeksiz kalması |
| **SRE-55** | 🔴 **P0 (Kritik)** | `ads.py` & `ad_service.py` | Kampanya Oluşturmada Tüm Aktif Kampanyaların Harcanmış Bütçelerinin Sıfırlanması | Her yeni reklamda tüm mevcut bütçelerin tavana vurması, sınırsız bedava trafik sızıntısı |
| **SRE-56** | 🟠 **P1 (Yüksek)** | `story_service.py` | `cleanup_expired_stories` İçinde Açık DB Oturumunda Senkron MinIO Silme ve Yetim DB Kayıtları | 100+ sn açık Postgres oturumu, kilitler ve commit hatasında bozuk/404 story kayıtları |
| **SRE-57** | 🔴 **P0 (Kritik)** | `teqlif.service` & `sync_main.py` | Systemd `ExecStartPre` İçinde Ağır Lokasyon/Kategori Sync Scripti Nedeniyle 30s Kesinti | Servis çökmesinde/restartında Uvicorn'un 30s gecikmesi, 502 Bad Gateway ve lock starvation |
| **SRE-58** | 🟠 **P1 (Yüksek)** | `teqlif.conf` | Nginx Konfigürasyonunda Canlı Yayın ve Açık Artırma WebSocket Rotalarında Upgrade Eksikliği | Canlı yayın chat ve müzayede WebSocket bağlantılarının kurulamaması, 400 Bad Request |
| **SRE-59** | 🟠 **P1 (Yüksek)** | `livekit_subscriber.py` | Video Kaydında Senkron VP8 Encode ve Matriks Rotasyonunun Event-Loop'u Kilitlemesi | 30 FPS'de event-loop blokajı, ses/video senkron kopmaları ve WebRTC paket düşüşü |
| **SRE-60** | 🟡 **P2 (Orta)** | `livekit_relay.py` | Relay Subprocess'inin Streaming Node'larında Olmayan Yerel Redis'e Bağlanması | `ConnectionRefusedError`, ready key yazılamaması ve izleyicilerin relay'e yönlendirilememesi |
| **SRE-61** | 🟠 **P1 (Yüksek)** | `direct_sale_commands.py` | Satıcının Kendi Satışını Satın Alması Kontrolünün Bulunmaması ve Bakiye Doğrulamasız Sipariş | Canlı yayında sahte satış, yapay hype yaratma ve stok manipülasyonu |
| **SRE-62** | 🟡 **P2 (Orta)** | `messages.py` | HTTP GET Endpoint'inde (`GET /{other_user_id}`) Yan Etkili DB Commit ve Okundu İşareti | Prefetch/link taramalarında mesajların erken okunması, Read-Replica'da crash |
| **SRE-63** | 🟡 **P2 (Orta)** | `chat.py` | `_check_whale_status` İçindeki Hatalı `user_type` Kontrolü Nedeniyle Tüm Yayınlarda DB Aggregation | Her izleyici girişinde `Purchase` tablosunda `SUM(price)` çalışması, DB havuzu kilitlenmesi |
| **SRE-64** | 🟠 **P1 (Yüksek)** | `upload.py` & `media_processor.py` | Resim Yüklemede Senkron Pillow LANCZOS Thumbnail Üretimi Nedeniyle Event-Loop Blokajı | 300-800ms worker donması, eşzamanlı yüklemelerde tüm API ve WebSocketlerin kilitlenmesi |
| **SRE-65** | 🔴 **P0 (Kritik)** | `listings.py` | `/generate-description` İçinde TOCTOU Bakiye Yarış Koşulu ile Sınırsız Bedava AI İlan Açıklaması | Tekil bakiye ile eşzamanlı istek atılarak onlarca lüks AI metni üretilmesi, maliyet sızıntısı |
| **SRE-66** | 🟠 **P1 (Yüksek)** | `teqlif-ai-proxy.service` (node5, node6) | AI Proxy Servislerinin WireGuard Yerine `0.0.0.0:8001` ile Genel İnternete Açık Olması | Genel WAN IP üzerinden API'ye erişim, token brute-force ve Groq/Gemini kota tükenmesi |
| **SRE-67** | 🟡 **P2 (Orta)** | `recommendation_service.py` | Dinamik Salt'lı `ORDER BY hashtext(...)` ile PostgreSQL Tam Tablo Hash Sort Felaketi | Her feed isteğinde indeks kullanılamayan tam tablo sıralaması, Postgres CPU %100 |
| **SRE-68** | 🔴 **P0 (Kritik)** | `auth.py` & `admin_data.py` | Hesap/Kullanıcı Silmede Redis `session:user:{uid}` Temizlenmemesi ve Zombi Oturumlar | Silinen/yasaklanan kullanıcının 15 dk boyunca JWT ile her işlemi yapabilmesi |
| **SRE-69** | 🟠 **P1 (Yüksek)** | `auction.py` | `AuctionConnectionManager` Bağımsız WS Yöneticisi ve Graceful Shutdown Eksikliği | Uvicorn restart anında müzayede soketlerinin dirty reset ile kopması |
| **SRE-70** | 🟠 **P1 (Yüksek)** | `story_service.py` | `delete_story` İçinde DB Commit Öncesi MinIO Silme ve Yetim/Bozuk DB Kayıtları | Hata anında DB rollback, dosya yokluğu ve story tepsisinde 404 patlaması |
| **SRE-71** | 🟡 **P2 (Orta)** | `catalog.py` | `/version` Endpoint'inde Tüm Veritabanı Taksonomisinin Baştan Sona Yüklenip Hash Hesaplanması | Mobil istemcilerin her sürüm kontrolünde tüm kataloğu DB'den çekip CPU/RAM tüketmesi |
| **SRE-72** | 🔴 **P0 (Kritik)** | `notifications.py` | Eksik `AsyncSessionLocal` Import'u Nedeniyle Tüm Canlı Bildirim WebSocket'lerinin Çökmesi | Mobil ve web istemcilerin anında 1011 alması, bildirimlerin canlı düşmemesi |
| **SRE-73** | 🔴 **P0 (Kritik)** | `bootstrap_node2.sh` & `runbook.sh` | Node2'de PostgreSQL Server Paketinin Kurulmaması ve Felaket Kurtarmada PITR Restore Çöküşü | Node1 çöktüğünde veritabanının `Unit postgresql.service not found` ile açılamaması |
| **SRE-74** | 🟠 **P1 (Yüksek)** | `search_alerts.py` | `delete_alert` İçinde Geçersiz Enum Değeri (`'passive'`) Ataması Nedeniyle HTTP 500 Çökmesi | Kullanıcıların arama alarmlarını silememesi, SQLAlchemy DataError |
| **SRE-75** | 🟡 **P2 (Orta)** | `ratings.py` & `favorites.py` | Değerlendirme ve Favori Listelemede Sayfalama (Pagination) Eksikliği ve O(N) IN Şişmesi | Büyük profillerde binlerce satırın tek seferde çekilmesi, asyncpg limit çökmesi |
| **SRE-76** | 🔴 **P0 (Kritik)** | `read_cache.py` & `follows.py` | `invalidate_cache("user_profile")` ile Global Profil Önbellek Çöküşü (Cache Stampede) | Her takip/profil aksiyonunda 50.000 kullanıcının önbelleğinin silinmesi, DB kilitlenmesi |
| **SRE-77** | 🟠 **P1 (Yüksek)** | `admin_data.py` | `/push/send` İçinde Senkron Döngüde 10.000 FCM Çağrısı ve Uvicorn Worker Blokajı | Uvicorn iş parçacığının 25 dakika kilitlenmesi, 504 Gateway Timeout |
| **SRE-78** | 🟠 **P1 (Yüksek)** | `cleaner.py` (teqlif-agent) | Süresi Dolan Hikayelerin DB'den Silinirken MinIO Nesnelerinin Silinmemesi | MinIO diskinde yüzlerce GB yetim video/thumbnail birikmesi, depolama tükenmesi |
| **SRE-79** | 🟡 **P2 (Orta)** | `users.py` | `suggested-sellers` İçinde Her İstekte Tüm `follows` Tablosunun Taranması | Her kullanıcı önerisinde milyonlarca satırlık `GROUP BY followed_id`, Postgres CPU %100 |
| **SRE-80** | 🟡 **P2 (Orta)** | `admin_data.py` | `admin_delete_listing` İçinde Ardışık Hatalı Atama Nedeniyle İlanın Silinememesi | Admin silme isteğinde `DELETED` ardından `PASSIVE` atanması, ilanın silinmemesi |
| **SRE-81** | 🔴 **P0 (Kritik)** | `request_withdrawal_command.py` | `exchange_rates` Tablosunda Olmayan Sütunların Aranması ve Tüm Dövizli Para Çekimlerinin Patlaması | USD/EUR para çekim taleplerinde `UndefinedColumn` SQL çökmesi (HTTP 500) |
| **SRE-82** | 🟠 **P1 (Yüksek)** | `credit_service.py` & `leads.py` | TOCTOU Yarış Durumu (Race Condition) ile Kullanıcıların Ücretsiz Haklarını Sınırsız Aşabilmesi | Ücretsiz aylık limitlerin (Blast, Boost, AI Desc) paralel isteklerle baypas edilmesi |
| **SRE-83** | 🟠 **P1 (Yüksek)** | `tcmb_service.py` | Hafta Sonu ve Tatillerde Boş TCMB XML ForexBuying Nedeniyle `AttributeError` ile Güncellemenin Durması | Tatil günlerinde döviz kurlarının çekilememesi, `None.replace` çökmesi |
| **SRE-84** | 🟠 **P1 (Yüksek)** | `relationship_service.py` | Canlı Arama Durumunun (`user_busy`) 1 Saatlik İzin Önbelleğine Yazılarak Aramaların Kilitlenmesi | Anlık meşguliyetin 1 saatlik cache'e zehirlenmesi, kullanıcının 1 saat aranamaması |
| **SRE-85** | 🟡 **P2 (Orta)** | `delete_conversation_command.py` | Silinen Sohbet Mesajlarının Okunmamış Rozet Filtresinde Kalarak "Hayalet Rozet" Üretmesi | Silinen sohbetler nedeniyle mobil uygulamada asla sıfırlanmayan okunmamış mesaj rozeti |
| **SRE-86** | 🟠 **P1 (Yüksek)** | `ad_service.py` & `feed_queries.py` | Kampanya Duraklatma/Bitişinde `ad_campaigns:active` Setinden `SREM` Yapılmaması | Pasif reklamların sette birikmesi, 50 kotasının dolması ve feed reklamlarının tamamen kilitlenmesi |
| **SRE-87** | 🟠 **P1 (Yüksek)** | `listing_tasks.py` & `listing_cache_service.py` | Süresi Dolan İlanlar Pasife Alınırken Redis Feed ve İlan Cache'inin Temizlenmemesi | Desenkronize zombi ilanlar, mobil akışta pasif ilanların tıklanması ve checkout hataları |
| **SRE-88** | 🟡 **P2 (Orta)** | `health.py` (teqlif-agent) | `_collect_hw_metrics` İçinde Asenkron Event Loop'ta Senkron `time.sleep(1)` Çağrılması | Agent'ın her 5 sn'de 1 tam saniye donması, UDP gossip ve watchdog paketlerinin düşmesi |
| **SRE-89** | 🔴 **P0 (Kritik)** | `calls.py` | `start_call` İçinde Tek Taraflı Callee Lock Nedeniyle Simetrik Arama Çakışması (Glare) | İki kullanıcının birbirini aynı anda aramasıyla çift LiveKit odası oluşması ve sessizlik |
| **SRE-90** | 🟠 **P1 (Yüksek)** | `calls.py` & `webhooks.py` | Grup Katılımcılarına Kapanışın Bildirilmemesi ve Webhook'ta `clear_presence` Eksikliği | Misafirlerin aramada askıda kalması, LiveKit oda kapanışında kullanıcıların 10 dk meşgul kilitlenmesi |
| **SRE-91** | 🟠 **P1 (Yüksek)** | `refresh_stream_token.py` | Token Yenilemede `resolve_stream_endpoint` Çağrılmayarak İzleyicilerin Relay'den Atılması | Token yenileyen yüzlerce izleyicinin relay'den düşüp kaynak node'u (origin) çökertmesi |
| **SRE-92** | 🟡 **P2 (Orta)** | `chat_commands.py` | Bağımsız `INCR/DECR` ile İzleyici Sayacı Bozulması ve `live:viewer_set` TTL'siz Sızıntısı | Mobil reconnect'lerde yapay izleyici şişmesi ve öksüz kalan viewer setlerinin Redis RAM'ini tüketmesi |
| **SRE-93** | 🟠 **P1 (Yüksek)** | `firebase_adapter.py` & `worker.py` | Sözde Multicast İçinde Sıralı Senkron HTTP Döngüsü ve Kritik ARQ Kuyruğunun Felç Olması | Takipçi bildirimlerinde worker'ın 25 dakika donması, kritik zaman aşımlarının çalışamaması |
| **SRE-94** | 🔴 **P0 (Kritik)** | `cancel_withdrawal_request_command.py` | Para Çekim İptalinde Eksik `FOR UPDATE` ile Çift İade ve Çekim-İptal Yarışı | Çift iade ile sınırsız para çoğaltma ve hem nakit hem bakiye haksız kazancı |
| **SRE-95** | 🟠 **P1 (Yüksek)** | `convert_to_teqlik_command.py` & `send_gift_command.py` | Sistem Hesabının (id=0) `teqlik_balance`'ının Güncellenmemesi ve Defter Tutarsızlığı | Platform hazinesinin sıfır kalması, çift taraflı defter mutabakatının bozulması |
| **SRE-96** | 🟠 **P1 (Yüksek)** | `wallet.py` & `send_gift_command.py` | `send-gift` İçinde Canlı Yayın ve Host Doğrulaması Olmaması | Kapanmış yayın üzerinden kara para transferi, sahte hype ve FK çökmesi |
| **SRE-97** | 🟠 **P1 (Yüksek)** | `admin_data.py` | Admin Kampanya Duraklatma ve İlan Pasifleştirmede Redis'in Güncellenmemesi | Adminin durdurduğu reklam/ilanların mobil kullanıcılar için yayında kalması |
| **SRE-98** | 🟡 **P2 (Orta)** | `listings.py` & `get_listing_offers.py` | İlan Tekliflerinin Kimlik Doğrulamasız ve Gizliliksiz Halka Açık Sızması | Özel pazarlık tekliflerinin rakiplerce kazınması ve teklif verenlerin deşifre olması |
| **SRE-99** | 🔴 **P0 (Kritik)** | `auth.py` & `user.py` & `wallet.py` | Redis Oturum Önbelleğinde Eksik Tarih Deserializasyonu (`TypeError` Çökmesi) ve Cüzdanda Eski Bakiye | `pro_expires_at` vb. string kalarak çökme, cüzdan işlemlerinde 15 dk eski bakiye ile yetkisiz kullanım |
| **SRE-100** | 🔴 **P0 (Kritik)** | `listings.py` | Toplu Bildirimde (Blast) Önce Gönderim Sonra Düşüm, `GREATEST(0, ...)` ile Negatif Bakiye Açığı | Yetersiz bakiyeyle bedava bildirim gönderimi ve eksik cache invalidation ile sonsuz blast |
| **SRE-101** | 🟠 **P1 (Yüksek)** | `direct_sale_commands.py` | Direkt Satışta Eşzamanlı Alımlarda Kilitsiz Stok Güncellemesi (Lost Update) ve İptal Sonrası Sipariş | Stok düşümünün ezilmesi, sold_out durumunun bozulması ve iptal edilen satışa yetim sipariş commit'i |
| **SRE-102** | 🟠 **P1 (Yüksek)** | `streams.py` | `get_suggested_streamers` İçinde Her İstekte Milyonluk `follows` ve `live_streams` Full Tablo Taraması | Her sayfa yenilemede filtresiz takipçi ve 90 günlük yayın agregasyonu, Postgres CPU %100 |
| **SRE-103** | 🟡 **P2 (Orta)** | `story_service.py` | Hikaye Görüntüleyenler Endpoint'inde (`get_story_viewers`) Sayfalama Eksikliği | Popüler hikayelerde on binlerce izleyici ve tam User modelinin belleğe yüklenmesi (OOM çökmesi) |
| **SRE-104** | 🟡 **P2 (Orta)** | `video_tasks.py` & `misc_commands.py` | Hype Highlight Videolarının Yerel Diske Kaydedilmesi, Kümede 404 ve Dosya Silinmeme Bellek Sızıntısı | Çoklu node'da video 404, yayın kapandığında DB'den silinirken MP4'ün yerel diskte yetim kalması |
| **SRE-105** | 🔴 **P0 (Kritik)** | `like_service.py` | Canlı Yayın Kalplerinde Senkron DB Commit, Her Kalpte Expire ve Bireysel WS Broadcast Patlaması | 1.000 izleyicili yayında saniyede binlerce DB commit ve milyonlarca WS paketiyle Postgres ve Uvicorn çökmesi |
| **SRE-106** | 🔴 **P0 (Kritik)** | `leads.py` | HTTP Handler İçinde 10.000 Alıcı İçin Senkron ORM Obje Tahsisi ve 200 Sıralı FCM HTTP Çağrısı | 60-120s asılı kalma, 504 Gateway Timeout, Uvicorn worker thread kilitlenmesi ve DoS |
| **SRE-107** | 🔴 **P0 (Kritik)** | `search_alerts.py` & `enums.py` | Arama Alarmı Silmede Enum Uyuşmazlığı (`'passive'`) Nedeniyle Alarmların Asla Silinememesi | PostgreSQL SQLEnum DataError (500) hatası, alarmların silinememesi ve zombi alarmlara sonsuz push bildirimi |
| **SRE-108** | 🟠 **P1 (Yüksek)** | `relationship_service.py` & `call_presence.py` | Anlık Çağrı Meşguliyetinin (`user_busy`) Statik 1 Saatlik İlişki Önbelleğine Gömülmesi | 3. şahısların arama bittikten sonra bile 1 saat boyunca hedefi arayamaması (Cache Poisoning) |
| **SRE-109** | 🟠 **P1 (Yüksek)** | `ad_service.py` | Reklam Tıklama Lua Scriptinde Negatif Bütçe Guard'ı Olmaması ve `ad_campaigns:active` Set İhmali | Bütçe bittikten sonra negatif bakiye harcaması ve duraklatılmış reklamların ana feed'de dönmeye devam etmesi |
| **SRE-110** | 🟠 **P1 (Yüksek)** | `turkish_nlp.py` & `search.py` | Arama Stemmer'ında Tek Tırnak Temizlenmemesi (`to_tsquery` Syntax Error 500) ve Sınırsız Offset DoS | Tırnaklı kelime aramalarında Postgres 500 çökmesi ve büyük offset değerleriyle DB CPU %100 tükenmesi |
| **SRE-111** | 🔴 **P0 (Kritik)** | `storage_service.py` | `minio_public_base` ile Silme Yönlendirme Hatası ve Edge MinIO Terabaytlarca Medya Yetim Sızıntısı | CDN domain'i node_id ile eşleşmediği için silme komutunun yanlış node'a gitmesi, dosyaların silinmemesi |
| **SRE-112** | 🔴 **P0 (Kritik)** | `delete_conversation_command.py` | UoW Context Bloğu Dışında Kapatılmış Session ile DB Sorgusu Çalıştırma (`IllegalStateChangeError`) | Karşılıklı DM silmede connection is closed / inactive transaction hatası ile HTTP 500 çökmesi |
| **SRE-113** | 🟠 **P1 (Yüksek)** | `delete_message_command.py` | Herkesten Silinen Mesajlarda MinIO DM Dosyasının Silinmemesi ve KVKK/Gizlilik İhlali | DB'den satır silinirken özel fotoğrafların ve ses kayıtlarının MinIO `teqlif-dm` bucket'ında kalıcı yaşaması |
| **SRE-114** | 🟠 **P1 (Yüksek)** | `ip_utils.py` & `fraud_detection_service.py` | IPv6 Kullanıcılarında `mask_ip`'nin None Dönmesi ve Shill Bidding Korumasının %100 By-pass Olması | Mobil IPv6 kullanıcılarında IP eşleşmesinin atlanması ve sahte teklifçilerin engellenememesi |
| **SRE-115** | 🟡 **P2 (Orta)** | `chat.py` | Her İzleyici Girişinde Tüm Odaya `system_join` WS Yayını ile Chat Soket DoS'u | 1.000 izleyicili yayında saniyede on binlerce gereksiz sistem mesajı ile mobil istemcilerin donması |
| **SRE-116** | 🟡 **P2 (Orta)** | `prometheus.yml` & `nodeMonitor` | DB, Redis, PgBouncer ve API Metriklerinin Scrape Dışında Kalması (Kör İzleme) | Postgres pool tükenmesi, Redis OOM ve HTTP 5xx fırtınalarında hiçbir alert üretilmeyip kör kalınması |
| **SRE-117** | 🔴 **P0 (Kritik)** | `apple_verifier.py` & `verify_purchase_command.py` | Consumable Alımlarda `originalTransactionId` Kullanılması Nedeniyle Sonraki Alımların Kilitlenmesi | Kullanıcının kartından para çekilmesi ancak sonraki alımların hatalı replay sayılarak Teqlik'lerin yüklenmemesi |
| **SRE-118** | 🔴 **P0 (Kritik)** | `stream_concat_task.py` | Concat Görevinde Yanlış MinIO Node'u, Yetim Part Dosyaları ve Bozuk MP4 Transcode Açığı | Edge node kayıtlarının bulunamaması, GB'larca yetim part birikmesi ve network dalgalanmasında bozuk video |
| **SRE-119** | 🔴 **P0 (Kritik)** | `webhooks.py` | `_delayed_close_stream` Fallback'inde Yanlış Node Sorgulanması Nedeniyle Aktif Yayınların Kapatılması | Node3/Node4 ayrımı yapılmadan rastgele node sorgulanarak yayındaki odaların zorla kapatılması |
| **SRE-120** | 🟠 **P1 (Yüksek)** | `client_log.py` | Mobil Hata Loglarında IP Sahtelemesi/Global Drop ve `entry.details` Log Injection (CWE-117) | Global crash loglarının drop edilmesi ve filtrelenmemiş detaylarla disk doldurma / log manipülasyonu |
| **SRE-121** | 🟠 **P1 (Yüksek)** | `favorites.py` | Favoriden Çıkarılırken İlgisiz Beğeninin (`ListingLike`) Sessizce Silinmesi ve Cache Desync | Kullanıcının beğenisinin habersizce silinmesi, çift tıkta 500 hatası ve Redis beğeni kümesi tutarsızlığı |
| **SRE-122** | 🟠 **P1 (Yüksek)** | `story_service.py` | Story Yükleme Sırasında Senkron FFmpeg Transcoding ile Uvicorn Event Loop Açlığı | Video yüklemelerinde 120s süren FFmpeg ile CPU %100, teklif ve DM isteklerinde 504 Gateway Timeout |
| **SRE-123** | 🟠 **P1 (Yüksek)** | `worker.py` | PgBouncer Transaction Pooling Altında `VACUUM ANALYZE` Nedeniyle Task Çökmesi ve Kilitsiz Silme | Arka plan temizlik görevlerinin her gün çökmesi ve tek sorguda milyonluk silmeyle replication lag patlaması |
| **SRE-124** | 🟠 **P1 (Yüksek)** | `influence_service.py` | Limitsiz `SELECT * FROM follows` Bellek Patlaması (OOM) ve Devasa Redis Pipeline Kilitlenmesi | Yüz binlerce takip ilişkisinin tek sorguda belleğe alınarak worker'ın çökmesi ve Redis soket tıkanması |
| **SRE-125** | 🟡 **P2 (Orta)** | `recommendation_service.py` | Her Feed İsteğinde `SELECT DISTINCT category FROM listings` Full Table Scan ve İndekssiz Sort | Milyonlarca ilanın her feed çağrısında taranması ve `ORDER BY hashtext()` ile DB CPU %100 darboğazı |
| **SRE-126** | 🟡 **P2 (Orta)** | `reports.py` | Şikayet Endpoint'inde Pydantic Şeması ve Karakter Sınırı Olmaması (Disk DoS ve TOCTOU) | Sınırsız metin yüküyle veritabanı şişirme ve eşzamanlı çift istekte IntegrityError 500 çökmesi |
| **SRE-127** | 🔴 **P0 (Kritik)** | `analytics_processor.py` | `calculate_user_budgets` Fonksiyonunda On Binlerce Sıralı UPDATE ve Uzun Açık Transaction | Dakikalarca süren tek transaction, satır kilitleri, PgBouncer pool tıkanması ve tek hatada toplu rollback |
| **SRE-128** | 🔴 **P0 (Kritik)** | `bid_validation_service.py` | Doğrulanmış Hesaplarda Tavan Sınır (Hard Ceiling) Olmaması Nedeniyle Müzayede Sabotajı (Troll Bid Bypass) | Telefon doğrulamalı bir kullanıcının 100 TL'lik canlı yayın ürününe 1 milyar TL teklif verip yayını kilitlemesi |
| **SRE-129** | 🔴 **P0 (Kritik)** | `bootstrap_node1.sh` | Node1 Kurulum Scriptinde `postgresql-17-pgvector` Paketinin Eksik Olması ve Vektör Extension Çökmesi | `vector.control` dosyasının bulunamaması, `CREATE EXTENSION` sessiz hata yutması ve `Vector(384)` sorgularında 500 çökmesi |
| **SRE-130** | 🔴 **P0 (Kritik)** | `bootstrap_node5.sh` | Staging Redis Konfigürasyonunun `/etc/redis` Dizinine Yazılması ve `apply_secrets` Tarafından Atlanması | `<staging_redis_pass>` placeholder'ının değişmeden kalması ve Staging FastAPI'nin `WRONGPASS` ile Redis'e bağlanamaması |
| **SRE-131** | 🔴 **P0 (Kritik)** | `video_tasks.py` | `capture_hype_highlight` İçinde Rastgele Node ile WHEP 404 Hatası ve MinIO Yerine Yerel Diske Kayıt | Highlight'ların %50+ oranla yanlış node sorgulamasıyla başarısız olması ve üretilen MP4'lerin yerel diskte kaybolması |
| **SRE-132** | 🟠 **P1 (Yüksek)** | `fraud_detection_service.py` | Global `fraud_log` Redis ZSET'ine Her Olayda JSON Yazılması ve Her Seferinde `zremrangebyscore` Kilitlenmesi | Yüksek frekanslı troll teklif saldırılarında devasa ZSET temizliği ile Redis tek thread'inin donması ve OOM riski |
| **SRE-133** | 🟠 **P1 (Yüksek)** | `user.py` / `device_service.py` | `User.fcm_token` Tekil Sütun Tasarımı ile Çoklu Cihaz Desteğinin Olmaması ve Toplu Bildirim Kesintisi | İkinci cihazda oturum açınca birincil telefonun bildirim dışı kalması ve tek cihaz invalidation'ında tüm bildirimlerin sıfırlanması |
| **SRE-134** | 🟠 **P1 (Yüksek)** | `livekit_service.py` | `lk_list_all_rooms` ve `lk_broadcast_delete` İçinde Sıralı (Sequential) Döngü ile Blokaj | 1 media node erişilemez olduğunda arka plan temizlik ve senkronizasyonunun 16-60 saniye boyunca kilitlenmesi |
| **SRE-135** | 🟠 **P1 (Yüksek)** | `messages.py` / `media_processor.py` | `_read_streaming` Bellek Çiftlemesi ve HTTP Handler İçinde Senkron Pillow/FFmpeg Süreç Blokajı | 50 MB dosyayı bellekte birleştirip CPU-yoğun thumbnail ve 50s'lik ffmpeg çalıştırma ile Uvicorn event loop açlığı |
| **SRE-136** | 🟠 **P1 (Yüksek)** | `upsert_rating.py` | `upsert_rating` Eşzamanlı İsteklerinde IntegrityError (HTTP 500) Yarışı ve Erken Session Commit Tutarsızlığı | Çift tıkta `ratings_rater_id_rated_id_key` 500 çökmesi ve UoW context'i içinde kontrolsüz commit yapılması |
| **SRE-137** | 🟡 **P2 (Orta)** | `follows.py` | `accept_follow_request` İçinde Koşulsuz `_redis.decr` Nedeniyle Mesaj İstek Sayacının Negatife Düşmesi | Aralarında mesaj isteği olmasa bile sayacın `-1, -2` olması ve mobil badge'in hatalı gösterilmesi |
| **SRE-138** | 🟡 **P2 (Orta)** | `ratings.py` | `mark_read` Endpoint'inde Tüm Nesnelerin Belleğe Çekilip Python Döngüsüyle Tek Tek Güncellenmesi | Tek SQL UPDATE yerine yüzlerce ayrı UPDATE sorgusu atılması ve Redis unread badge önbelleğinin güncellenmemesi |
| **SRE-139** | 🔴 **P0 (Kritik)** | `stream_concat_task.py` | Concat Sonucu Kayıtta `available_at` Eksikliği Nedeniyle Bildirim ve Yaşam Döngüsü Felci | Bildirimlerin gitmemesi, expires_at'in NULL kalması, MinIO ILM ve Node2 yedekleme zincirinin kilitlenmesi |
| **SRE-140** | 🔴 **P0 (Kritik)** | `utils/i18n.py` | `_get_t` İçinde Senkron `create_engine` ile Havuz Sızıntısı ve 3s Uvicorn Event Loop Donması | DB TTL bitiminde her çağrıda unclosed connection pool sızması, Uvicorn'un 3s kilitlenmesi ve WebSocket donmaları |
| **SRE-141** | 🔴 **P0 (Kritik)** | `auth.py` | Doğrulanmamış Telefonun Erken DB Commit'i ile Numara Rehin Alma (Phone DoS) ve Statü Kaybı | Saldırganın mağaza numaralarını bloke etmesi ve yanlış numara giren onaylı kullanıcının anında hakkını kaybetmesi |
| **SRE-142** | 🟠 **P1 (Yüksek)** | `upload.py` | İlan Videosu Yüklemede Senkron FFmpeg/FFprobe ile 504 Timeout ve CPU %100 Açlığı | 60s süren video remuxing sırasında mobil ağın kopması, Nginx 504 hatası ve aynı sunucudaki Postgres'in kilitlenmesi |
| **SRE-143** | 🟠 **P1 (Yüksek)** | `admin_data.py` | Admin Dashboard'da 16 Sıralı Aggregate SQL ve 7 Günlük Döngü ile Postgres CPU Doygunluğu | Her dashboard açılışında full-table scan ile bakiye toplamı ve 7 ayrı tarih sorgusunun DB'yi kilitlemesi |
| **SRE-144** | 🟠 **P1 (Yüksek)** | `admin_data.py` | Analytics Summary Endpoint'inde ClickHouse Yerine PostgreSQL'de `COUNT(DISTINCT)` Kirlenmesi | Milyonlarca analitik satırında unindexed session_id sort/hash ile Postgres buffer cache'inin boşaltılması ve kilitlenme |
| **SRE-145** | 🟡 **P2 (Orta)** | `leads.py` | `/audience-size` Endpoint'inde 10.000 ID'lik `ANY(:ids)` Parametresi ve Önbelleksiz Cross-DB Yükü | Her filtre değişiminde ClickHouse'dan 10.000 ID çekilip Postgres'e devasa array olarak fırlatılması |
| **SRE-146** | 🟡 **P2 (Orta)** | `wallet.py` / `auth.py` | Cüzdan Bakiyesinin 15 Dakikalık Redis Session Cache'inden, İşlemlerin DB'den Çekilmesi Tutarsızlığı | Para transferi ve airdroplarda alıcının işlemler listesinde parayı görmesine rağmen tepedeki bakiyenin 15 dk eski kalması |
| **SRE-147** | 🔴 **P0 (Kritik)** | `auth.py` | Refresh Token Kaydında `token_version` Denetimi Olmaması Nedeniyle Şifre Sıfırlama Sonrası Oturumun Düşmemesi | Çalınan refresh token ile şifre sıfırlanmasına rağmen `/refresh` ile yeni token_version'lı geçerli access token alınabilmesi |
| **SRE-148** | 🟠 **P1 (Yüksek)** | `stream_recording_tasks.py` | `notify_new_recordings_task` İçindeki 6 Saatlik Sınır Nedeniyle Geciken Kayıtların Askıda Kalması ve MinIO Sızıntısı | 6 saatten eski hazır kayıtların bildirim alamaması, expires_at'in sonsuza dek NULL kalarak MinIO'dan silinememesi |
| **SRE-149** | 🟠 **P1 (Yüksek)** | `chat.py` | Canlı Sohbet WebSocket El Sıkışmasında Çift DB Oturumu ve Bilateral Block Sorgusunda `mute_key` TTL Sızıntısı | C10K altında her izleyici bağlantısında Postgres/PgBouncer havuzunun kilitlenmesi ve kalıcı Redis bellek sızıntısı |
| **SRE-150** | 🟠 **P1 (Yüksek)** | `direct_sale.py` / `direct_sale_commands.py` | `purchase_sale` Endpoint'inde Idempotency Key Eksikliği Nedeniyle Mükerrer Sipariş ve Çift Stok Düşümü | Zayıf mobil ağ ve çift tıklamalarda kullanıcının iki kez sipariş vermesi ve stokların haksız yere tükenmesi |
| **SRE-151** | 🟡 **P2 (Orta)** | `notifications.py` | WebSocket El Sıkışmasında DM Filtresinin Unutulması ve Badge Sayısı Titremesi (Flickering) | WS açılışında DM'lerin okunmamış sayılması, REST sorgusunda hariç tutulması sebebiyle mobil bildirim rozetinin titremesi |
| **SRE-152** | 🟡 **P2 (Orta)** | `calls.py` / `models/call.py` | `/history` Arama Geçmişi Sorgusunda `OR` Koşulu ve `started_at` İçin Bileşik İndeks Eksikliği | Kullanıcı arama geçmişi çekildiğinde Postgres'in Bitmap Scan ve disk üzerinde sort yapması, CPU darboğazı |
| **SRE-153** | 🟡 **P2 (Orta)** | `feed.py` | `/signal` Endpoint'inde Her İlan Tıklamasında Senkron NumPy Vektör Matematiği ile Uvicorn Event Loop Donması | İlan tıklamalarında async event loop içinde senkron `np.linalg.norm` ve embedding sorgusu çalıştırılarak API gecikmesi |
| **SRE-154** | 🟡 **P2 (Orta)** | `admin_nodes.py` / `edge_orchestrator.py` | `GET /nodes/{id}` Tekil Düğüm Sorgusunda Tüm Canlı Düğümlerin O(N) `redis.keys()` ile Taranması | Belirli bir node detayı istendiğinde doğrudan anahtara gitmek yerine kümedeki tüm node'ların Redis'ten taranıp filtrelenmesi |
| **SRE-155** | 🔴 **P0 (Kritik)** | `dm_archive_tasks.py` / `storage_service.py` | DM Arşiv Görevinde Yanlış Bucket Okuması Nedeniyle MinIO'daki Tüm Geçmiş DM Arşivlerinin Kalıcı Silinmesi | `get_object_bytes`'ın public bucket'a bakıp None dönmesi, `upload_bytes_dm`'in önceki arşivleri ezmesi ve kalıcı veri kaybı |
| **SRE-156** | 🔴 **P0 (Kritik)** | `auth.py` / `get_conversations_query.py` | `init_context` ve `get_conversations` Endpoint'lerinde Tekil `AsyncSession` Üzerinde `asyncio.gather` ile HTTP 500 Çökmesi | Tek oturumda eşzamanlı DB execute çağrısı nedeniyle `IllegalStateChangeError` oluşması ve uygulamanın açılışta çökmesi |
| **SRE-157** | 🟠 **P1 (Yüksek)** | `worker.py` / `models/message_thread.py` | `cleanup_empty_message_threads_task` İçinde `has_archive` Kontrolü Olmaması Nedeniyle Arşivli Başlıkların Silinmesi | 1 yıldan eski mesajları arşivlenmiş konuşmaların boş sanılarak silinmesi, kullanıcı izin ve arşiv bağlarının yok olması |
| **SRE-158** | 🟠 **P1 (Yüksek)** | `leads.py` | `send_retargeting` Endpoint'inde Bakiye Düşümü Öncesinde Push Gönderilmesi Nedeniyle Karşılıksız Bildirim İstismarı | 500 kişiye önce bildirim fırlatılıp sonra bakiye düşülmeye çalışılması, bakiye yetersizliğinde dahi ücretsiz bildirim sızıntısı |
| **SRE-159** | 🟠 **P1 (Yüksek)** | `calls.py` | `start_call` Başlatma Sırasında Yalnızca `callee_id` Üzerine Advisory Lock Alınması Nedeniyle Karşılıklı Çift Çağrı | İki kullanıcının birbirini aynı anda araması durumunda iki ayrı çağrı ve LiveKit odası oluşması, split-brain durumu |
| **SRE-160** | 🟡 **P2 (Orta)** | `ads.py` | `create_campaign` Endpoint'inde `total_budget` ve `cpc_bid` Üzerinde Tavan Kontrolü Olmaması Nedeniyle Bütçe Enflasyonu | Satıcının 50 TEQlik flat boost ile 1 milyar bütçeli hayali kampanya açabilmesi, feed açık artırma algoritmasının manipülasyonu |
| **SRE-161** | 🔴 **P0 (Kritik)** | `auction_commands.py` / `auction_redis_repo.py` | `accept_bid` Sırasında Redis'te Atomik Kilitleme Olmaması Nedeniyle Eşzamanlı Tekliflerle Haksız İhale Gasbı | Teklif kabul DB süreci sırasında Redis'in aktif kalması, daha yüksek tekliflerin ezilip önceki teklifin kazanan yapılması |
| **SRE-162** | 🔴 **P0 (Kritik)** | `admin_data.py` | `purge_user` Endpoint'inde `token_version` Artırılmaması ve Session Cache/İlanların Temizlenmemesi | Anonimize edilip silinen kullanıcının JWT ve Redis oturumunun 15 dk sürmesi, ilan ve yayınların piyasada sahipsiz kalması |
| **SRE-163** | 🟠 **P1 (Yüksek)** | `admin_data.py` | `update_user_info` İçinde Yalnızca `PASSIVE` Durumunda `token_version` Artırılması Nedeniyle Banlanan Kullanıcının Oturumunun Sürmesi | Admin tarafından `banned` veya `deleted` yapılan kötü niyetli kullanıcıların JWT oturumlarının iptal edilmemesi ve API erişimini sürdürmesi |
| **SRE-164** | 🟠 **P1 (Yüksek)** | `pro_insights_use_case.py` | `ProInsightsUseCase` İçinde `auctions` ve `bids` Tablolarının Çarpımsal Join Edilmesi Nedeniyle Şişirilmiş `bid_count` | Stream bazlı açık artırmalarla tekliflerin kartezyen çarpılması sonucu satıcı panelinde teklif sayısının katlanarak yanlış gösterilmesi |
| **SRE-165** | 🟡 **P2 (Orta)** | `onboarding.py` / `user_interest.py` | `seed_interests` Endpoint'inde `NULL` Subcategory Nedeniyle PostgreSQL Unique Constraint İhlali ve Mükerrer Kayıt | PostgreSQL'de NULL değerlerin unique kısıtını bypass etmesi sonucu her onboarding isteğinde mükerrer kategori satırları oluşması |
| **SRE-166** | 🟡 **P2 (Orta)** | `bpr_service.py` | `train_bpr` İçinde Hard Negative Örneklemesinde 200 Milyonluk Kartezyen Döngü ve Negatif Ağırlıkların Matris Dışında Kalması | 20 bin ilan ve 10 bin kullanıcı için 200M iterasyonluk döngüyle RAM'in şişirilmesi, üretilen verinin `w > 0` filtresiyle tamamen atılması |
| **SRE-167** | 🔴 **P0 (Kritik)** | `referral_service.py` / `auth.py` / `users.py` | `apply_referral` İçinde Eksik `_get_t` Import'u Nedeniyle HTTP 500 Çökmesi ve Oturum Önbelleği İptal Edilmemesi | Davet kodu kullanımı ve onaylı kullanıcıların e-posta/SMS doğrulamasında `NameError` ile çökmesi; +50 TEQlik bakiyesinin 15 dk boyunca önbellekte güncellenmemesi |
| **SRE-168** | 🔴 **P0 (Kritik)** | `nsfw_service.py` | `check_listing_nsfw` İçinde Eksik `ListingStatus` Import'u Nedeniyle Müstehcen İçeriklerin Askıya Alınamaması | NudeNet analizinde `max_score >= 0.85` olduğunda worker'ın `NameError: ListingStatus` ile çökmesi, pornografik ve müstehcen ilanların platformda sansürsüz yayında kalması |
| **SRE-169** | 🟠 **P1 (Yüksek)** | `analytics.py` | Pro Analitik Endpoint'lerinde Eksik `_dt` ve `_td` Import'u Nedeniyle Tarih Filtreli İsteklerde HTTP 500 Çökmesi | `video_roi`, `gallery_stats` ve `video_perf` sorgularında `start_date` veya `end_date` verildiğinde `NameError: name '_dt' is not defined` ile çöküş |
| **SRE-170** | 🟠 **P1 (Yüksek)** | `worker.py` | `cleanup_ghost_calls_task` İçinde Eksik `ws_manager` Import'u Nedeniyle Hayalet Arama WebSocket Bildirimlerinin Düşmesi | Hayalet aramaların sonlandırılmasında `NameError` hatasının sessizce yutulması ve arayan/aranan kullanıcıların arama ekranında kilitli kalması |
| **SRE-171** | 🔴 **P0 (Kritik)** | `worker.py` | `flush_interactions_to_db` İçinde `len(raw_items)` Yerine Sabit `BATCH_LIMIT` ile `LTRIM` Yapılması Nedeniyle Eşzamanlı Gelen Etkileşimlerin Silinmesi | Her 5 dakikada bir PG yazımı sürerken gelen tüm kullanıcı tıklama, dwell ve teklif sinyallerinin Redis'ten kalıcı olarak silinmesi ve ML modellerinin sakatlanması |
| **SRE-172** | 🔴 **P0 (Kritik)** | `failover_stream.py` | Canlı Yayın Düğüm Arızasında (`failover_stream`) Yeni Odaya Taşınan Yayının İzleyicilere Bildirilmemesi | Medya sunucusu çöktüğünde host'un yeni odaya geçmesi ancak izleyicilerin ölü düğümde kilitli kalması ve yayının 0 izleyiciyle devam etmesi |
| **SRE-173** | 🟠 **P1 (Yüksek)** | `convert_to_teqlik_command.py` / `wallet.py` | Kazanç Bakiyesini TEQlik'e Dönüştürmede (`convert-to-teqlik`) Redis Oturum Önbelleğinin Geçersiz Kılınmaması | Harcanabilir bakiyeye çevrilen TEQlik'lerin 15 dakika boyunca oturumda görünmemesi ve kullanıcıların yetersiz bakiye hatası alması |
| **SRE-174** | 🟠 **P1 (Yüksek)** | `create_offer.py` / `listings.py` | İlan Teklifi Verildiğinde Satıcıya Push ve WebSocket Bildirimi Gönderilmemesi | Alıcı teklif verdiğinde satıcıya hiçbir bildirim gitmemesi, tekliflerin yanıtsız kalması ve satış döngüsünün durması |


---

## 🔍 Detaylı Bulgular ve Çözüm Reçeteleri

---

### SRE-01 · 🔴 P0 (Kritik) · Canlı Yayın Birleştirmede Sonsuz Döngü ("Zehirli Hap" / Poison Pill)

> ✅ **Çözüldü** — Commit `80352d6b` · 2026-10-29

* **Etkilenen Dosya:** `backend/app/tasks/stream_concat_task.py`
* **İlgili Satırlar:** 122–132, 23–33
* **Zamanlama:** `worker.py` satır 4346: `cron(stream_concat_task, minute=set(range(0, 60, 2)))` (Her 2 dakikada bir)

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın parçaları MinIO'dan indirilip `ffmpeg` ile birleştirilirken, dosyalardan biri bozuk (corrupt) ise FFmpeg hata verir (`proc.returncode != 0`). 
Mevcut kodda bu durum şöyle ele alınmıştır:
```python
if proc.returncode != 0:
    logger.error("_run_concat: ffmpeg hata stream_id=%s: %s", stream_id, stderr.decode()[-500:])
    return  # <-- HATA BURADA!
```
Fonksiyon sadece log basıp `return` etmektedir. Veritabanındaki `stream_recordings` tablosundaki kayıtların durumu **`status = 'available'` olarak kalmaya devam eder.**
`stream_concat_task` her **2 dakikada bir** çalıştığı için, bir sonraki turda aynı bozuk stream'i tekrar listeler (`SELECT ... WHERE status = 'available'`), tekrar MinIO'dan indirir, tekrar FFmpeg çalıştırır ve tekrar patlar.
Bu durum **sonsuz bir döngü** yaratır; sunucunun bant genişliği, CPU'su ve disk I/O'su her 2 dakikada bir aynı bozuk dosya için tükenir.

#### 2. Çözüm / Refactoring Reçetesi
1. `stream_recordings` tablosuna `retry_count (INTEGER DEFAULT 0)` ve `last_error (TEXT)` sütunları eklenmeli veya `status` enum'una `concat_failed` durumu eklenmelidir.
2. FFmpeg hata verdiğinde:
   * İlgili part'ların `retry_count` değeri artırılmalı.
   * `retry_count >= 3` olduğunda parçaların durumu `status = 'concat_failed'` yapılmalı ve Telegram / Sentry alarmı tetiklenmelidir.
3. Böylece bozuk kayıt havuzdan çıkar ve sonraki 2 dakikalık periyotlarda tekrar işlenmez.

---

### SRE-02 · 🔴 P0 (Kritik) · FAISS Vektör İndeksinde Yarış Durumu (Race Condition) ve Canlıda Çökme

> ✅ **Çözüldü** — Commit `80352d6b` · 2026-10-29

* **Etkilenen Dosya:** `backend/app/services/ml/faiss_service.py`
* **İlgili Satırlar:** 37–67, 152–165

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Canlı Dosya Üzerine Doğrudan Yazım (Non-Atomic Write):**
   `rebuild_index()` fonksiyonu hesaplanan yeni indeksi doğrudan canlı dosyanın üzerine yazar:
   ```python
   faiss.write_index(idx, _INDEX_PATH)
   np.save(_ID_MAP_PATH, ids)
   ```
   Canlı API trafiğinde kullanıcılar arama yaparken (`faiss_search`) tam o salisede diskteki dosya yazılıyor olursa, okuyucu süreç eksik/yarım yazılmış dosyayı okumaya çalışır. FAISS C++ kütüphanesi EOF veya bellek hatası alarak **Segmentation Fault** fırlatır ve Uvicorn worker sürecini anında düşürür.
2. **Desenkronizasyon Riski:** `write_index` tamamlanıp `np.save` diske yazılırken bir kesinti olursa, vektör indeksi ile ID haritası birbiriyle uyumsuz hale gelir; kullanıcı bir ilanı ararken tamamen alakasız başka bir ilanın ID'si döner.
3. **Syscall Fırtınası:** `faiss_search()` fonksiyonunun başındaki `_ensure_index()` her arama isteğinde diske gidip `os.path.getmtime(_INDEX_PATH)` çağırır. Saniyede 200 arama alan bir sistemde disk stat syscall'ları I/O darboğazı yaratır.
4. **Hardcoded Yol:** `_INDEX_PATH = "/var/www/teqlif.com/faiss/listings_384.index"` kodu taşınabilir değildir; Docker, test ortamı veya staging'de patlar.

#### 2. Çözüm / Refactoring Reçetesi
1. **Atomik Dosya Değişimi (Atomic File Replacement):**
   * Yeni indeks geçici bir dosyaya yazılmalı: `_INDEX_PATH + ".tmp"` ve `_ID_MAP_PATH + ".tmp"`.
   * Her iki dosya da başarıyla yazıldıktan sonra POSIX atomik rename fonksiyonu olan `os.replace(tmp, target)` ile yer değiştirilmelidir.
2. **mtime Önbelleklemesi:** `_ensure_index()` içindeki disk kontrolü her istekte değil, bir `last_checked_at` zaman damgasıyla en fazla **30 saniyede bir** çalıştırılmalıdır.
3. **Yapılandırma (Settings):** Dosya yolu `settings.faiss_index_dir` üzerinden dinamik alınmalı, dizin yoksa otomatik oluşturulmalıdır.

---

### SRE-03 · 🟠 P1 (Yüksek) · ARQ Worker Görev Zaman Aşımı (300sn) vs Uzun Video İşleme Süresi Çelişkisi

> ✅ **Çözüldü** — Commit `80352d6b` · 2026-10-29

* **Etkilenen Dosyalar:** `backend/app/worker.py` (satır 4364–4367) ve `backend/app/tasks/stream_concat_task.py` (satır 12–14)

#### 1. Sorunun Tanımı ve Arıza Modu
`WorkerSettings` (default queue) konfigürasyonunda tüm görevler için tek bir global timeout belirlenmiştir:
```python
max_jobs = 20
job_timeout = 300     # 5 dakika
max_tries = 3
```
Ancak `stream_concat_task` içinde tanımlanan kilit süresi:
```python
_LOCK_TTL_SEC = 3600  # 1 saat
```
1-2 saatlik bir canlı yayının (5-6 GB) MinIO'dan yerel diske indirilmesi, FFmpeg ile işlenmesi ve MinIO'ya geri yüklenmesi yoğun disk/ağ anında 5 dakikayı (300 saniye) aşabilir. 
300. saniyede ARQ, işlemi acımasızca öldürür (`JobTimeoutError`). Görev yarıda kesilir, `max_tries = 3` olduğu için baştan başlar ve 3 kez 5'er dakika sunucu kaynaklarını tüketip en sonunda başarısız olur.

#### 2. Çözüm / Refactoring Reçetesi
1. `WorkerSettingsCritical` gibi, video işleme için de **`WorkerSettingsVideo` (Bulkhead Pattern)** oluşturulmalıdır.
2. `stream_concat_task` bağımsız bir `video` kuyruğuna (`queue_name = "video"`) taşınmalı; `job_timeout = 1800` (30 dakika) ve `max_jobs = 2` olarak sınırlandırılmalıdır (FFmpeg'in CPU'yu boğmaması için).

---

### SRE-04 · 🟠 P1 (Yüksek) · Sınırsız Veri Çekimi (Unbounded Query) ve Bellek Tüketimi (OOM Riski)

> ✅ **Çözüldü** — Commit `80352d6b` · 2026-10-29

* **Etkilenen Dosyalar:**
  * `backend/app/services/ml/bpr_service.py` (satır 134–147)
  * `backend/app/services/ml/feed_als_ml.py` (satır 122–143)

#### 1. Sorunun Tanımı ve Arıza Modu
`bpr_service.py` içindeki şu sorgu PostgreSQL'e atılmaktadır:
```python
SELECT user_id, item_id, interaction_type, COUNT(*) AS cnt
FROM user_interactions
WHERE interaction_type = ANY(...)
  AND created_at >= NOW() - INTERVAL '120 days'
GROUP BY user_id, item_id, interaction_type
```
Ve ardından:
```python
interactions = rows.fetchall()  # <-- TÜM SATIRLAR PYTHON RAM'İNE ALINIYOR
```
Platformda 50.000 aktif kullanıcı olduğunda, 120 günlük etkileşim tablosu (görüntüleme, tıklama, favori) **on milyonlarca satıra** ulaşır. 
`rows.fetchall()` çağrısı tüm bu veriyi Python heap belleğine tek bir nesne olarak yüklemeye çalışır. Bu işlem Python sürecinin belleğini saniyeler içinde 4-8 GB'a fırlatır ve sunucuda **OOM (Out Of Memory) çökmesine** sebep olur.

Aynı problem `feed_als_ml.py` içinde ClickHouse'dan çekilen 30 günlük veride de (`rows = result.result_rows`) mevcuttur.

#### 2. Çözüm / Refactoring Reçetesi
1. 120 gün yerine son **30 veya 45 gün** ile sınırlandırılmalıdır.
2. Sorgu seviyesinde hacim filtresi getirilmelidir: Etkileşimi 1 olan önemsiz veriler elenmeli (`HAVING COUNT(*) >= 2`).
3. Veri doğrudan bellek dizisine değil; parça parça işlenerek seyrek matrise (scipy CSR matrix) aktarılmalı veya bir satır tavanı (`LIMIT 500000`) konulmalıdır.

---

### SRE-05 · 🟠 P1 (Yüksek) · `foryou_worker.py`: N+1 Sıralı Ağ Çağrısı ve Pasif Kullanıcılar İçin Gereksiz Hesaplama

* **Etkilenen Dosya:** `backend/app/services/feed/foryou_worker.py`
* **İlgili Satırlar:** 28–33, 52–90

#### 1. Sorunun Tanımı ve Arıza Modu
```python
async with AsyncSessionLocal() as db:
    result = await db.execute(select(User.id).where(User.status == UserStatus.ACTIVE))
    users = result.scalars().all()

for uid in users:
    bpr_data = await redis.get(f"bpr:rec:{uid}")  # <-- HER KULLANICI İÇİN AYRI AĞ ÇAĞRISI
    # ... hesaplamalar ...
    await redis.set(f"feed:foryou:{uid}", json.dumps(final_feed), ex=_FORYOU_TTL)  # <-- TEKRAR ÇAĞRI
```
1. **N+1 Ağ Çağrısı:** 50.000 aktif kullanıcı olduğunda bu döngü ardışık **100.000 adet `await` ağ isteği** yapar. Tek bir worker iş parçacığı dakikalarca bu döngüde kilitli kalır.
2. **Hayalet Kullanıcı İsrafı:** `status == ACTIVE` şartı, 6 aydır uygulamayı açmayan kullanıcıları da kapsar. Sisteme hiç girmeyen 40.000 pasif kullanıcı için her gün boş yere ForYou akışı hesaplanıp Redis RAM'inde saklanır.

#### 2. Çözüm / Refactoring Reçetesi
1. **Sadece Aktif Kullanıcıları Hedefle:** Sorgu şu şekilde güncellenmelidir:
   ```python
   WHERE User.status == UserStatus.ACTIVE AND User.last_active_at >= NOW() - INTERVAL '7 days'
   ```
2. **Redis Pipeline ile Batch İşleme:** Kullanıcılar 500'lük gruplar halinde işlenmeli; okuma (`mget`) ve yazma (`pipeline()`) toplu olarak gerçekleştirilmelidir.

---

### SRE-06 · 🟠 P1 (Yüksek) · Sınırsız Redis Pipeline Yüklemesi (Buffer Bloat)

* **Etkilenen Dosyalar:** `feed_als_ml.py` (satır 218–229) ve `swipe_live_ml.py` (satır 195–206)

#### 1. Sorunun Tanımı ve Arıza Modu
```python
redis = await get_redis()
pipe = redis.pipeline()

for uid, ui in u2i.items():
    pipe.setex(_USER_VEC_KEY.format(uid=uid), _ALS_TTL, uf[ui].tobytes())
for lid, li in l2i.items():
    pipe.setex(_ITEM_VEC_KEY.format(lid=lid), _ALS_TTL, itf[li].tobytes())

await pipe.execute()  # <-- TEK SEFERDE ON BİNLERCE KOMUT
```
Kullanıcı sayısı 50.000, ilan sayısı 100.000 olduğunda; `pipe.execute()` tek bir TCP paketi yığını olarak Redis'e **150.000 komut** fırlatır.
Bu durum:
* Redis sunucusunun tek iş parçacıklı event-loop'unu yüzlerce milisaniye dondurur (o sırada gelen canlı API istekleri Redis timeout alır).
* Redis'in istemci çıkış arabelleğini (`client-output-buffer-limit`) aşarak bağlantının kopmasına neden olabilir.

#### 2. Çözüm / Refactoring Reçetesi
Pipeline işlemleri **1.000'lik veya 2.000'lik paketlere (chunk)** bölünerek yürütülmelidir:
```python
BATCH_SIZE = 1000
items = list(u2i.items())
for i in range(0, len(items), BATCH_SIZE):
    pipe = redis.pipeline()
    for uid, ui in items[i:i + BATCH_SIZE]:
        pipe.setex(_USER_VEC_KEY.format(uid=uid), _ALS_TTL, uf[ui].tobytes())
    await pipe.execute()
```

---

### SRE-07 · 🟡 P2 (Orta) · Cüzdan ve Karşılıklı Transferlerde Veritabanı Kilitlenmesi (Deadlock / 40P01)

* **Etkilenen Dosya:** `backend/app/use_cases/wallet/commands/transfer_teqlik.py`
* **İlgili Satırlar:** 38–52

#### 1. Sorunun Tanımı ve Arıza Modu
Mevcut transfer komutunda güncelleme sırası şöyledir:
1. `sender_id` kullanıcısının bakiyesi düşürülür (Postgres satır kilidi alınır).
2. `receiver_id` kullanıcısının bakiyesi artırılır (Postgres satır kilidi alınır).

Eğer tam aynı anda:
* **İşlem 1:** Kullanıcı 10, Kullanıcı 20'ye transfer yaparsa (Önce 10'u kilitler, sonra 20'yi bekler).
* **İşlem 2:** Kullanıcı 20, Kullanıcı 10'a transfer yaparsa (Önce 20'yi kilitler, sonra 10'u bekler).

PostgreSQL bu durumu tespit eder ve **`deadlock_detected` (SQLSTATE 40P01)** hatası fırlatarak işlemlerden birini iptal eder.

#### 2. Çözüm / Refactoring Reçetesi
Satır kilitleri (Lock Order) her zaman **deterministik bir sıralama (küçük ID'den büyük ID'ye)** ile alınmalıdır:
```python
first_lock_id = min(sender_id, receiver_id)
second_lock_id = max(sender_id, receiver_id)

# Önce first_lock_id satırı, ardından second_lock_id satırı kilitlenmeli / güncellenmelidir.
```
Böylece iki işlem de aynı sıralamayla kilit talep edeceği için deadlock oluşması matematiksel olarak imkansız hale gelir.

---

### SRE-08 · 🟡 P2 (Orta) · Açık Transaction İçinde Binlerce Döngüsel SQL (`wallet_tasks.py`)

* **Etkilenen Dosya:** `backend/app/tasks/wallet_tasks.py`
* **İlgili Satırlar:** 38–94 (`release_pending_earnings_task`)

#### 1. Sorunun Tanımı ve Arıza Modu
```python
async with AsyncSessionLocal() as session:
    locked = await session.execute(...)
    rows = locked.fetchall()

    for user_id, total in rows:  # Binlerce kullanıcı
        await session.execute("UPDATE user_wallet_earnings ...")
        await session.execute("SELECT available ...")
        await session.execute("INSERT INTO wallet_ledger ...")

    await session.execute("UPDATE gift_events ...")
    await session.commit()
```
5.000 kullanıcının bekleyen bakiyesi açılırken, tek bir veritabanı oturumu (`session`) içinde **15.000 ayrı SQL ifadesi** tek tek çalıştırılır ve en son `commit()` edilir.
* Bu uzun işlem boyunca veritabanı transaction'ı dakikalarca açık kalır.
* Postgres WAL (Write-Ahead Logging) şişer, satırlar üzerinde lock birikir.
* 4.999. kullanıcıda ağ koparsa tüm işlem rollback olur ve hiçbir kullanıcının kazancı onaylanamaz.

#### 2. Çözüm / Refactoring Reçetesi
1. İşlem tek tek satır döngüsüyle değil; küme tabanlı (set-based) SQL sorgusuyla tek bir `UPDATE ... FROM` ifadesiyle toplu olarak yapılmalıdır.
2. Veya kullanıcılar **100'lük gruplar (batches)** halinde işlenip her 100 kullanıcıda bir `session.commit()` çağrılmalıdır.

---

### SRE-09 · 🟡 P2 (Orta) · Pazar Günü "Süper Fırtına" Yığılması (Schedule Storm)

* **Etkilenen Dosya:** `deploy/scale/V2.1/schedule.yaml`
* **İlgili Satırlar:** 257–300

#### 1. Sorunun Tanımı ve Arıza Modu
Pazar sabahı arka arkaya 5 adet ağır ML ve analitik görevi sabit saatlerle planlanmıştır:
* `05:15` train_swipe_live_als_task
* `05:30` train_item2vec_task
* `05:45` train_kmeans_cold_start_task
* `06:00` train_feed_als_task
* *(Ve node2 üzerinde saat 08:30'da haftalık `pg_basebackup`)*

Veri hacmi arttığında bir eğitim görevinin 15 dakikada bitmemesi kaçınılmazdır. Bir görev 25 dakika sürdüğünde, 05:30'daki Item2Vec ile aynı anda çalışmaya başlar; bellek ve CPU tüketimi ikiye katlanır. Pazar sabahı canlı kullanıcı trafiği uyandığında sunucu %100 CPU ile yanıt veremez hale gelir.

#### 2. Çözüm / Refactoring Reçetesi
Bu işler cron zamanlarıyla birbirinden bağımsız değil, bir **İş Akışı Zinciri (Pipeline DAG)** olarak kurgulanmalıdır:
* Cron sadece saat `05:00`'da ana görevi (`run_ml_training_pipeline`) tetiklemelidir.
* Ana görev sırasıyla: ALS biter -> ardından Item2Vec başlar -> o biter -> KMeans başlar şeklinde ardışık (sequential) olarak çalıştırılmalıdır.

---

### SRE-10 · 🟢 P3 (Düşük) · ML Eğitim Görevlerinde Dağıtık Kilit (Distributed Lock) Eksikliği

* **Etkilenen Dosyalar:** `feed_als_ml.py`, `swipe_live_ml.py`, `bpr_service.py`

#### 1. Sorunun Tanımı ve Arıza Modu
`stream_concat_task.py` içinde `redis.set(lock_key, "1", nx=True, ex=...)` ile harika bir dağıtık kilit kurulmuşken; `train_feed_als`, `train_bpr` ve `train_swipe_live_als` fonksiyonlarında hiçbir kilit kontrolü yoktur.
Eğer bir görev timeout nedeniyle yeniden kuyruğa girerse veya bir geliştirici manuel olarak tetiklerse, aynı anda iki model eğitimi başlar. İki süreç aynı anda CPU'nun tüm çekirdeklerini sömürür ve Redis'teki anahtarları birbirinin üzerine yazar.

#### 2. Çözüm / Refactoring Reçetesi
Tüm ML eğitim fonksiyonlarının başına Redis tabanlı dağıtık kilit (`lock:ml:{task_name}`) eklenmeli; kilit alınamazsa görev güvenli şekilde loglanıp atlanmalıdır (`return`).

---

### SRE-11 · 🔴 P0 (Kritik) · Açık Artırmada İki Aşamalı Tutarsızlık ve Reddedilen Tekliflerin DB'de Kalması

* **Etkilenen Dosyalar:** 
  * `backend/app/use_cases/auctions/commands/auction_commands.py` (satır 427–479)
  * `backend/app/use_cases/auctions/queries/auction_queries.py` (satır 13–31)
  * `backend/app/repositories/auction_redis_repo.py` (satır 37–65)

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı açık artırmada teklif verme (`place_bid`) metodunda ölümcül bir iki aşamalı mutabakat (2-Phase Commit desynchronization) hatası vardır:
```python
# 1. PostgreSQL'e commit edilir (Kayıt kalıcı olur!)
new_bid = Bid(stream_id=stream_id, bidder_id=user.id, amount=data.amount, ...)
self.uow.session.add(new_bid)
await self.uow.session.commit()

# 2. Redis atomik güncelleme denenir
ok, msg = await self.redis_repo.execute_bid(stream_id, float(data.amount), user.id, user.username)
if ok == 0:
    # Eşzamanlı yarış: Başka bir kullanıcı daha yüksek teklif verdi!
    # HATA 1: new_bid zaten PostgreSQL'e commit edildi! Geri alınamaz (rollback imkansız).
    # HATA 2: Aşağıdaki kurgu:
    last_bid = (await self.uow.session.execute(
        select(Bid).where(Bid.stream_id == stream_id).order_by(Bid.created_at.desc()).limit(1)
    )).scalar_one_or_none()
    if last_bid and float(last_bid.amount) > redis_current:
        await self.redis_repo.update_bid_state(...)
    raise BadRequestException(code="CONCURRENT_BID_OUTBID")
```
**Neden Felaket?**
1. **Reddedilen Teklif DB'de Kalır:** Kullanıcıya `400 CONCURRENT_BID_OUTBID` ("Teklifiniz geride kaldı") dönülmesine rağmen, o teklif PostgreSQL'deki `bids` tablosuna kalıcı olarak yazılmıştır! `GetBidsQuery` sorgulandığında kullanıcılar reddedilmiş, geçersiz teklifleri geçerli bir teklifmiş gibi geçmişte görürler.
2. **Kendi Kendini Ezme:** `last_bid` sorgusu az önce commit edilen reddedilmiş teklifi getirir. Eğer Redis state o an bir senkronizasyon anomalisindeyse, sistem reddedilmiş teklifi Redis'e "lider teklif" olarak zorla yazabilir!
3. **Mali ve Hukuki Uyuşmazlık:** İhale tamamlandığında (`end_auction`) kazanan kişi ve fiyat DB'deki `bids` geçmişi ile tutarsızlaşır.

#### 2. Çözüm / Refactoring Reçetesi
1. **Redis-First Concurrency:** Açık artırma gibi milisaniyelik çekişmelerde concurrency arbiter Redis Lua scripti olmalıdır.
   * `execute_bid` Lua scripti ÖNCE çalıştırılmalıdır (Atomik CAS - Compare And Set).
   * Yalnızca Redis'ten `ok == 1` gelirse PostgreSQL'e `new_bid` eklenmeli ve commit edilmelidir.
   * Eğer PostgreSQL commit patlarsa (nadir 500 durumu), Redis'te önceki teklife rollback (veya telafi event'i) uygulanır.
2. **Alternatif (Transaction İçinde Bekletme):** Eğer DB-first kalınacaksa, `session.commit()` Redis çağrısından SONRAYA alınmalıdır:
   ```python
   self.uow.session.add(new_bid)
   await self.uow.session.flush() # ID üretilir ama transaction açık kalır
   ok, msg = await self.redis_repo.execute_bid(...)
   if ok == 0:
       await self.uow.session.rollback() # DB kaydı temizlenir!
       raise BadRequestException(code="CONCURRENT_BID_OUTBID")
   await self.uow.session.commit()
   ```

---

### SRE-12 · 🔴 P0 (Kritik) · Uvicorn 8 Worker Çoğaltması Nedeniyle Arka Plan Scheduler ve Flush Görevlerinin 8 Kat Çalışması

* **Etkilenen Dosyalar:** 
  * `backend/main.py` (satır 121–144)
  * `deploy/scale/V2.1/node1/systemd/teqlif.service` (satır 18)

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif.service` incelendiğinde FastAPI'nin 8 iş parçacığıyla (Uvicorn workers) başlatıldığı görülmektedir:
```ini
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn main:app --workers 8 ...
```
Uvicorn `--workers 8` ile çalıştığında, birbirinden izole 8 ayrı Python işletim sistemi süreci (fork process) ayağa kaldırır.
`backend/main.py` dosyasındaki `lifespan` yöneticisi ise şunları başlatır:
```python
flush_task = start_flush_loop()                              # Satır 122
ds_scheduler_task = asyncio.create_task(direct_sale_scheduler()) # Satır 141
hype_manager.start_decay()                                   # Satır 144
```
**Sonuç:**
* **8 Ayrı Scheduler:** 8 ayrı Uvicorn süreci aynı anda her 10 saniyede bir `direct_sale_scheduler` çalıştırır; PostgreSQL'e sürekli `SELECT ... FOR UPDATE SKIP LOCKED` sorguları atarak connection havuzunu tüketir.
* **8 Ayrı ClickHouse Flush Loop:** Her 30 saniyede bir 8 ayrı worker aynı anda Redis'teki buffer kuyruklarını (`_drain`) boşaltmaya çalışır ve ClickHouse'a mikro-batch parçacıkları gönderir. ClickHouse çok sayıda küçük batch yazımını sevmez (Parts Too Many hatasına yol açar).
* Web sunucuları yalnızca HTTP/WS isteklerine yanıt vermelidir; periyodik arka plan scheduler'lar web lifespane bağlanmamalıdır.

#### 2. Çözüm / Refactoring Reçetesi
1. `direct_sale_scheduler` ve `start_flush_loop` gibi sürekli dönen arka plan scheduler döngüleri `main.py`'dan tamamen kaldırılmalıdır.
2. Bu görevler `worker.py` (ARQ background worker) içinde tekil (singleton) olarak tanımlanmalıdır:
   * `flush_clickhouse_task`: ARQ cron görevi olarak her 30 saniyede bir tek bir iş parçacığı tarafından yürütülmelidir.
   * `direct_sale_overdue_check_task`: ARQ cron görevi veya bağımsız bir systemd timer/daemon tarafından yürütülmelidir.
3. Web worker'larda yalnızca WebSocket pub/sub dinleyicileri kalmalıdır (`chat_pubsub_listener`, `dm_pubsub_listener` gibi WS broadcast için worker başına zorunlu olanlar).

---

### SRE-13 · 🟠 P1 (Yüksek) · ClickHouse Buffer Boşaltımında Sessiz Veri Kaybı ve Finansal Event Riski

* **Etkilenen Dosya:** `backend/app/database_clickhouse.py` (satır 451–464, 466–574)

#### 1. Sorunun Tanımı ve Arıza Modu
`database_clickhouse.py` içindeki `_drain` fonksiyonu şu şekilde çalışmaktadır:
```python
async def _drain(redis, buf_key: str) -> list[list]:
    async with redis.pipeline(transaction=True) as pipe:
        await pipe.lrange(buf_key, 0, MAX_BATCH - 1)
        await pipe.ltrim(buf_key, MAX_BATCH, -1)   # <-- REDİS'TEN HEMEN SİLİNİYOR!
        results = await pipe.execute()
    ...
    return out
```
Ardından `flush_all_buffers` içinde:
```python
rows = await _drain(redis, _BUF_USER_EVENTS)
if rows:
    await _client.insert(...) # <-- HATA BURADA ÇIKARSA?
```
Ve hata bloğu:
```python
except Exception as exc:
    logger.warning("[ClickHouse] flush_all_buffers başarısız: %s", exc)
```
Eğer ClickHouse geçici olarak kapanırsa, WireGuard ağı (10.10.0.3) anlık koparsa veya timeout olursa:
* `_drain` veriyi Redis listesinden **zaten silmiştir** (`ltrim`).
* `_client.insert()` hata verir ve exception yakalanıp sadece bir satır log basılır.
* Çekilen 5.000 analitik satırı ve **Doğrudan Satış Finansal Olayları (`_BUF_DIRECT_SALE_EVENTS` - satır 530)** kalıcı olarak **YOK OLUR**.
* Kodun başındaki "Finansal veri için bu pattern kullanılmamalıdır" uyarısına rağmen, canlı yayında sipariş, stok ve ciro loglarını tutan `direct_sale_events` tablosu bu fonksiyonla boşaltılmaktadır!

#### 2. Çözüm / Refactoring Reçetesi
1. **At-least-once Durability (Reliable Queue / Staging Key):**
   * Veriler doğrudan `ltrim` ile silinmemeli; `RPOPLPUSH` veya `LMOVE` ile geçici bir işleme kuyruğuna (`_BUF_PROCESSING`) alınmalıdır.
   * Ya da ClickHouse `_client.insert()` **başarılı olduktan sonra** `LTRIM` edilmelidir.
   * `insert()` hata verirse veri Redis'te kalmalı veya başa geri atılmalıdır (`LPUSH`).
2. **Finansal Olayların İzolasyonu:** `direct_sale_events` gibi denetim ve sipariş olayları ClickHouse kesintisinde asla silinmeyecek bir Dead-Letter Queue (DLQ) mekanizmasına bağlanmalıdır.

---

### SRE-14 · 🟠 P1 (Yüksek) · Thompson Sampling Redis Read-Modify-Write Yarış Durumu (Lost Updates)

* **Etkilenen Dosya:** `backend/app/services/ml/thompson_sampling.py` (satır 54–114)

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcıların kategori tercihlerini dinamik öğrenen Thompson Sampling algoritması, her tıklama/görüntüleme olayında Beta dağılımı parametrelerini ($\alpha, \beta$) günceller:
```python
params = await _load_params(user_id)  # Redis HGETALL: "elektronik" -> "1.0,1.0"
alpha, beta = params.get(category, (_ALPHA_INIT, _BETA_INIT))
if delta > 0:
    alpha = min(alpha + delta, 500.0)
else:
    beta = min(beta - delta, 500.0)

params[category] = (alpha, beta)
await _save_params(user_id, params)   # Redis HSET: tüm hash'i tekrar yazar
```
**Yarış Durumu (Race Condition):**
Canlı yayında veya keşfet akışında kullanıcı 2 saniye içinde 3 farklı ilana tıklar/izler:
* İşlem 1 `_load_params` ile eski durumu okur.
* İşlem 2 aynı anda eski durumu okur.
* İşlem 1 `elektronik` kategorisini artırıp kaydeder.
* İşlem 2 `vasıta` kategorisini güncellerken elindeki eski `params` haritasını kaydeder; İşlem 1'in yaptığı `elektronik` güncellemesi **ezilir (Lost Update)**.
Ayrıca string olarak `"1.0000,1.0000"` birleştirip parse etmek CPU ve bellek israfıdır.

#### 2. Çözüm / Refactoring Reçetesi
Redis'in yerel atomik kayan noktalı artırma komutu olan **`HINCRBYFLOAT`** kullanılmalıdır:
* Hash yapısı: `HINCRBYFLOAT user:ts:{user_id} {category}:alpha {delta}`
* Bu işlem tek adımda, atomik, kilit gerektirmeyen ve O(1) hızında çalışır.
* Python tarafında hiçbir okuma-hesaplama-yazma (Read-Modify-Write) döngüsü kalmaz; eşzamanlı gelen 100 event bile sıfır kayıpla anında işlenir.

---

### SRE-15 · 🟠 P1 (Yüksek) · Kapatılmış SQLAlchemy Session'ı Üzerinde Çalıştırma ve İşlem Sızıntısı

* **Etkilenen Dosyalar:** 
  * `backend/app/use_cases/messages/commands/send_direct_message.py` (satır 145–155)
  * `backend/app/core/uow.py` (satır 104–110)

#### 1. Sorunun Tanımı ve Arıza Modu
`send_direct_message.py` dosyası incelendiğinde:
```python
async with self.uow:
    ...
    await self.uow.session.flush()
    msg_id = msg.id
    session = self.uow.session  # <-- Session referansı alınıyor

# commit sonrası — Context manager'dan ÇIKILDI (__aexit__ çalıştı)
if thread_status_changed:
    state = await RelationshipStateService.recompute_and_cache(user_a, user_b, session)
```
`uow.py` incelendiğinde, `_owns_session = True` olduğunda `__aexit__` bloğu şunu yapar:
```python
finally:
    if self._owns_session:
        await self.session.close() # <-- SESSION KAPATILDI!
```
1. `SqlAlchemyUnitOfWork()` bağımsız kullanıldığında (örneğin testlerde, CLI araçlarında veya worker görevlerinde), `recompute_and_cache` çağrısı **kapatılmış bir session** üzerinden SQL sorgusu atmaya çalışır. Bu durum `sqlalchemy.exc.IllegalStateChangeError` veya `InvalidRequestError: This session is closed` fırlatır.
2. Web router'ından enjekte edildiğinde (`_owns_session = False`), UoW'un transaction'ı kapandıktan sonra session üzerinde yeni bir sorgu atılır; bu da açıkta kalan, commit/rollback edilmeyen hayalet bir transaction başlatarak PostgreSQL bağlantı havuzunda connection kirliliğine yol açar.

#### 2. Çözüm / Refactoring Reçetesi
`RelationshipStateService.recompute_and_cache` çağrısı ya UoW context manager bloğunun **içine** (commit öncesi) alınmalı, ya da UoW dışında çalıştırılacaksa bağımsız ve temiz bir `async with AsyncSessionLocal() as session:` oturumuyla yürütülmelidir.

---

### SRE-16 · 🟠 P1 (Yüksek) · Churn Modelinde Atomik Olmayan Model (Pickle) Kaydı

* **Etkilenen Dosya:** `backend/app/services/ml/churn_ml_service.py` (satır 167–172)

#### 1. Sorunun Tanımı ve Arıza Modu
`train_churn_model` fonksiyonu eğitilen modeli şu şekilde diske kaydeder:
```python
model_path = _model_path()
model_path.parent.mkdir(parents=True, exist_ok=True)
with open(model_path, "wb") as f:
    pickle.dump({"scaler": scaler, "clf": clf, "val_acc": val_acc}, f)
```
`SRE-02` (FAISS) zaafında olduğu gibi, `open(model_path, "wb")` çağrıldığı anda diskteki eski dosya anında sıfırlanır (truncate edilir). 
Tam o saniyede ARQ worker veya churn tahmin görevi (`predict_churn_for_all_users`) modeli okumak için `_load_model()` çağırırsa:
Eksik yazılmış dosyayla karşılaşır ve `_pickle.UnpicklingError: pickle data was truncated` veya `EOFError` hatasıyla anında patlar.

#### 2. Çözüm / Refactoring Reçetesi
Model dosyası önce geçici bir dosyaya yazılmalı, ardından atomik rename yapılmalıdır:
```python
tmp_path = model_path.with_suffix(".tmp")
with open(tmp_path, "wb") as f:
    pickle.dump({"scaler": scaler, "clf": clf, "val_acc": val_acc}, f)
os.replace(tmp_path, model_path)  # Atomik POSIX işlemi
```

---

### SRE-17 · 🟡 P2 (Orta) · İlan Pasifleştirmede ORM Nesne Şişmesi & IN Parametre Patlaması

* **Etkilenen Dosya:** `backend/app/tasks/listing_tasks.py` (satır 43–73)

#### 1. Sorunun Tanımı ve Arıza Modu
`deactivate_expired_listings_task` görevinde:
```python
result = await db.execute(
    select(Listing).where(Listing.status == ListingStatus.ACTIVE, Listing.created_at < cutoff)
)
listings = result.scalars().all()  # <-- ON BİNLERCE FULL ORM MODELİ

listing_ids = [l.id for l in listings]

await db.execute(
    update(Listing).where(Listing.id.in_(listing_ids)).values(status='passive', deactivated_at=now)
)
```
1. **Bellek Şişmesi:** 30 günü dolmuş 20.000 ilan varsa, tüm bu satırlar (açıklamaları, resim URL'leri, metadata kolonlarıyla birlikte) Python heap belleğine ağır SQLAlchemy nesneleri olarak çekilir.
2. **SQL Parametre Limiti Darboğazı:** `Listing.id.in_(listing_ids)` ifadesi PostgreSQL'e 20.000 parametreli (`$1, $2, ..., $20000`) bir SQL sorgusu fırlatır. PostgreSQL query planner bu devasa parametre listesini parse ederken yüksek CPU harcar ve sorgu yavaşlar.
3. **Yarış Durumu:** SELECT ile UPDATE arasında geçen sürede kullanıcı ilanını silmiş veya güncellemiş olabilir; eski veri üzerinden pasife alma yapılır.

#### 2. Çözüm / Refactoring Reçetesi
İşlem tek bir küme tabanlı (set-based) SQL sorgusu ve `RETURNING` ifadesiyle sıfır bellek tüketimiyle halledilmelidir:
```python
stmt = (
    update(Listing)
    .where(
        Listing.status == ListingStatus.ACTIVE,
        Listing.expires_at.is_(None),
        Listing.created_at < cutoff,
    )
    .values(status=ListingStatus.PASSIVE, deactivated_at=now)
    .returning(Listing.id, Listing.user_id, Listing.title)
)
result = await db.execute(stmt)
updated_rows = result.all()  # Sadece bildirim için gereken küçük tuple'lar döner
```

---

### SRE-18 · 🟡 P2 (Orta) · Churn Airdrop Dağıtımında Toplu Kilit ve Tablo Blokajı

* **Etkilenen Dosya:** `backend/app/tasks/analytics_tasks.py` (satır 225–252)

#### 1. Sorunun Tanımı ve Arıza Modu
Churn riski altındaki kullanıcılara geri kazanım airdrop'u yükleyen `_apply_airdrops` fonksiyonunda:
```python
await db.execute(
    text("""
        UPDATE users
        SET teqlik_balance = teqlik_balance + :amount
        WHERE id = ANY(:uids) AND status = 'active'
    """),
    {"amount": _AIRDROP_AMOUNT, "uids": uid_list},
)
```
Eğer 5.000 veya 10.000 churn kullanıcısı belirlenmişse:
`UPDATE users ... WHERE id = ANY(:uids)` sorgusu tek bir SQL transaction'ı içinde `users` tablosundaki binlerce satırı aynı anda kilitler (exclusive row-level lock).
Bu güncelleme devam ederken, o kullanıcılardan herhangi biri uygulamayı açıp giriş yapmaya, ilan vermeye veya profilini güncellemeye çalışırsa kilit bekler (`LockWaitTimeout`).

#### 2. Çözüm / Refactoring Reçetesi
Kullanıcı ID listesi **200 veya 500'lük gruplar (chunks)** halinde işlenmeli ve her chunk arasında `await db.commit()` edilmelidir:
```python
CHUNK_SIZE = 500
for i in range(0, len(uid_list), CHUNK_SIZE):
    chunk = uid_list[i:i + CHUNK_SIZE]
    await db.execute(text("UPDATE users ... WHERE id = ANY(:uids)"), {"uids": chunk, ...})
    await db.execute(text("INSERT INTO teqlik_transactions ..."), ...)
    await db.commit()
```
Böylece veritabanında satır kilitleri milisaniyeler içinde serbest bırakılır ve canlı kullanıcı istekleri engellenmez.

---

### SRE-19 · 🟠 P1 (Yüksek) · Canlı Yayın Katılımcı Çıkarma / Moderasyonda Yanlış Edge Node Yönlendirmesi

* **Etkilenen Dosyalar:** 
  * `backend/app/services/moderation_service.py` (satır 76–98)
  * `backend/app/services/edge_orchestrator.py` (satır 72–116)
  * `backend/app/services/livekit_service.py` (satır 79–105)

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayında bir trolleri veya kural ihlali yapan kullanıcıyı odadan atmak için `remove_from_livekit` çağrılır:
```python
async def remove_from_livekit(room_name: str, user_id: int) -> None:
    from app.services.edge_orchestrator import orchestrator, ServiceType
    node = await orchestrator.allocate_node(ServiceType.MEDIA) # <-- HATA BURADA!
    api_url = node["livekit_url"]
    async with aiohttp.ClientSession() as session:
        svc = RoomService(session, api_url, settings.livekit_api_key, settings.livekit_api_secret)
        req = RoomParticipantIdentity()
        req.room = room_name
        req.identity = str(user_id)
        await svc.remove_participant(req)
```
**Neden Bozuk?**
`orchestrator.allocate_node(ServiceType.MEDIA)` fonksiyonu, o an cluster'da **en az yük altındaki rastgele bir medya sunucusunu** (node4, node5, node6) seçer!
Eğer yayın `node4` üzerinde açılmışsa ve moderatör tam bir kullanıcıyı atarken `node5` sunucusu daha az yüke sahipse:
İstek `node5` üzerindeki LiveKit API'sine gönderilir!
`node5` sunucusunda öyle bir oda veya katılımcı olmadığı için LiveKit `Participant not found` döner ve işlem sessizce başarısız olur (`logger.warning`).
Trol kullanıcı odadan atılamaz, yayında spam yapmaya ve tacize devam eder!

#### 2. Çözüm / Refactoring Reçetesi
1. `remove_from_livekit` fonksiyonuna yayının `livekit_url` bilgisi parametre olarak geçilmelidir (veya `orchestrator.resolve_stream_endpoint(stream)` kullanılmalıdır).
2. Tıpkı `livekit_service.py` içindeki `lk_broadcast_delete` mantığında olduğu gibi, eğer hedef sunucu tam bilinmiyorsa tüm sağlıklı medya node'larına silme isteği yayınlanmalıdır (`broadcast`).

---

### SRE-20 · 🟠 P1 (Yüksek) · Davet (Referral) Sisteminde Çift Harcama / Race Condition ile Sınırsız Teqlik Kazanımı

* **Etkilenen Dosyalar:** 
  * `backend/app/services/referral_service.py` (satır 65–146)
  * `backend/app/models/referral.py` (satır 8–17)

#### 1. Sorunun Tanımı ve Arıza Modu
`referral_service.py` içindeki davet kodu uygulama fonksiyonu incelendiğinde:
```python
already = await db.scalar(
    select(Referral).where(Referral.referred_id == current_user.id)
)
if already:
    raise BadRequestException(code="REFERRAL_ALREADY_USED")

# ... kod devam eder ...
referral = Referral(referrer_id=referrer.id, referred_id=current_user.id, status="completed")
db.add(referral)

# Referrer +50 teqlik, Referred +50 teqlik bakiyesi artırılır
await db.execute(sql_text("UPDATE users SET teqlik_balance = teqlik_balance + :amt WHERE id = :uid"), ...)
await db.commit()
```
Ve `models/referral.py` modelinde:
```python
referred_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
```
**İstismar ve Açık (Exploit Vector):**
1. `referrals` tablosundaki `referred_id` sütununda **`unique=True` KISITI YOKTUR**.
2. Fonksiyonda hiçbir satır kilidi (`with_for_update`) veya atomik kontrol bulunmamaktadır.
3. Kötü niyetli bir kullanıcı veya bot, aynı anda 10 adet paralel HTTP isteği atarak `apply_referral` endpoint'ini tetiklerse:
   * 10 isteğin hepsi de `already = None` sonucunu alır.
   * 10 istek de veritabanına `Referral` kaydı ekler.
   * Davet eden ve davet edilen kullanıcının bakiyesi her istek için 50'şer teqlik (toplamda 500 teqlik) artırılır!
   * Bu bir **Sonsuz Para / Çift Harcama (Double-Spend)** açığıdır.

#### 2. Çözüm / Refactoring Reçetesi
1. **Veritabanı Seviyesinde Unique Constraint:** `models/referral.py` ve Alembic migration'ında `referred_id` sütununa `unique=True` (`UNIQUE CONSTRAINT`) eklenmelidir.
2. **Pessimistic Locking / Atomic Insert:** `apply_referral` fonksiyonunun başında `current_user` kaydı `SELECT ... FOR UPDATE` ile kilitlenmeli veya `Referral` ekleme işlemi `ON CONFLICT DO NOTHING` ile yürütülmeli; ekleme başarısız olursa bakiye artırımı yapılmamalıdır.

---

### SRE-21 · 🔴 P0 (Kritik) · Ters Proxy (Nginx) Arkasında İstemci IP Kaybı ve Küresel Rate Limit / Sahte Shill Kilidi

* **Etkilenen Dosyalar:** 
  * `deploy/scale/V2.1/node1/systemd/teqlif.service` (satır 15–19)
  * `backend/app/core/rate_limit.py` (satır 30–44)
  * `backend/app/routers/auction.py` (satır 69, 112)
  * `backend/app/services/fraud_detection_service.py` (satır 97–110)

#### 1. Sorunun Tanımı ve Arıza Modu
`node1` üzerinde Nginx genel internetten gelen HTTPS isteklerini sonlandırıp yerel Uvicorn soketine yönlendirir (`http://127.0.0.1:8000`).
Ancak `teqlif.service` dosyası Uvicorn'u şu parametrelerle çalıştırmaktadır:
```ini
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn main:app \
    --host 127.0.0.1 \
    --port 8000 \
    --workers 8 \
    --log-level warning
```
**Eksik Olan:** `--proxy-headers` ve `--forwarded-allow-ips="*"` bayrakları **kullanılmamıştır**.
Bunun sonucunda Uvicorn Nginx'in gönderdiği `X-Forwarded-For` ve `X-Real-IP` başlıklarını dikkate almaz. Tüm API istekleri için `request.client.host` istisnasız **`127.0.0.1`** olur!

**Yıkıcı Sonuçları:**
1. **Küresel Giriş Blokajı (Rate Limit Collapse):** `POST /auth/login` (5/dakika) gibi kimlik doğrulaması olmayan tüm endpoint'lerde `get_remote_address(request)` çağrısı herkes için `127.0.0.1` döner. Tüm Türkiye'den gelen kullanıcılar aynı 5 istek/dakika limit havuzunu paylaşır. Aynı dakikada 5 kişi giriş yaparsa, 6. kişi `429 Too Many Requests` alır!
2. **Masum Teklif Sahiplerinin Otomatik Engellenmesi (False Shill Bidding):**
   * Açık artırmada yayıncı `host_ip = mask_ip(request.client.host)` ile kaydedilir (`127.0.0.0`).
   * Teklif veren kullanıcı `bidder_ip = mask_ip(request.client.host)` ile kaydedilir (`127.0.0.0`).
   * `FraudDetectionService` içinde `bidder_ip == host_ip` kontrolü **dünyadaki tüm kullanıcılar için TRUE çıkar!**
   * Telefonu henüz onaylamamış veya hesabı 7 günden yeni olan masum kullanıcılar anında 75-95 shill puanı alarak **`MUTE (BID_BLOCKED_SUSPICIOUS)`** ile engellenir ve teklif veremez!

#### 2. Çözüm / Refactoring Reçetesi
1. `teqlif.service` içindeki Uvicorn komutuna proxy bayrakları eklenmelidir:
   ```ini
   ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn main:app \
       --host 127.0.0.1 \
       --port 8000 \
       --workers 8 \
       --proxy-headers \
       --forwarded-allow-ips="127.0.0.1" \
       --log-level warning
   ```
2. `rate_limit.py` ve `auction.py` içinde istemci IP'si alınırken `request.headers.get("x-forwarded-for")` kontrolü önceliklendirilmeli veya güvenilir bir reverse proxy middleware'i doğrulanmalıdır.

---

### SRE-22 · 🟠 P1 (Yüksek) · Hikaye Yüklemede Senkron FFmpeg Video Sıkıştırması ve API Worker Blokajı

* **Etkilenen Dosya:** `backend/app/services/story_service.py` (satır 48–90, 324–330)

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı mobil uygulamadan video hikaye yüklediğinde (`POST /api/stories/upload`), `StoryService.upload_story` fonksiyonu çağrılır:
```python
if not is_image:
    compressed_path, _ = await _compress_video(tmp_path, tmp_dir, ext)
```
Ve `_compress_video`:
```python
cmd = ["ffmpeg", "-y", "-i", src, "-vf", "scale=-2:720", "-c:v", "libx264", "-crf", "28", ...]
proc = await asyncio.create_subprocess_exec(*cmd, ...)
await asyncio.wait_for(proc.communicate(), timeout=120)
```
**Arıza Modu:**
* Video transcode (libx264, 720p) işlemi **doğrudan HTTP istek iş parçacığı içinde (web worker)** senkron olarak bekletilir (`timeout=120` sn).
* 10 kullanıcı aynı anda hikaye yüklediğinde, `node1` (6 çekirdek) üzerinde 10 adet paralel FFmpeg süreci başlar.
* Sunucunun CPU kullanımı saniyeler içinde %100'e fırlar. Uvicorn worker'ları canlı API isteklerini, mesajları ve ping/pong'ları işleyemez hale gelir.
* Nginx 60 saniyelik `proxy_read_timeout` süresini aşar ve mobil istemcilere **`504 Gateway Timeout`** döner.

#### 2. Çözüm / Refactoring Reçetesi
Web worker'da asla ağır CPU video render işlemi yapılmamalıdır:
1. HTTP endpoint'i videoyu MinIO'ya ham (`raw/stories/{uuid}`) olarak kaydetmeli, DB'ye `status='processing'` olarak yazmalı ve kullanıcıya anında `202 Accepted` dönmelidir.
2. Sıkıştırma ve thumbnail çıkarma işi ARQ arka plan kuyruğuna (`queue_name="video"`, `max_jobs=2`) atılmalıdır.
3. Transcode tamamlandığında DB'deki hikaye `status='active'` yapılmalı ve kullanıcıya WebSocket/Push ile bildirimi iletilmelidir.

---

### SRE-23 · 🟠 P1 (Yüksek) · Doğrudan Satışta DB Hatalarında Redis Stok Sızıntısı (Missing Compensating Tx)

* **Etkilenen Dosya:** `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` (satır 385–455)

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayında doğrudan satış satın alma akışında:
```python
# 1. Redis'ten Lua ile stok düşülür:
remaining = await redis_mgr.decrement_stock(sale.stream_id, data.quantity)

# 2. DB'ye sipariş ve DM nesneleri eklenir:
order = DirectSaleOrder(...)
uow.session.add(order)
sale.remaining_stock = remaining
await uow.session.flush()

# 3. Redis hash güncellenir:
await redis_mgr.update_remaining_stock(stream_id, remaining)

# 4. DB Commit çağrılır:
await uow.session.commit() # <-- EĞER BURADA HATA OLURSA?
```
Eğer `uow.session.commit()` sırasında veritabanı kilit zaman aşımı (`LockNotAvailable`), disk hatası veya bağlantı kopması yaşanırsa:
* PostgreSQL transaction'ı rollback olur; sipariş veritabanına yazılmaz, alıcıya 500 hatası döner.
* Ancak Redis'teki stok **zaten düşürülmüştür** (`decrement_stock`) ve geri artırılmaz (Rollback/Compensating transaction yoktur).
* Örneğin tek kalan (stok=1) bir ürün satın alınırken DB commit patlarsa, ürün fiilen satılmadığı halde Redis'te stok 0 kalır ve yayın `sold_out` durumuna kilitlenir. Başka hiç kimse ürünü satın alamaz.

#### 2. Çözüm / Refactoring Reçetesi
`uow.session.commit()` işlemi bir `try...except` bloğu içine alınmalı; commit başarısız olduğunda Redis stoğu telafi edici işlemle (compensating transaction) geri artırılmalıdır:
```python
try:
    await uow.session.commit()
except Exception as exc:
    await redis_mgr.increment_stock(sale.stream_id, data.quantity)
    raise DatabaseException(code="PURCHASE_COMMIT_FAILED") from exc
```

---

### SRE-24 · 🟠 P1 (Yüksek) · Reklam Tıklamalarında Negatif Bütçe ve Karşılıksız Tıklama Sızıntısı

* **Etkilenen Dosya:** `backend/app/services/ad_service.py` (satır 36–43, 142–171)

#### 1. Sorunun Tanımı ve Arıza Modu
Reklam tıklamasında bütçe düşen Lua script'i incelendiğinde:
```lua
local current = tonumber(redis.call('GET', KEYS[1]))
if not current then return nil end
local bid = tonumber(ARGV[1])
local new_val = math.floor(current - bid)
redis.call('SET', KEYS[1], tostring(new_val))
return tostring(new_val)
```
**Mantık Hatası:**
Script `current <= 0` kontrolü yapmamaktadır!
Eğer kampanya bütçesi 5 teqlik kalmışsa ve aynı anda 10 kullanıcı reklama tıklarsa:
* İstek 1: bütçeyi 0 yapar.
* İstek 2: bütçeyi -5 yapar.
* İstek 3: bütçeyi -10 yapar.
* İstek 10: bütçeyi -45 yapar.
Python kodundaki `if new_budget <= 0` bloğu her istek için çalışmaya devam eder; arka planda `_sync_spent()` PostgreSQL'e harcanan bütçeyi sürekli ekler ve reklamverenin bakiyesinden fazla gösterim/tıklama bedava servis edilmiş olur.

#### 2. Çözüm / Refactoring Reçetesi
Lua scripti bütçe 0 veya altındaysa anında reddetmelidir:
```lua
local current = tonumber(redis.call('GET', KEYS[1]))
if not current or current <= 0 then return nil end
local bid = tonumber(ARGV[1])
if current < bid then return nil end
local new_val = math.floor(current - bid)
redis.call('SET', KEYS[1], tostring(new_val))
return tostring(new_val)
```
Böylece bütçe tükendiği anda sonraki tüm tıklamalar `nil` alır, hiçbir negatif bütçe oluşmaz ve veritabanına fazla harcama yazılmaz.

---

### SRE-25 · 🟠 P1 (Yüksek) · Stream Fan-Out Listener'da `os.getpid()` ile Restart Anında Mesaj Kaybı

* **Etkilenen Dosya:** `backend/app/core/stream_listener.py` (satır 124–136)

#### 1. Sorunun Tanımı ve Arıza Modu
Worker'ların Redis Stream'den mesaj okumasını sağlayan listener:
```python
worker_id = str(os.getpid())
pos_key = f"stream_pos:{stream_name}:{worker_id}"
saved = await r.get(pos_key)
last_id: str = saved if saved else "$"
```
* Her sistem güncellemesinde, deployment'ta veya worker çöküp yeniden başladığında işletim sistemi sürecin PID'sini değiştirir (örn: 10420 -> 18390).
* Yeni süreç ayağa kalktığında `stream_pos:{stream_name}:18390` anahtarı Redis'te bulunamaz (`saved is None`).
* Kod `last_id = "$"` değerini kullanır. Redis Stream terminolojisinde `$` sembolü: **"Sadece bu andan sonra gelen yeni mesajları oku, geçmişi yok say"** anlamına gelir.
* Sonuç: Uygulama yeniden başlarken geçen 5-10 saniye içinde gönderilen tüm canlı yayın chat mesajları, doğrudan mesajlar (DM), moderasyon susturma eventleri ve arama sinyalleri **kalıcı olarak kaybolur ve kullanıcılara asla iletilmez**. Ayrıca Redis'te binlerce eski PID'ye ait çöp `stream_pos` anahtarı birikir.

#### 2. Çözüm / Refactoring Reçetesi
1. `worker_id` olarak geçici işletim sistemi PID'si yerine; ya sabit worker indeksleri (örn: `teqlif_worker_0`, `teqlif_worker_1`) kullanılmalı ya da standart **Redis Consumer Groups (`XREADGROUP`)** mimarisine geçilmelidir.
2. Eğer fan-out modeli korunacaksa, yeni PID başladığında en son genel stream pozisyonundan geriye dönük son 1 dakikalık pencereyi replay edecek güvenli bir başlangıç ID'si belirlenmelidir.

---

### SRE-26 · 🟡 P2 (Orta) · Çoklu Node Depolamada (MinIO) Rastgele Node Seçimi (Get Object 404)

* **Etkilenen Dosyalar:** 
  * `backend/app/services/storage_service.py` (satır 147–169)
  * `backend/app/services/edge_orchestrator.py` (satır 145–163)

#### 1. Sorunun Tanımı ve Arıza Modu
`storage_service.py` içindeki nesne okuma fonksiyonu:
```python
async def get_object_bytes(key: str) -> bytes | None:
    node = await orchestrator.allocate_node(ServiceType.STORAGE)
    client = _get_client_for_internal_url(node["minio_url"])
    ...
```
Ve `_pick_storage`:
```python
best = min(candidates, key=lambda m: m.get("disk_percent", 100.0))
```
`allocate_node(ServiceType.STORAGE)` o an disk doluluğu en az olan node'u seçer.
Eğer cluster'da `node1` ve `node2` depolama node'u olarak tanımlanmışsa ve MinIO dağıtık modda (erasure-coded distributed cluster) değil de bağımsız MinIO instance'ları olarak çalışıyorsa:
Bir avatar veya görsel `node1`'e yüklendiğinde, daha sonra `get_object_bytes` çağrısı `node2`'yi seçerse, `node2` üzerinde o dosya olmadığı için `NoSuchKey` döner ve sistem dosyayı **yok (`None`)** zanneder.

#### 2. Çözüm / Refactoring Reçetesi
1. MinIO mimarisi küme genelinde ya tekil bir merkezi gateway (node1) üzerinden sunulmalı ya da `cluster.yaml`'daki gibi tek bir authoritative endpoint (`10.10.0.1:9000`) üzerinden yönetilmelidir.
2. Dosya anahtarları (key) hangi node'a yüklendiğini içermeli (`node_id/bucket/key`) ya da `delete_object` fonksiyonundaki gibi URL üzerinden domain çözümlemesi yapılmalıdır.

---

### SRE-27 · 🟡 P2 (Orta) · Keşfet Akışında Her İstekte Dinamik `SELECT DISTINCT category` Sorgusu

* **Etkilenen Dosya:** `backend/app/services/recommendation_service.py` (satır 315–322)

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı her ana sayfayı veya keşfet akışını yenilediğinde (`get_personalized_feed`):
```python
cat_result = await db.execute(
    text("""
        SELECT DISTINCT category FROM listings
        WHERE status = 'active' AND category IS NOT NULL
        LIMIT 50
    """)
)
all_categories = [row[0] for row in cat_result.fetchall()]
```
**Neden Verimsiz?**
* Aktif ilan sayısı 50.000 - 100.000 olduğunda, PostgreSQL'de `SELECT DISTINCT category` çalıştırmak tüm aktif ilan indeksini veya tablosunu tarar (Index / Sequential Scan).
* Bu sorgu her ana sayfa kaydırmasında çalışarak veritabanına gereksiz disk I/O ve 30-60 ms ek gecikme ekler.
* Oysa platformdaki kategori listesi günde bir kez bile değişmez ve `main.py` içinde `init_category_cache()` ile zaten Redis'e yüklenmektedir!

#### 2. Çözüm / Refactoring Reçetesi
Kategoriler doğrudan `app.utils.category_cache.get_categories()` üzerinden RAM/Redis'ten O(1) hızında okunmalıdır; PostgreSQL'e kesinlikle dinamik `DISTINCT` sorgusu atılmamalıdır.

---

### SRE-28 · 🟡 P2 (Orta) · Canlı Yayın Sohbet Dump'ında asyncpg Parametre Limiti (32767) Çökmesi

* **Etkilenen Dosya:** `backend/app/use_cases/streams/stream_finalizer.py` (satır 44–79)

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın sonlandığında Redis'teki chat mesajları veritabanına aktarılır:
```python
await db.execute(sa_delete(StreamChatMessage).where(StreamChatMessage.stream_id == stream_id))
await db.execute(pg_insert(StreamChatMessage).values(rows)) # <-- TEK SEFERDE INSERT
await db.commit()
```
`StreamChatMessage` tablosunda satır başına 9 adet parametre vardır (`stream_id, user_id, username, avatar_url, content, is_host, is_mod, is_hidden, created_at`).
Popüler bir yayında 4.000 chat mesajı birikmişse:
`4.000 × 9 = 36.000 parametre` üretilir.
PostgreSQL sürücüsü olan `asyncpg`, tek bir sorguda en fazla **32.767 parametreye** izin verir (`int16` protokol limiti).
3.640 mesajın üzerindeki tüm yayınlarda bu sorgu şu hatayla çöker:
`asyncpg.exceptions.TooManyArgumentsError: too many arguments in query, expected at most 32767`
**Zincirleme Etki:**
`dump_chat_to_db` çöktüğü için `dump_ok = False` olur; `finalize_stream` fonksiyonu Redis'teki chat anahtarını silmez (`if dump_ok: base_keys.append(...)`); binlerce mesajlık chat geçmişi Redis RAM'inde kalıcı çöp olarak kalır.

#### 2. Çözüm / Refactoring Reçetesi
Mesajlar **500'lük gruplar (chunks)** halinde veritabanına eklenmelidir:
```python
CHUNK_SIZE = 500
for i in range(0, len(rows), CHUNK_SIZE):
    await db.execute(pg_insert(StreamChatMessage).values(rows[i:i + CHUNK_SIZE]))
await db.commit()
```

---

### SRE-29 · 🟢 P3 (Düşük) · Canlı Ortamda O(N) `redis.keys()` Kullanımı ve Event-Loop Blokajı

* **Etkilenen Dosyalar:** 
  * `backend/app/use_cases/streams/stream_finalizer.py` (satır 143)
  * `backend/app/services/edge_orchestrator.py` (satır 34)

#### 1. Sorunun Tanımı ve Arıza Modu
`stream_finalizer.py`:
```python
keys = await redis.keys(f"cache:pro_insights:{stream.host_id}:*")
```
Ve `edge_orchestrator.py`:
```python
keys = await redis.keys("edge:metrics:*")
```
Redis tek iş parçacıklı (single-threaded) bir mimariye sahiptir. `KEYS` komutu Redis'teki tüm anahtar uzayını (yüz binlerce anahtar) baştan sona lineer olarak tarar (O(N) karmaşıklık).
Canlı bir sistemde `KEYS` komutu çalıştığı sırada Redis tüm diğer gelen API isteklerini, teklifleri ve WebSocket yayınlarını dondurur.

#### 2. Çözüm / Refactoring Reçetesi
1. `KEYS` yerine bloklamayan imleç tabanlı **`SCAN` (veya `redis.scan_iter`)** kullanılmalıdır.
2. Veya daha iyisi: İlgili anahtarlar bir Redis Set'inde (`edge:nodes:active` veya `user:{id}:insight_keys`) indekslenmeli; böylece arama yapmaya gerek kalmadan O(1) `SMEMBERS` ile çekilmelidir.

---

### SRE-30 · 🟡 P2 (Orta) · Hype Manager Süreç İçi (In-Memory) Durum ve 8 Worker Arasında Senkronizasyon Yokluğu

* **Etkilenen Dosya:** `backend/app/core/hype_manager.py` (satır 44–50, 89–92)

#### 1. Sorunun Tanımı ve Arıza Modu
`hype_manager` canlı yayındaki anlık heyecan (hype) skorunu yönetir:
```python
class HypeManager:
    def __init__(self) -> None:
        self._scores: dict[int, float] = {}
        self._user_ts: dict[tuple[int, int], float] = {}
```
Bu skorlar Python sürecinin yerel belleğinde (`self._scores` sözlüğünde) tutulmaktadır.
Ancak üretimde Uvicorn **8 worker** olarak çalışmaktadır.
Kullanıcı A'nın sohbet mesajı Worker 1'e düştüğünde Worker 1'deki skor 40 olur.
Kullanıcı B'nin mesajı Worker 2'ye düştüğünde Worker 2'deki skor 15'tir.
İzleyiciler WebSocket üzerinden farklı worker'lara bağlı olduğundan veya HTTP sorgusu attığında her worker kendi yerel belleğindeki farklı skoru yayınlar. Skor izleyici ekranında sürekli tutarsız olarak zıplar (jitter).

#### 2. Çözüm / Refactoring Reçetesi
Hype skoru ve kullanıcı cooldown zamanları süreç belleğinde değil, Redis üzerinde `live:hype:{stream_id}` anahtarında atomik olarak tutulmalı; sönümleme döngüsü (decay) ise 8 worker'da ayrı ayrı değil, tek bir ARQ periyodik görevi üzerinden yürütülmelidir.

---

### SRE-31 · 🔴 P0 (Kritik) · In-App Purchase (IAP) Satın Alma Doğrulamasında Eksik `commit()` Nedeniyle Gerçek Parayla Alınan Bakiyenin Rollback Olması

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/wallet/commands/verify_purchase_command.py` (Satır 122–174 ve 176–244)
  * `backend/app/routers/wallet.py` (Satır 34–48)
* **İlgili Fonksiyonlar:** `VerifyPurchaseCommand._handle_consumable`, `VerifyPurchaseCommand._handle_subscription`, `wallet.py:verify_purchase`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı iOS veya Android üzerinden gerçek para ödeyerek Teqlik satın aldığında veya PRO abonelik başlattığında, mobil istemci mağaza dekontunu `POST /api/wallet/purchase/verify` endpoint'ine iletir.
Endpoint doğrudan `VerifyPurchaseCommand(db).execute(...)` çağrısı yapar.

`VerifyPurchaseCommand` sınıfı mağaza API'si ile faturayı doğrular, ardından veritabanında şu işlemleri yürütür:
```python
# _handle_consumable (satır 127-168)
await self._session.execute(text("UPDATE users SET teqlik_balance = teqlik_balance + :amt WHERE id = :uid"), ...)
await self._session.execute(text("INSERT INTO teqlik_transactions ..."), ...)
await self._session.execute(text("INSERT INTO wallet_ledger ..."), ...)
return {"status": "ok", "product_type": "consumable", "teqlik_added": teqlik_amount}
```
**Kritik Arıza:**
`VerifyPurchaseCommand` içerisinde ne `_handle_consumable` ne de `_handle_subscription` metodunun sonunda **`await self._session.commit()` ÇAĞRILMAMAKTADIR**.
Dahası, `backend/app/routers/wallet.py:verify_purchase` içerisinde de bir `commit()` bulunmamaktadır.
FastAPI `get_db` bağımlılığı incelendiğinde (`backend/app/database.py:49-55`):
```python
async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
```
`get_db` generator'ı oturumu kapatırken (`session.close()`), commit edilmemiş tüm açık hareketleri **PostgreSQL seviyesinde otomatik olarak `ROLLBACK` eder!**

**Mali ve Operasyonel Yıkım:**
1. Kullanıcının kredi kartından Apple/Google 100 TL veya 1.000 TL çeker.
2. API istemciye HTTP 200 OK ve `{"status": "ok", "teqlik_added": 500}` döner.
3. Ancak HTTP isteği sonlandığı anda Postgres transaction'ı ROLLBACK olur!
4. Kullanıcının `teqlik_balance` bakiyesi artmaz, transaction tablosuna hiçbir şey yazılmaz. Kullanıcı parasını kaybeder, bakiyesi 0 kalır. Müşteri şikayetleri ve Apple/Google ters ibraz (chargeback) cezaları patlar.

#### 2. Çözüm / Refactoring Reçetesi
1. `backend/app/use_cases/wallet/commands/verify_purchase_command.py` dosyasında:
   * Hem `_handle_consumable` (satır 170 öncesi) hem de `_handle_subscription` (satır 240 öncesi) bloklarının sonuna açıkça `await self._session.commit()` eklenmelidir.
2. Hata durumunda tutarlılık için `execute()` metodunda `try...except` bloğu oluşturularak hata anında `await self._session.rollback()` çağrılmalı ve hata dışarı fırlatılmalıdır.
3. Alternatif ve daha güvenli mimari: `verify_purchase` endpoint'i `SqlAlchemyUnitOfWork` pattern'ine bağlanmalı ve transaction yaşam döngüsü context manager garantisine alınmalıdır.

> ✅ **Çözüldü** — commit `a8448139`, 2026-10-30. `wallet.py:verify_purchase`'a `await db.commit()` eklendi.

---

### SRE-32 · 🔴 P0 (Kritik) · Apple Store İadelerinde (Refund) Eksik `commit()` Nedeniyle İade Bakiyesinin Düşürülememesi ve Sonsuz Para Açığı

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/wallet/commands/handle_store_refund_command.py` (Satır 33–149)
  * `backend/app/tasks/wallet_tasks.py` (Satır 227–258)
* **İlgili Fonksiyonlar:** `HandleStoreRefundCommand.execute`, `wallet_tasks.py:process_store_notification_task`

#### 1. Sorunun Tanımı ve Arıza Modu
Apple App Store Server Notifications V2 üzerinden bir kullanıcı iade (`REFUND`) aldığında, webhook ARQ worker'a `process_store_notification_task` işi olarak iletilir.
Task içerisinde yeni bir veritabanı oturumu açılır:
```python
async with AsyncSessionLocal() as session:
    if platform == "apple":
        ...
        if notif_type == "REFUND":
            await HandleStoreRefundCommand(session).execute(
                platform=platform, signed_payload=signed_payload
            )
```
`HandleStoreRefundCommand.execute` metodu incelendiğinde (`handle_store_refund_command.py:68-142`):
1. `UPDATE users SET teqlik_balance = teqlik_balance - :amt ...` çalıştırılır.
2. `UPDATE users SET pending_refund = true ...` çalıştırılır.
3. `INSERT INTO wallet_ledger ...` (2 satır) çalıştırılır.
4. `INSERT INTO refund_log ...` çalıştırılır.

**Kritik Arıza:**
`HandleStoreRefundCommand` sınıfının hiçbir satırında **`await self._session.commit()` ÇAĞRILMAMAKTADIR**.
Çağıran `process_store_notification_task` fonksiyonunda da `await session.commit()` yoktur!
`async with AsyncSessionLocal() as session:` bloğundan çıkıldığı anda oturum commit edilmeden kapanır ve **yapılan tüm bakiye düşürme, pending_refund ve ledger log işlemleri ROLLBACK olur!**

**İstismar Senaryosu (Infinite Money Glitch):**
1. Kötü niyetli kullanıcı Apple üzerinden 10.000 Teqlik satın alır.
2. Ardından Apple Destek üzerinden sipariş için "Yanlışlıkla satın aldım" diyerek iade (refund) ister.
3. Apple parayı kullanıcının kartına iade eder ve Teqlif webhook'una `REFUND` bildirimini atar.
4. Teqlif worker'ı bildirimi başarıyla işlediğini sanır (log basar), ancak transaction rollback olduğu için kullanıcının 10.000 Teqlik bakiyesi DÜŞÜRÜLMEZ.
5. Kullanıcı parasını geri almış, fakat sistemde 10.000 Teqlik bedava bakiye sahibi olmuştur. Bu işlem defalarca tekrarlanarak sistemdeki tüm pazar yeri manipüle edilebilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `handle_store_refund_command.py` dosyasında `execute` metodunun en sonuna (satır 143 öncesine):
   ```python
   await self._session.commit()
   ```
   eklenmelidir.
2. `wallet_tasks.py:process_store_notification_task` içinde de oturum bloğu sonunda emniyet olarak:
   ```python
   await session.commit()
   ```
   çağrılmalı, olası bir use-case içi commit unutulmasına karşı çift dikiş emniyet sağlanmalıdır.

> ✅ **Çözüldü** — commit `a8448139`, 2026-10-30. `wallet_tasks.py:process_store_notification_task`'a `await session.commit()` eklendi.

---

### SRE-33 · 🟠 P1 (Yüksek) · Google Play RTDN Webhook Bildirimlerinin Worker Tarafından Desteklenmeyip Yutulması

* **Etkilenen Dosya:** `backend/app/tasks/wallet_tasks.py` (Satır 236–257)
* **İlgili Fonksiyon:** `process_store_notification_task`

#### 1. Sorunun Tanımı ve Arıza Modu
`wallet_tasks.py` içindeki mağaza bildirim yönlendiricisi incelendiğinde:
```python
async with AsyncSessionLocal() as session:
    if platform == "apple":
        # Apple JWS çözme ve işleme...
    else:
        logger.warning(
            "[StoreNotif] Bilinmeyen platform, atlandı | platform=%s", platform
        )
        return
```
Android platformunda Google Play Store üzerinden yapılan abonelik ve satın alımlara ait Real-Time Developer Notifications (RTDN - Pub/Sub) webhook'ları geldiğinde, `platform == "google"` durumu doğrudan `else` bloğuna düşmekte ve **tamamen yutulmaktadır (dropped)!**

**Etkileri:**
1. Android kullanıcıları aboneliklerini Google Play Store üzerinden iptal ettiğinde (`SUBSCRIPTION_CANCELED`), Teqlif sistemi bundan haberdar olamaz ve kullanıcıya süresiz bedava PRO hakları tanımlı kalır.
2. Google Play abonelik yenilemeleri (`SUBSCRIPTION_RENEWED`) işlenemez; kullanıcının süresi dolunca hesabı haksız yere pasife düşer.
3. Android kullanıcılarının Google Play üzerinden aldıkları iadeler (`SUBSCRIPTION_REVOKED` / voided purchases) sisteme yansımaz; bakiye düşürülemez.

#### 2. Çözüm / Refactoring Reçetesi
1. `wallet_tasks.py:process_store_notification_task` içine `elif platform == "google":` dalı eklenmelidir:
   ```python
   elif platform == "google":
       from app.services.store.notification_factory import StoreNotificationHandlerFactory
       handler = StoreNotificationHandlerFactory.get("google", session)
       await handler.handle(signed_payload)
       await session.commit()
   ```
2. Google Play RTDN Base64 formatındaki payload'ı doğrulayan ve `subscriptionNotification` / `oneTimeProductNotification` tiplerini ayrıştıran `GoogleNotificationHandler` pipeline'ı aktif edilmelidir.

---

### SRE-34 · 🟠 P1 (Yüksek) · `track_event` Endpoint'inde Kapatılmış DB Oturumunun (Closed Session) BackgroundTasks'e Verilmesi

* **Etkilenen Dosya:** `backend/app/routers/analytics.py` (Satır 68–85 ve 86–121)
* **İlgili Fonksiyonlar:** `track_event`, `_save_event_async`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/analytics/track` endpoint'i istemcilerden gelen gezinme, tıklama ve izleme verilerini alır. Endpoint tanımı şöyledir:
```python
@router.post("/track", status_code=202)
async def track_event(
    data: AnalyticsEventCreate,
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
):
    ...
    # Save to database asynchronously in the background
    background_tasks.add_task(_save_event_async, data, user_id, ip_address, db)
    return {"status": "queued"}
```
Arka planda çalışan `_save_event_async` fonksiyonu:
```python
async def _save_event_async(data: AnalyticsEventCreate, user_id: int | None, ip_address: str | None, db: AsyncSession):
    try:
        event = AnalyticsEvent(...)
        db.add(event)
        await db.commit()
    except Exception as exc:
        logger.error("[ANALYTICS] Error saving event: %s", exc)
```
**Kritik Yaşam Döngüsü Hatası:**
FastAPI mimarisinde `db: AsyncSession = Depends(get_db)` bir generator dependency'dir.
`track_event` fonksiyonu `return {"status": "queued"}` döndüğü anda HTTP yanıtı istemciye gönderilir ve FastAPI dependency'nin `finally: await session.close()` bloğunu çalıştırarak **oturum nesnesini kapatır**.
FastAPI'nin `BackgroundTasks` mekanizması ise HTTP yanıtı döndükten SONRA çalışır.
`_save_event_async` tetiklendiğinde parametre olarak aldığı `db` oturumu **zaten kapatılmıştır (closed)**.
`db.add(event)` veya `await db.commit()` satırında SQLAlchemy anında şu istisnayı fırlatır:
`sqlalchemy.exc.IllegalStateChangeError: Cannot operate on a closed session.`
Satır 84'teki `except` bloğu bu hatayı loglar ve işlemi sonlandırır.

**Sonuç:**
Sistemde web veya mobil kullanıcıların gezinme ve tıklama davranışlarını kaydeden analitik altyapısı **%100 oranında veri kaybı yaşamakta**, hiçbir analitik event veritabanına yazılamamaktadır.

#### 2. Çözüm / Refactoring Reçetesi
1. `_save_event_async` fonksiyonuna `db: AsyncSession` parametresi geçirilmemelidir.
2. Fonksiyon kendi bağımsız oturumunu `AsyncSessionLocal()` ile açmalıdır:
   ```python
   async def _save_event_async(data: AnalyticsEventCreate, user_id: int | None, ip_address: str | None):
       from app.database import AsyncSessionLocal
       try:
           async with AsyncSessionLocal() as session:
               event = AnalyticsEvent(...)
               session.add(event)
               await session.commit()
       except Exception as exc:
           logger.error("[ANALYTICS] Error saving event: %s", exc)
   ```
3. `track_event` içindeki `background_tasks.add_task(_save_event_async, data, user_id, ip_address)` çağrısından `db` argümanı kaldırılmalıdır.

---

### SRE-35 · 🟠 P1 (Yüksek) · Korunmasız ve Tahmin Edilebilir `POST /calls/{id}/ack` ile Çağrı İşaretleşmesinin Bozulması

* **Etkilenen Dosyalar:**
  * `backend/app/routers/calls.py` (Satır 718–730)
  * `backend/app/core/ws_manager.py` (Satır 319–342)
* **İlgili Fonksiyonlar:** `call_incoming_ack_http`, `ws_manager.store_call_ack`, `ws_manager.wait_for_call_ack`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/calls/{call_id}/ack` endpoint'i unauthenticated (kimlik doğrulaması olmadan) çalışacak şekilde tasarlanmıştır. Gerekçe olarak yorum satırında Android background isolate'in auth token taşımadığı, sequential `call_id`'nin tahmin edilemeyeceği iddia edilmiştir:
```python
@router.post("/{call_id}/ack")
async def call_incoming_ack_http(call_id: int):
    await ws_manager.store_call_ack(call_id)
    return {"ok": True}
```
Ancak `call_id`, PostgreSQL `calls` tablosundaki standart bir **ardışık artan tamsayıdır (auto-increment integer: 1041, 1042, 1043...)**.

Sistemdeki arama başlatma akışı incelendiğinde (`initiate_call`):
```python
ack_received = await ws_manager.wait_for_call_ack(call_id, timeout=0.5)
if ack_received:
    logger.info("ACK alındı — FCM/APNs push bildirimi iptal edildi")
else:
    logger.info("ACK zaman aşımı — callee'ye FCM/APNs push gönderiliyor")
    await send_push(...)
```
**Hizmet Engelleme (DoS) Açığı:**
Kötü niyetli bir saldırgan, arka arkaya basit bir HTTP döngüsü ile `POST /api/calls/{id}/ack` isteği atarak güncel çağrı ID'lerini ACK'leyebilir.
Bir arama başladığında:
1. Saldırgan sahte ACK üretir (`call_ack:{call_id}` Redis'e yazılır).
2. `wait_for_call_ack` fonksiyonu `True` döner.
3. Sunucu, aranan kullanıcının çağrıyı WebSocket üzerinden aldığını varsayar ve **FCM / APNs PUSH BİLDİRİMİNİ GÖNDERMEZ (İPTAL EDER)**.
4. Telefonu kilitli veya arka planda olan aranan kullanıcının cihazı ASLA ÇALMAZ.
5. Arayan kullanıcı ise çaldığını sanır, 30 saniye sonra arama "Cevap Verilmedi" olarak düşer. Sistem genelindeki tüm sesli/görüntülü aramalar tamamen felç edilebilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `Call` modeline veya Redis oturumuna tahmin edilemez bir `ack_token (UUIDv4)` eklenmelidir.
2. Arama başlatıldığında üretilen `ack_token`, yalnızca aranan cihazın WebSocket ve Push payload'ına gömülmelidir.
3. `POST /api/calls/{call_id}/ack` endpoint'i body'de `{ "ack_token": "..." }` beklemeli; token eşleşmezse ACK kabul edilmemelidir.
4. Böylece yalnızca çağrının gerçek muhatabı olan cihaz ACK gönderebilir.

---

### SRE-36 · 🟠 P1 (Yüksek) · Canlı Yayın Düğümlerinde (node3/node4) `livekit.yaml` İçinde Olmayan Yerel Redis'e (`127.0.0.1:6379`) Bağlanma Girişimi

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/node3/resources/livekit/livekit.yaml` (Satır 19–24)
  * `deploy/scale/V2.1/node4/resources/livekit/livekit.yaml` (Satır 19–24)
  * `deploy/scale/V2.1/scripts/bootstrap_node3.sh` ve `bootstrap_node4.sh`
* **İlgili Servis:** `teqlif-livekit.service`

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın sunucuları olan `node3` (51.75.74.124 / 10.10.0.3) ve `node4` (135.125.175.223 / 10.10.0.4) üzerindeki LiveKit konfigürasyonu incelendiğinde:
```yaml
# HAProxy local proxy üzerinden Redis HA
redis:
  address: 127.0.0.1:6379
  db: 1
  password: <core_redis_pass>
```
Konfigürasyonda HAProxy local proxy üzerinden Redis'e gidileceği belirtilmiştir.
Ancak `node3/systemd`, `node4/systemd` ve `bootstrap_node3.sh` dosyaları incelendiğinde:
1. `node3` ve `node4` üzerinde **hiçbir HAProxy servisi kurulu veya yapılandırılmış DEĞİLDİR**.
2. Bu node'larda yerel bir Redis servisi de çalışmamaktadır (Redis yalnızca `node1` 10.10.0.1 ve `node2` 10.10.0.2 üzerindedir).
3. `systemctl start teqlif-livekit` çalıştırıldığında LiveKit, `127.0.0.1:6379` adresine bağlanmayı dener ve anında:
   `dial tcp 127.0.0.1:6379: connect: connection refused`
   hatasıyla çöker (CrashLoopBackOff).

**Sonuç:**
Canlı yayın cluster'ına eklenen hiçbir streaming node'u ayağa kalkamaz; sistemde oda oluşturulamaz ve kullanıcılar canlı yayına bağlanamaz.

#### 2. Çözüm / Refactoring Reçetesi
İki çözüm yolu mevcuttur:
* **Seçenek A (Doğrudan WireGuard Mesh Bağlantısı - Tavsiye Edilen):**
  `livekit.yaml` içindeki Redis adresi doğrudan WireGuard IP'sine yönlendirilir:
  ```yaml
  redis:
    address: 10.10.0.1:6379
    db: 1
    password: <core_redis_pass>
  ```
* **Seçenek B (HAProxy ile Yüksek Erişilebilirlik):**
  `bootstrap_node3.sh` ve `bootstrap_node4.sh` içine `haproxy` kurulumu ve `127.0.0.1:6379 -> 10.10.0.1:6379 (primary) / 10.10.0.2:6379 (backup)` frontend/backend yapılandırması eklenmelidir.

---

### SRE-37 · 🟠 P1 (Yüksek) · `send-blast` Endpoint'inde Senkron Döngüde 10.000'e Varan FCM Push Gönderimi ve Gateway Timeout

* **Etkilenen Dosya:** `backend/app/routers/leads.py` (Satır 370–376)
* **İlgili Fonksiyon:** `send_blast`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/leads/send-blast` endpoint'i satıcıların hedef kitleye toplu push bildirimi göndermesini sağlar. Hedef kitle büyüklüğü 10.000 kullanıcıya kadar çıkabilmektedir (`actual_count_max = min(desired, cap)`).
Bildirim gönderim bloğu doğrudan FastAPI HTTP istek işleyicisi (endpoint thread'i) içinde şu şekilde yazılmıştır:
```python
chunk_size = 50
sent = 0
for i in range(0, len(fcm_tokens), chunk_size):
    chunk = fcm_tokens[i : i + chunk_size]
    await asyncio.gather(*[_send_one(t, campaign.id) for t in chunk])
    sent += len(chunk)
```
**Performans ve Kararlılık Arızası:**
1. 5.000 alıcılı tipik bir kampanyada, kod 50'şerli gruplar halinde **100 ardışık HTTP turu (roundtrip)** yapar.
2. Her bir `_send_one` çağrısı Google Firebase FCM REST API'sine tekil HTTP isteği atar.
3. 100 ardışık grup * ~250ms ağ gecikmesi = **25 ila 35 saniye boyunca tek bir HTTP isteğinin Uvicorn worker'ını rehin alması** demektir!
4. Nginx ters proxy'si 30 saniye sonra `504 Gateway Time-out` hatası ile bağlantıyı koparır.
5. Satıcı ekranda hata gördüğü için "Gönderilmedi" zannedip butona tekrar tıklar.
6. Mükerrer kampanya açılır, satıcının Teqlik kredisi iki kat kesilir ve kullanıcılara çift bildirim bombardımanı yapılır.

#### 2. Çözüm / Refactoring Reçetesi
1. **İşi Kuyruğa Devretme:** `send_blast` HTTP endpoint'i sadece veritabanına kampanya kaydını açmalı, ücreti tahsil etmeli ve işi anında ARQ arka plan kuyruğuna devrederek HTTP 202 Accepted dönmelidir:
   ```python
   await arq_redis.enqueue_job("send_lead_blast_task", campaign_id=campaign.id)
   return {"campaign_id": campaign.id, "status": "processing"}
   ```
2. **Toplu FCM API Kullanımı:** ARQ worker içerisinde tek tek `send_push` çağırmak yerine, Firebase Admin SDK'nın `messaging.send_each_for_multicast` fonksiyonu kullanılmalıdır. Bu API tek bir HTTP isteğinde 500 adede kadar token kabul eder. 5.000 kullanıcı 100 istek yerine sadece 10 istekte ~1 saniyede tamamlanır.

---

### SRE-38 · 🟡 P2 (Orta) · `refresh_token` İçinde Grace Period Olmayan `redis.getdel` Nedeniyle Mobil Kullanıcıların Rastgele Oturumdan Atılması

* **Etkilenen Dosya:** `backend/app/routers/auth.py` (Satır 1005–1020)
* **İlgili Fonksiyon:** `refresh_token`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/auth/refresh` endpoint'inde token yenileme mantığı şu şekildedir:
```python
user_id_str = await redis.getdel(f"refresh:{token}")
if not user_id_str:
    raise UnauthorizedException("Geçersiz veya süresi dolmuş refresh token")
new_refresh = create_refresh_token()
await redis.setex(f"refresh:{new_refresh}", REFRESH_TOKEN_TTL, str(user.id))
```
Kullanıcının access token'ı dolduğunda mobil uygulama (iOS/Android) veya React web istemcisi genellikle aynı anda birden fazla HTTP isteğinde bulunur (örneğin uygulama ön plana geldiğinde eşzamanlı olarak: profil yükleme, okunmamış bildirim sayısı, keşfet akışı).
Bu 3 istek de aynı anda `401 Unauthorized` alır.
Mobil uygulamanın HTTP interceptor katmanı (ör. Dio veya Axios interceptor) `/api/auth/refresh` endpoint'ine eşzamanlı olarak 2 veya 3 refresh isteği yollar.

**Yarış Durumu (Race Condition):**
1. 1. İstek `redis.getdel` çalıştırır; anahtar başarıyla okunur ve Redis'ten silinir. Yeni refresh token üretilir.
2. Milisaniyeler sonra gelen 2. İstek aynı eski `token` ile `redis.getdel` yapar. Anahtar zaten silindiği için `None` döner!
3. Sunucu 2. İsteğe `401 Unauthorized ("Geçersiz veya süresi dolmuş refresh token")` hatası döner.
4. Mobil istemci refresh endpoint'inden 401 aldığı anda protokol gereği yerel oturum verilerini siler ve **kullanıcıyı aniden zorla Login (Giriş) ekranına fırlatır!**

Kullanıcılar uygulamayı kullanırken hiçbir sebep yokken rastgele aralıklarla oturumlarının kapandığını ve şifre girmek zorunda kaldıklarını bildirir.

#### 2. Çözüm / Refactoring Reçetesi
1. **Grace Period (Geçiş Tolerans Süresi):** `redis.getdel` ile anında silmek yerine, tüketilen refresh token 15–30 saniyelik bir süre boyunca üretilen yeni token ikilisine map edilerek Redis'te tutulmalıdır:
   `redis.setex(f"refresh:used:{token}", 30, json.dumps({"access": new_access, "refresh": new_refresh}))`
2. İkinci eşzamanlı istek geldiğinde, `refresh:used:{token}` anahtarı kontrol edilir; varsa hata vermek yerine az önce üretilmiş olan geçerli token ikilisi döndürülür.
3. 30 saniye sonra anahtar Redis tarafından kendiliğinden temizlenir. Böylece hem token replay saldırıları engellenir hem de istemci taraflı yarış durumlarında kullanıcı oturumu korunur.

---

### SRE-39 · 🔴 P0 (Kritik) · `teqlif.conf` İçindeki `client_max_body_size 5m` Nedeniyle Story, Video ve Medya Yüklemelerinin Nginx Tarafından HTTP 413 ile Reddedilmesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/node1/resources/nginx/conf.d/teqlif.conf` (Satır 23 ve 99)
* **İlgili Bloklar:** `server { server_name teqlif.com www.teqlif.com; }` ve `server { server_name api.teqlif.com; }`

#### 1. Sorunun Tanımı ve Arıza Modu
Nginx konfigürasyonunda `teqlif.conf` dosyası incelendiğinde, her iki HTTPS sunucu bloğunda da istemci gövde boyutu sınırı şu şekilde tanımlanmıştır:
```nginx
# Satır 23 (teqlif.com) ve Satır 99 (api.teqlif.com)
client_max_body_size 5m;
```
Buna karşılık doğrudan FastAPI web sunucusuna dosya yükleyen uç noktalar incelendiğinde:
1. `backend/app/routers/stories.py:27, 58`: Story video yüklemeleri `POST /api/stories/` üzerinden kabul edilir ve Python kodunda azami boyut `_MAX_VIDEO_SIZE = 50 * 1024 * 1024` (50 MB) olarak tanımlanmıştır.
2. `backend/app/routers/upload.py:96, 136`: `POST /api/upload/image` ve `POST /api/upload/video` uç noktaları 10MB ve 50MB dosya kabul eder.
3. `backend/app/routers/messages.py:153`: DM üzerinden gönderilen görsel ve videolar `POST /api/messages/media` ile FastAPI'ye iletilir (azami 15 MB).
4. `backend/app/routers/streams.py:473`: Canlı yayın kapak görseli `POST /api/streams/{stream_id}/thumbnail` ile FastAPI'ye iletilir (azami 10 MB).

**Kritik Arıza:**
Bir kullanıcı telefonundan 6 MB, 15 MB veya 45 MB boyutunda tipik bir dikey video (story) yüklemeye çalıştığında, istek FastAPI'ye dahi ulaşamadan Nginx katmanında kesilir ve kullanıcıya şu yanıt döner:
`HTTP 413 Request Entity Too Large`

**Sonuç:**
Uygulamanın en temel vitrin özelliği olan Story (Hikaye) video paylaşımı, DM video paylaşımı ve yüksek çözünürlüklü ilan fotoğrafları üretim ortamında tamamen çalışmaz hale gelir.

#### 2. Çözüm / Refactoring Reçetesi
1. `deploy/scale/V2.1/node1/resources/nginx/conf.d/teqlif.conf` dosyasında:
   * Genel `client_max_body_size 5m;` ayarı `client_max_body_size 60m;` olarak yükseltilmelidir.
   * Veya genel seviye 10m tutulup, yalnızca medya yükleme yolları için özel `location` bloklarında limit artırılmalıdır:
     ```nginx
     location ~ ^/api/(stories|upload|messages/media) {
         client_max_body_size 60m;
         proxy_pass http://teqlif_app;
         ...
     }
     ```
2. Değişiklik sonrası `nginx -t` test edilip Nginx yeniden yüklenmelidir (`systemctl reload nginx`).

---

### SRE-40 · 🔴 P0 (Kritik) · Node1 Çöküş Kurtarma Runbook'unun (`runbook.sh`) Tüm Üretim DNS Trafiğini FastAPI/Nginx/MinIO Olmayan Node2'ye Yönlendirip Sistemi Çökertmesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/node2/resources/scripts/runbook.sh` (Satır 198–228)
* **İlgili Adım:** `log_step "6. DNS Değişikliği (MANUEL)"`

#### 1. Sorunun Tanımı ve Arıza Modu
`node2` üzerinde bulunan ve felaket anında operatörün çalıştırması için hazırlanan `runbook.sh` scripti incelendiğinde:
Adım 6'da operatöre şu talimat verilir:
```bash
# Satır 202-207
Cloudflare panelinde şu A kayıtlarını 135.125.223.43 (node2) yap:
  teqlif.com         A  →  135.125.223.43
  www.teqlif.com     A  →  135.125.223.43
  api.teqlif.com     A  →  135.125.223.43
  uploads.teqlif.com A  →  135.125.223.43
```
Hemen ardından Adım 7'deki notlar incelendiğinde (satır 226–227):
```
• FastAPI node2'de çalışmıyor — kullanıcı trafiği node2'ye ulaşıyor ama API cevap veremez
• FastAPI kurulumu bu runbook kapsamında değil — node1'i kurtarmak öncelik!
```
**Operasyonel Felaket Senaryosu:**
1. `node1` donanımsal arıza yaşar (OVH elektrik/ağ kesintisi).
2. Nöbetçi operatör runbook'u çalıştırır. PostgreSQL veritabanı başarıyla node2 üzerinde PITR veya pg_dump ile ayağa kalkar.
3. Operatör runbook'un talimatına uyarak Cloudflare DNS kayıtlarını node2'ye yönlendirir.
4. Fakat node2 üzerinde:
   * **Nginx yoktur** (HTTP 80/443 dinleyen hiçbir şey yoktur veya UFW kapalıdır).
   * **FastAPI yoktur** (Python venv, Uvicorn, teqlif.service kurulu değildir).
   * **MinIO yoktur** (uploads.teqlif.com çöker, görseller 404/Connection Refused olur).
5. Tüm dünyadaki mobil ve web kullanıcıları anında `502 Bad Gateway` veya `ERR_CONNECTION_REFUSED` almaya başlar.

**Sonuç:**
Runbook, veri tabanını kurtarmakta fakat canlı trafiği bilerek ve isteyerek çalışan bir uygulama bulunmayan boş bir makineye (black hole) yönlendirmektedir. Kurtarma prosedürü sistemi ayağa kaldırmak yerine tam bir kesintiye sokmaktadır.

#### 2. Çözüm / Refactoring Reçetesi
1. **Seçenek A (Tam Sıcak/Ilık Standby Node2):**
   * `bootstrap_node2.sh` scriptine Nginx, MinIO read-only alias ve `teqlif.service` (minimal worker sayısı ile) kurulumu eklenmeli; node2 gerçek bir Disaster Recovery (DR) düğümüne dönüştürülmelidir.
2. **Seçenek B (Statik Bakım Sayfası - Hızlı Çözüm):**
   * Runbook içindeki DNS yönlendirme talimatı kaldırılmalı veya Cloudflare üzerinde statik bir "Sistem Bakımda" (Cloudflare Waiting Room / Worker) sayfasına yönlendirme talimatı verilmelidir.
   * Canlı API trafiği, node2 üzerinde FastAPI/Nginx ortamı doğrulanmadan ASLA node2'ye çevrilmemelidir.

---

### SRE-41 · 🟠 P1 (Yüksek) · MinIO Yedekleme Scriptinde (`minio_backup.sh`) Hardcoded ve Geçersiz ILM Kural ID'si Nedeniyle Kayıt Silinmesi Riski

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh` (Satır 39–49)
  * `deploy/scale/V2.1/scripts/setup_minio_ilm.sh` (Satır 22–49)
* **İlgili Fonksiyon:** `ilm_set_days`

#### 1. Sorunun Tanımı ve Arıza Modu
`node2` üzerindeki `minio_backup.sh` scripti, yayın kayıtlarını node1 MinIO'sundan yedekler. Yedekleme başarılı veya başarısız olduğunda MinIO'daki dosya yaşam döngüsü (ILM) süresini dinamik olarak ayarlar:
```bash
MINIO_ILM_ID="db3tiuskndq8as06c0e0"
MINIO_ILM_NORMAL_DAYS=2
MINIO_ILM_EMERGENCY_DAYS=7

ilm_set_days() {
    local days="$1"
    mc ilm edit --id "${MINIO_ILM_ID}" --expiry-days "${days}" node1minio/teqlif \
        >/dev/null 2>&1 \
        && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: ILM retention=${days}d" \
        || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) minio_backup: WARNING ILM güncellenemedi"
}
```
**Kritik Arıza:**
`MINIO_ILM_ID="db3tiuskndq8as06c0e0"` değeri, eski bir test ortamında MinIO tarafından rastgele üretilmiş geçici bir string'dir.
MinIO her `mc ilm add` komutunda yeni ve benzersiz bir rastgele hash üretir (`setup_minio_ilm.sh:44` çalıştığında kural ID'si tamamen farklı bir değer alır).
Bu nedenle:
1. `mc ilm edit --id "db3tiuskndq8as06c0e0" ...` komutu her çalıştığında **`Rule ID not found`** hatası verir.
2. `>/dev/null 2>&1` nedeniyle hata tamamen gizlenir.
3. Bir gece WireGuard dalgalanması veya disk doluluğu nedeniyle `minio_backup.sh` başarısız olursa, kod satır 57'deki `ilm_set_days 7` çağrısını yapar.
4. Kural ID bulunamadığı için komut sessizce başarısız olur ve ILM süresi 7 güne ÇIKARILAMAZ; node1 MinIO'sunda 2 gün olarak kalmaya devam eder!
5. Node2 yedeği alamadığı halde, node1 MinIO'su 48 saat sonra tüm canlı yayın video kayıtlarını **kalıcı olarak siler!**

#### 2. Çözüm / Refactoring Reçetesi
1. `minio_backup.sh` içinde hardcoded ID kaldırılmalıdır.
2. `setup_minio_ilm.sh` içindeki dinamik ID bulma mantığı `ilm_set_days` fonksiyonuna entegre edilmelidir:
   ```bash
   ilm_set_days() {
       local days="$1"
       local rule_id
       rule_id=$(mc ilm ls node1minio/teqlif --json 2>/dev/null | python3 -c "
   import sys, json
   for line in sys.stdin:
       try:
           for r in (json.loads(line).get('config') or {}).get('rules') or []:
               if (r.get('filter') or {}).get('prefix') == 'recordings/':
                   print(r.get('id', ''))
       except Exception: pass
   " 2>/dev/null | head -1)

       if [[ -n "${rule_id}" ]]; then
           mc ilm edit --id "${rule_id}" --expiry-days "${days}" node1minio/teqlif
       fi
   }
   ```

---

### SRE-42 · 🟠 P1 (Yüksek) · Node2 Redis Replica Konfigürasyonunun (`/etc/redis/redis-replica.conf`) Bulunmaması ve Failover'ın Çökmesi

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/node2/systemd/teqlif-redis-replica.service` (Satır 8)
  * `deploy/scale/V2.1/scripts/bootstrap_node2.sh` (Satır 131–160)
  * `deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh`
* **İlgili Servis:** `teqlif-redis-replica.service`

#### 1. Sorunun Tanımı ve Arıza Modu
`node2/systemd/teqlif-redis-replica.service` servisi şu komutla başlar:
```ini
ExecStart=/usr/bin/redis-server /etc/redis/redis-replica.conf --supervised systemd
```
Ancak:
1. `deploy/scale/V2.1/node2/resources/` altında hiçbir `redis-replica.conf` dosyası yoktur.
2. `bootstrap_node2.sh` scripti bu dosyayı oluşturacak veya şablonunu kopyalayacak hiçbir adıma sahip değildir.
3. Servis başlatıldığında Redis anında çöker:
   `Fatal error, can't open config file '/etc/redis/redis-replica.conf': No such file or directory`
4. Dahası, `teqlif-redis-failover.service` dosyasında şu kural vardır:
   ```ini
   Requires=teqlif-redis-replica.service
   ```
   Replica servisi çöktüğü için systemd `teqlif-redis-failover.service`'i de çalıştırmayı reddeder (`dependency failed`).

**Sonuç:**
Mimari dokümanlarda övülen "Node2 Redis HA Standby ve 10 saniyede otomatik failover" mekanizması fiilen tamamen ölüdür; tek bir konfigürasyon eksikliği nedeniyle çalışmamaktadır.

#### 2. Çözüm / Refactoring Reçetesi
1. `deploy/scale/V2.1/node2/resources/redis/redis-replica.conf.template` dosyası oluşturulmalıdır:
   ```text
   port 6379
   bind 127.0.0.1 10.10.0.2
   replicaof 10.10.0.1 6379
   masterauth <core_redis_pass>
   requirepass <core_redis_pass>
   dir /var/lib/redis
   appendonly yes
   ```
2. `bootstrap_node2.sh` scriptine bu şablonun `/etc/redis/redis-replica.conf` yoluna kopyalanması ve parolasının doldurulması adımı eklenmelidir.

---

### SRE-43 · 🟠 P1 (Yüksek) · `teqlif-agent` Self-Healer Modülünün Yetkisiz Kullanıcı Nedeniyle Servisleri Yeniden Başlatamaması

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/teqlif-agent/modules/healer.py` (Satır 94–140)
  * `deploy/scale/V2.1/node2/systemd/teqlif-agent.service` (Satır 9–23)
  * `deploy/scale/V2.1/nodeMonitor/systemd/teqlif-agent.service` (Satır 9–23)

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif-agent` platformun merkezi kontrol düzlemidir. Çöken bir servisi algıladığında `SelfHealer` sınıfı devreye girer:
```python
# healer.py:130
async def _run(*cmd: str) -> bool:
    proc = await asyncio.create_subprocess_exec(*cmd, ...)
    await proc.wait()
    return proc.returncode == 0

# Çağrılar:
await _run("systemctl", "reset-failed", svc)
await _run("systemctl", "start", svc)
```
Ancak `teqlif-agent.service` systemd birimi incelendiğinde:
```ini
User=teqlif-agent
Group=teqlif-agent
NoNewPrivileges=true
ProtectSystem=strict
```
`teqlif-agent` kullanıcısı standart, yetkisiz bir Linux sistem kullanıcısıdır.
Linux Polkit ve systemd güvenlik modeli gereği, root olmayan ve `sudoers` yetkisi bulunmayan bir kullanıcı `systemctl reset-failed` veya `systemctl start` komutlarını çalıştıramaz.
Komut çalıştırıldığında systemd anında:
`Failed to reset failed state of unit teqlif.service: Access denied`
hatası döner ve `proc.returncode != 0` olur.

**Sonuç:**
Dokümanlarda belirtilen "servis çökerse healer otomatik olarak ayağa kaldırır" mekanizması yetki reddi nedeniyle hiçbir zaman çalışmaz. Çöken servisler `failed` durumunda kilitli kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. `/etc/sudoers.d/teqlif-agent` dosyası oluşturularak `teqlif-agent` kullanıcısına yalnızca belirtilen servisleri yönetme yetkisi şifresiz olarak verilmelidir:
   ```text
   teqlif-agent ALL=(ALL) NOPASSWD: /bin/systemctl reset-failed teqlif*, /bin/systemctl start teqlif*, /bin/systemctl restart teqlif*
   ```
2. `healer.py` içindeki `_run` çağrısına `sudo` eklenmelidir:
   ```python
   await _run("sudo", "/bin/systemctl", "reset-failed", svc)
   await _run("sudo", "/bin/systemctl", "start", svc)
   ```

---

### SRE-44 · 🟠 P1 (Yüksek) · Pazar Gecesi 02:00 UTC Ağ Darboğazı: `pg_basebackup` ile Video Transfer Penceresinin Aynı Anda Başlatılması

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/cluster.yaml` (Satır 32–34)
  * `deploy/scale/V2.1/schedule.yaml` (Satır 58–65 ve 357–361)
  * `deploy/scale/V2.1/node2/resources/scripts/pg_basebackup.sh`

#### 1. Sorunun Tanımı ve Arıza Modu
Zamanlama dosyaları çapraz analiz edildiğinde:
1. `cluster.yaml:33`:
   ```yaml
   transfer_window_start_utc: 2
   transfer_window_end_utc:   5
   ```
   Canlı yayın sunucuları olan `node3` ve `node4`, yerel disklerinde biriken tüm yüksek kaliteli MKV/MP4 canlı yayın kayıtlarını **02:00 UTC** itibarıyla WireGuard üzerinden `node1` MinIO'suna aktarmaya başlar.
2. `schedule.yaml:357-361` ve `node2/systemd/teqlif-pg-basebackup.timer`:
   `pg_basebackup` **Pazar 02:00 UTC'de** tetiklenir. `node1` üzerindeki onlarca gigabaytlık ham PostgreSQL veritabanını sıkıştırarak WireGuard üzerinden `node2`'ye akıtır.
3. `schedule.yaml:64`:
   `release_pending_earnings_task` saat **02:15 UTC'de** çalışır.
4. `schedule.yaml:30`:
   `compute_analytics_cache_task` saat **02:30 UTC'de** çalışır.

**Ağ ve I/O Çarpışması:**
Pazar 02:00 UTC'de `node1` sunucusunun 1 Gbps fiziksel ağ kartı üzerinde:
* Node3'ten gelen video yükleme trafiği (~300–400 Mbps)
* Node4'ten gelen video yükleme trafiği (~300–400 Mbps)
* Node2'ye giden `pg_basebackup` veri çıkışı (~400–600 Mbps)
**aynı anda başlar!**
Toplam bant genişliği ihtiyacı 1.2+ Gbps'e çıkarak 1 Gbps hattı tamamen tıkar (port saturation). WireGuard UDP paketleri düşer (packet drop), `pg_basebackup` akışı zaman aşımına uğrar veya MinIO PUT istekleri 504 Timeout alır.

#### 2. Çözüm / Refactoring Reçetesi
1. `cluster.yaml` içindeki video transfer penceresi `pg_basebackup`'ın bitmesinden sonraya ötelenmelidir:
   ```yaml
   transfer_window_start_utc: 3   # 02:00 yerine 03:30 veya 04:00
   transfer_window_end_utc:   6
   ```
2. Veya `pg_basebackup` Pazar gecesi 01:00 UTC'ye çekilmeli, video transferi 02:30'a kadar bekletilmelidir.
3. `pg_basebackup.sh` içine `--max-rate=40M` (40 MB/s bant genişliği tavanı) eklenerek ağın tamamen kilitlenmesi engellenmelidir.

---

### SRE-45 · 🟡 P2 (Orta) · Üretim Ortamında 30 Günlük Access Token (`ACCESS_TOKEN_EXPIRE_MINUTES=43200`) Güvenlik Riski

* **Etkilenen Dosya:** `deploy/scale/V2.1/node1/resources/.env.production.template` (Satır 35)

#### 1. Sorunun Tanımı ve Arıza Modu
Üretim ortamı konfigürasyon şablonunda JWT token geçerlilik süresi şu şekilde tanımlanmıştır:
```ini
ACCESS_TOKEN_EXPIRE_MINUTES=43200
```
43.200 dakika tam olarak **30 güne (1 ay)** denk gelmektedir.
Standart ve güvenli OAuth2 / JWT mimarisinde:
* `access_token`: Kısa ömürlü olmalıdır (15–60 dakika). Çünkü JWT stateless'tır; veritabanına bakmadan doğrulanır.
* `refresh_token`: Uzun ömürlü olmalıdır (30 gün) ve Redis'te saklanarak istendiğinde anında iptal (revoke) edilebilmelidir.

**Güvenlik Zafiyeti:**
Access token 30 gün geçerli olduğunda:
1. Bir kullanıcının cihazı çalındığında, hesabı ele geçirildiğinde veya şifresi değiştirildiğinde; saldırganın elindeki access token **30 gün boyunca geçerli kalmaya devam eder**. Şifre değiştirmek veya "Tüm oturumlardan çık" demek bu token'ı iptal edemez.
2. Sisteme kurulan Refresh Token mekanizması (ve `SRE-38`'de incelediğimiz rotasyon mantığı) fiilen işlevsiz kalır; çünkü istemciler 30 gün boyunca hiçbir zaman token yenileme ihtiyacı duymaz.

#### 2. Çözüm / Refactoring Reçetesi
1. `.env.production` dosyasında access token süresi makul bir değere çekilmelidir:
   ```ini
   ACCESS_TOKEN_EXPIRE_MINUTES=60   # 1 saat
   ```
2. Oturumun 30 gün boyunca devam etmesi, mobil ve web istemcilerinin her 1 saatte bir arka planda sessizce `/api/auth/refresh` endpoint'ini çağırmasıyla (refresh token kullanarak) sağlanmalıdır.

---

### SRE-46 · 🟡 P2 (Orta) · `LeaderElector` Basit HTTP Ping Algoritmasında Split-Brain ve Çift Temizlik Riski

* **Etkilenen Dosya:** `deploy/scale/V2.1/teqlif-agent/leader.py` (Satır 36–54)
* **İlgili Fonksiyon:** `LeaderElector.check`

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif-agent` içindeki lider seçim mekanizması Raft, Paxos veya Redis kilitleri yerine basit bir tek yönlü HTTP ping ile kurgulanmıştır:
```python
results = await asyncio.gather(*[self._ping(p) for p in higher], return_exceptions=True)
any_alive = any(r is True for r in results)
if any_alive:
    self._demote()
    return False
else:
    self._promote()
    return True
```
Yorum satırında `Partition'da her ada kendi liderini seçer` yazmaktadır.

**Arıza Modu (Split-Brain):**
WireGuard mesh üzerinde OVH Gravelines (node1) ile OVH Saarbrücken (node2) arasında anlık 2 saniyelik bir ağ titremesi (jitter/packet loss) meydana geldiğinde:
1. Node2'deki agent Node1'e `/ping` atar ve istek timeout'a düşer (`any_alive = False`).
2. Node2 kendisini anında **LİDER** ilan eder (`self._promote()`).
3. Node1 zaten en yüksek öncelikli node olduğu için kendisini **LİDER** saymaya devam etmektedir.
4. Ağda **2 lider** oluşur (Split-Brain).
5. Hem Node1 hem Node2 aynı anda `janitor.py` modülünü çalıştırarak veritabanındaki süresi dolmuş kayıtları silmeye başlar; aynı anda `reporter.py` çalıştırarak Telegram kanalına mükerrer durum raporları basar.

#### 2. Çözüm / Refactoring Reçetesi
1. Tek bir başarısız ping ile anında liderliğe terfi edilmemeli; en az 3 ardışık başarısız cycle (3 dakika) şartı aranmalıdır (`consecutive_failures >= 3`).
2. Alternatif olarak, liderlik durumu Redis üzerinde TTL'li bir dağıtık kilit (`SET teqlif:agent:leader <node_id> NX EX 90`) ile güvenceye alınmalıdır.

---

### SRE-47 · 🔴 P0 (Kritik) · `StoreVerifierFactory` İçinde Google Play Verifier Bulunmaması ve Android Satın Alımlarının Çökmesi

* **Etkilenen Dosya:** `backend/app/services/store/factory.py` (Satır 10–21), `backend/app/services/store/notification_factory.py` (Satır 7–14)
* **İlgili Sınıflar:** `StoreVerifierFactory`, `StoreNotificationHandlerFactory`
* **Etkilenen Endpoint:** `POST /api/wallet/purchase/verify` (`backend/app/routers/wallet.py:34-48`)

#### 1. Sorunun Tanımı ve Arıza Modu
`wallet.py` içindeki `PurchaseVerifyRequest` modeli mobil platformlar için `platform="^(apple|google|web)$"` doğrulaması yapar:
```python
class PurchaseVerifyRequest(BaseModel):
    platform: str = Field(..., pattern="^(apple|google|web)$")
```
Ancak `backend/app/services/store/factory.py` içinde platform fabrikası şöyle tanımlanmıştır:
```python
def _make_apple() -> StoreVerifier:
    from app.services.store.apple_verifier import AppleVerifier
    return AppleVerifier()

_REGISTRY: dict[str, type] = {
    "apple": _make_apple,
}

class StoreVerifierFactory:
    @staticmethod
    def get(platform: str) -> StoreVerifier:
        factory_fn = _REGISTRY.get(platform)
        if factory_fn is None:
            raise ValueError(f"Desteklenmeyen store platform: {platform!r}")
        return factory_fn()
```
Aynı şekilde `notification_factory.py`:
```python
class StoreNotificationHandlerFactory:
    @staticmethod
    def get(platform: str, session: AsyncSession) -> StoreNotificationHandler:
        if platform == "apple":
            from app.services.store.notifications.apple_handler import AppleNotificationHandler
            return AppleNotificationHandler(session)
        raise ValueError(f"Desteklenmeyen notification platform: {platform!r}")
```

**Arıza Modu:**
1. Bir Android kullanıcısı Google Play In-App Purchase ile Teqlik satın aldığında mobil istemci `platform="google"`, `product_id="teqlik_coin_100"` ve `payload` (purchaseToken / signature) ile `POST /api/wallet/purchase/verify` çağırır.
2. `VerifyPurchaseCommand` çalıştığında `StoreVerifierFactory.get("google")` çağrılır.
3. `_REGISTRY` içinde `"google"` anahtarı bulunmadığı için anında `ValueError: Desteklenmeyen store platform: 'google'` fırlatılır.
4. FastAPI bu hatayı yakalamaz ve kullanıcıya `HTTP 500 Internal Server Error` döner.
5. Google Play kullanıcının kredi kartından parayı kesmiştir; ancak teqlif backend'i faturayı doğrulayamadığı için kullanıcının bakiyesine Teqlik asla yüklenmez!
6. Kullanıcı destek talebi açar, chargeback / iade ister veya Google Play Store'da 1 yıldızlı şikayet bırakır. Android platformunda uygulama içi gelir elde etmek imkansızdır.

#### 2. Çözüm / Refactoring Reçetesi
1. `backend/app/services/store/google_verifier.py` modülü oluşturulmalı; Google Play Developer API (Android Publisher v3) ile `inappproducts.purchases.get` token doğrulaması implement edilmelidir (`GooglePlayVerifier(StoreVerifier)`).
2. `backend/app/services/store/factory.py` içine `"google": _make_google` kaydı eklenmelidir.
3. `backend/app/services/store/notifications/google_handler.py` eklenerek `StoreNotificationHandlerFactory` içine `"google"` desteği bağlanmalıdır.
4. Google Play credentials (`google-play-service-account.json`) ayarları `settings` sınıfına eklenmelidir.

> ✅ **Çözüldü** — commit `a8448139`, 2026-10-30. `GooglePlayVerifier` implementasyonu oluşturuldu, factory.py'ye `google` platformu eklendi, config'e `google_play_service_account_path` eklendi.

---

### SRE-48 · 🔴 P0 (Kritik) · Üretim Ortamında Apple Sandbox Dekontlarının Kabul Edilmesi ve Sınırsız Karşılıksız Teqlik İstismarı

* **Etkilenen Dosya:** `backend/app/services/store/apple_verifier.py` (Satır 76–80)
* **İlgili Fonksiyon:** `AppleVerifier.verify`

#### 1. Sorunun Tanımı ve Arıza Modu
`AppleVerifier.verify` metodu, Apple App Store Server API v2 JWS token'ını (`signedTransactionInfo`) doğrulamaktadır:
```python
env = claims.get("environment", "")
if env not in ("Production", "Sandbox"):
    raise ValueError(f"Geçersiz Apple environment: {env}")
```
Kod, ortamın `"Production"` veya `"Sandbox"` olmasını kabul etmekte, ancak backend'in hangi ortamda (`settings.app_env`) çalıştığını HİÇBİR ŞEKİLDE KONTROL ETMEMEKTEDİR!

**Arıza Modu (Exploit):**
1. Apple Sandbox dekontları, Apple'ın resmi Root CA'sı tarafından imzalanır ve x5c sertifika zinciri üretim zinciriyle aynıdır (geçerlidir).
2. Saldırgan veya kötü niyetli bir kullanıcı, Apple Developer hesabında bir Sandbox Test kullanıcısı açar (veya TestFlight / Jailbreak araçlarıyla sahte bir sandbox satın alma işlemi yapar).
3. Bu sandbox işlemi için Apple sıfır maliyetle geçerli bir JWS `signedTransactionInfo` üretir (içinde `"environment": "Sandbox"` yazar).
4. Saldırgan bu sandbox payload'unu üretim ortamındaki canlı sunucuya (`https://api.teqlif.com/api/wallet/purchase/verify`) gönderir.
5. `AppleVerifier` imzayı doğrular, `env` değerinin `"Sandbox"` olduğunu görür ve izin verir.
6. `VerifyPurchaseCommand` kullanıcının hesabına anında 1.000 veya 10.000 Teqlik ekler!
7. Saldırgan bu Teqlik'lerle canlı yayınlarda hediye gönderir, ilanlarını öne çıkarır ve hatta `POST /api/wallet/withdraw` ile bu sanal bakiyeyi gerçek banka hesabına (IBAN) TRY nakit olarak çeker!
8. Şirket, kasasından tek kuruş almadığı halde dışarıya yüzbinlerce lira gerçek nakit ödemek zorunda kalır.

#### 2. Çözüm / Refactoring Reçetesi
`apple_verifier.py` içine üretim ortamı doğrulaması eklenmelidir:
```python
env = claims.get("environment", "")
if settings.app_env == "production":
    if env != "Production":
        raise SecurityException("Üretim ortamında Apple Sandbox dekontları kabul edilemez.")
else:
    if env not in ("Production", "Sandbox"):
        raise ValueError(f"Geçersiz Apple environment: {env}")
```

> ✅ **Çözüldü** — commit `a8448139`, 2026-10-30. `apple_verifier.py`'ye `iap_allow_sandbox` flag kontrolü eklendi; production'da Sandbox receipt'ler reddediliyor.

---

### SRE-49 · 🟠 P1 (Yüksek) · 60 Saniyelik Global Circuit Breaker Nedeniyle Tek Hatada Tüm iOS VoIP Aramalarının Düşmesi

* **Etkilenen Dosya:** `backend/app/services/apns_service.py` (Satır 10–28, 107–111)
* **İlgili Fonksiyonlar:** `get_apns_client`, `send_voip_push`

#### 1. Sorunun Tanımı ve Arıza Modu
`apns_service.py` içinde VoIP push gönderimi için modül seviyesinde bir başarısızlık zaman damgası ve 60 saniyelik bekleme süresi tanımlanmıştır:
```python
_apns_clients: dict[bool, APNs | None] = {True: None, False: None}
_apns_last_failures: dict[bool, float] = {True: 0.0, False: 0.0}
_APNS_RETRY_COOLDOWN: int = 60

def get_apns_client(sandbox: bool) -> APNs | None:
    ...
    last_failure = _apns_last_failures[sandbox]
    if last_failure > 0 and (time.monotonic() - last_failure) < _APNS_RETRY_COOLDOWN:
        return None
    ...

async def send_voip_push(token: str, payload: dict, sandbox: bool | None = None):
    ...
    except Exception as e:
        logger.error("[CALL_PROCESS][APNS] VoIP push EXCEPTION | %s", e, exc_info=True)
        _apns_clients[effective_sandbox] = None
        _apns_last_failures[effective_sandbox] = time.monotonic()
        return False, False
```

**Arıza Modu (Global Blackout):**
1. Herhangi bir iOS kullanıcısına VoIP araması gönderilirken geçici bir ağ aksaması (anlık TCP reset, DNS gecikmesi veya Apple APNs gateway SSL el sıkışma timeout'u) meydana gelir.
2. `send_voip_push` bir `Exception` yakalar.
3. `_apns_clients[effective_sandbox] = None` yapılır ve `_apns_last_failures[effective_sandbox] = time.monotonic()` atanır.
4. Takip eden **60 saniye boyunca**, sistemdeki **HİÇBİR** kullanıcıya VoIP push atılamaz (`get_apns_client` doğrudan `None` döner ve çağrılar `return False, False` ile düşer).
5. 60 saniyelik süre dolmadan önce başka bir çağrı gelirse o da push gönderemez; 60. saniyede gelen çağrı da anlık bir hata alırsa sayaç tekrar 60 saniye uzatılır!
6. Sonuç: Tek bir münferit ağ hatası yüzünden sistemdeki yüzlerce iOS kullanıcısının gelen çağrıları çalmaz, aramalar "cevapsız arama" (missed call) olarak düşer.

#### 2. Çözüm / Refactoring Reçetesi
1. `aioapns.APNs` HTTP/2 bağlantı havuzuna (connection pool) sahiptir. Tek bir push hatasında client komple sıfırlanmamalı ve modül seviyesinde 60 saniyelik global kilit uygulanmamalıdır.
2. Circuit breaker sadece arka arkaya 5+ başarısız istek (`consecutive_failures >= 5`) alındığında devreye girmeli ve bekleme süresi maksimum 5–10 saniye olmalıdır.
3. İstek bazlı geçici hatalar için 1 saniyelik exponential backoff ile 2 yeniden deneme (retry) uygulanmalıdır.

---

### SRE-50 · 🟠 P1 (Yüksek) · Canlı Yayın Kalp Dokunuşlarında Senkron PostgreSQL Commit ve 150.000 WS/sn Mesaj Bombardımanı

* **Etkilenen Dosya:** `backend/app/services/like_service.py` (Satır 180–240), `backend/app/routers/streams.py` (Satır 417)
* **İlgili Fonksiyon:** `LikeService.add_stream_like`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcılar canlı yayın izlerken ekrana seri dokunarak (tap-to-heart) beğeni gönderirler.
Mevcut `add_stream_like` fonksiyonu her dokunuş için şu adımları işletmektedir:
```python
self.db.add(StreamLike(stream_id=stream_id, user_id=user_id))
await self.db.commit()

await publish_chat(stream_id, {
    "type": WS.STREAM_LIKE,
    "user_id": user_id,
    "username": username,
})
```

**Arıza Modu (I/O & WebSocket Fırtınası):**
1. 500 izleyicili popüler bir canlı yayında sadece 50 kişi ekrana saniyede 4 kez dokunduğunda sisteme saniyede 200 `POST /api/streams/{id}/like` isteği gelir.
2. **PostgreSQL Çökmesi:** Her istek senkron bir ACID `INSERT INTO stream_likes` ve ardından `await self.db.commit()` çalıştırır. Saniyede 200 transaction, PgBouncer ve PostgreSQL connection pool'unu anında tüketir. Disk I/O tavan yapar, diğer kritik işlemler (teklif verme, cüzdan işlemleri) kilitlenir.
3. **WebSocket Patlaması:** Her beğeni için `publish_chat` çağrılır. 500 izleyicili bir yayında:
   $$\text{Saniyede } 200 \text{ beğeni} \times 500 \text{ izleyici} = \mathbf{100.000 \text{ WebSocket mesajı / saniye}!}$$
4. Uvicorn worker'larının event-loop'u bu devasa mesaj hacmini işleyemez; CPU %100 olur, ping/pong gecikir ve tüm izleyicilerin bağlantısı kopar (mass disconnect).

#### 2. Çözüm / Refactoring Reçetesi
1. **İstemci Tarafı Debounce:** Mobil istemci her dokunuşta HTTP isteği atmamalı; 1 saniye boyunca basılan kalpleri toplayıp tek bir istekte `{count: 8}` göndermelidir.
2. **Redis Buffer / Batch Ingestion:** `add_stream_like` doğrudan PostgreSQL'e yazmamalıdır. Sadece Redis'te `HINCRBY stream:likes:{stream_id} count` yapmalıdır.
3. **Throttled WS Broadcast:** Canlı yayın chat kanalına her tekil kalp için değil, saniyede en fazla 2 kez kümülatif beğeni sayısı (`{"type": "likes_count_update", "total": 12840}`) yayımlanmalıdır.
4. **PostgreSQL Flush:** Yayın kapandığında veya her 60 saniyede bir `stream_finalizer` Redis'teki toplam sayıyı tek bir `UPDATE live_streams SET likes_count = ...` sorgusuyla PostgreSQL'e aktarmalıdır.

---

### SRE-51 · 🟠 P1 (Yüksek) · `delayed_close_stream_task` İçinde LiveKit Ağ Hatasında Yayının Haksız Yere Kapatılması

* **Etkilenen Dosya:** `backend/app/worker.py` (Satır 2527–2536), `backend/app/routers/webhooks.py` (Satır 214–235)
* **İlgili Fonksiyonlar:** `delayed_close_stream_task`, `_delayed_close_stream`

#### 1. Sorunun Tanımı ve Arıza Modu
`livekit_service.py` içindeki `lk_list_all_rooms()` fonksiyonunun dokümantasyonunda açıkça şu kural belirtilmiştir:
> *"Hiçbir node'a erişilemediyse RuntimeError fırlatır — çağıran yer boş kümeyi 'aktif oda yok' olarak yorumlayıp aktif kayıtları silmesin."*

Ancak `backend/app/worker.py` içindeki `delayed_close_stream_task` fonksiyonu bu emniyet kilidini tersine işletmektedir:
```python
try:
    active_room_names = await _lk_list_stream()
    if room_name in active_room_names:
        logger.info("[Worker] LiveKit odası hâlâ aktif, kapatma iptal | room=%s", room_name)
        return
except Exception:
    logger.warning("[Worker] LiveKit API kontrolü başarısız, kapatmaya devam | room=%s", room_name)

async with AsyncSessionLocal() as db:
    await force_close_stream(db, room_name)
```
Aynı kusur `webhooks.py:214-235` içindeki fallback mantığında da mevcuttur: `allocate_node(ServiceType.MEDIA)` rastgele bir node seçip odayı arar; bulamazsa veya hata alırsa yayını kapatır.

**Arıza Modu:**
1. LiveKit streaming sunucularında (node3 / node4) anlık bir ağ dalgalanması, CPU spike'ı veya geçici bir timeout oluşur.
2. `_lk_list_stream()` güvenlik amacıyla `RuntimeError` fırlatır ("Node'lara erişemedim, aktif odalara dokunma!").
3. Worker bu hatayı yakalar (`except Exception:`) ve *"LiveKit kontrolü başarısız, kapatmaya devam"* diyerek `force_close_stream(db, room_name)` çalıştırır!
4. Yayıncı ve yüzlerce izleyici sorunsuz yayın yaparken veritabanında yayın zorla sonlandırılır (`is_live = False`); mobil istemcilerde yayın ekranı kapanır ve kullanıcılar atılır.

#### 2. Çözüm / Refactoring Reçetesi
1. `_lk_list_stream()` hata verirse veya hiçbir node'a erişilemezse, varsayım olarak yayın **KAPATILMAMALI**, işlem bir sonraki kontrol döngüsüne (ARQ retry) ertelenmelidir (`raise exc` veya `return`).
2. Canlı yayın sadece LiveKit API'si kesin olarak `200 OK` dönüp ilgili odanın aktif odalar listesinde **bulunmadığını doğruladığında** kapatılmalıdır.
3. `webhooks.py` içindeki `allocate_node(MEDIA)` rastgele node seçimi kaldırılmalı, canlı yayının açıldığı yetkili node (`live_streams.node_id`) hedeflenmelidir.

---

### SRE-52 · 🟠 P1 (Yüksek) · FFmpeg ve `mc cp` Alt Süreçlerinde Timeout Olmaması Nedeniyle Encoding Kuyruğunun Kilitlenmesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/teqlif-agent/modules/encoder.py` (Satır 134–148, 233–249)
* **İlgili Fonksiyonlar:** `EncoderManager._encode_one`, `EncoderManager._transfer_one`

#### 1. Sorunun Tanımı ve Arıza Modu
`encoder.py` video encode ve transfer işlemlerini alt süreçlerle (subprocess) yürütür:
```python
proc = await asyncio.create_subprocess_exec(
    *cmd,
    stdout=asyncio.subprocess.DEVNULL,
    stderr=asyncio.subprocess.PIPE,
)
_, stderr_b = await proc.communicate()
```
Ve `_transfer_one`:
```python
proc = await asyncio.create_subprocess_exec(
    *mc_cmd,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE,
)
_, stderr_b = await proc.communicate()
```

**Arıza Modu (Zombie / Process Hang):**
1. Canlı yayın ham kayıt dosyası (`.raw` / `.mp4`) ağ kesintisi nedeniyle bozulmuşsa veya FFmpeg video akışında sonsuz bir decode döngüsüne/kilitlenmesine girerse, `await proc.communicate()` hiçbir zaman tamamlanmaz (`timeout` parametresi yoktur).
2. Benzer şekilde `mc cp` (MinIO transferi) WireGuard arayüzündeki paket kaybı veya MinIO soketinin kilitlenmesi durumunda sonsuza kadar TCP retransmit döngüsünde askıda kalır.
3. `self._encoding.add(row["id"])` veya `self._transferring.add(row["id"])` asla serbest bırakılamaz (`finally` bloğuna ulaşılamaz).
4. `_resolve_max_parallel` limiti 1 veya 2 olduğundan, kilitlenen tek bir süreç tüm node'un video işleme kapasitesini bloke eder.
5. Sonraki tüm canlı yayın kayıtları diskte birikir; disk %100 dolar ve streaming node'u çöker.
6. Ayrıca FFmpeg hata verdiğinde (`proc.returncode != 0`), yarım kalan geçici `.mp4` dosyası diskten silinmemekte (`unlink`), çöp dosyalar depolama alanını doldurmaktadır.

#### 2. Çözüm / Refactoring Reçetesi
1. Alt süreçlerin tamamı `asyncio.wait_for` ile sıkı bir zaman aşımına bağlanmalıdır:
   - FFmpeg encode: Maksimum 30 dakika (`timeout=1800`).
   - `mc cp` transfer: Dosya boyutuna göre dinamik veya maksimum 15 dakika (`timeout=900`).
2. Timeout durumunda alt süreç `proc.kill()` ile sonlandırılmalı ve `proc.wait()` ile zombi süreç oluşumu engellenmelidir.
3. Hata veya timeout durumunda yarım kalan hedef dosya (`enc_path.unlink(missing_ok=True)`) diskten derhal temizlenmelidir.

---

### SRE-53 · 🟠 P1 (Yüksek) · Eksik İstemci Yönlendirmesi Nedeniyle Sahte Failover (False Failover) ve Sistem Duruşu

* **Etkilenen Dosya:** `deploy/scale/V2.1/node2/resources/scripts/redis_failover.sh` (Satır 41–49)
* **İlgili Servis:** `teqlif-redis-failover.service` / `teqlif-redis-failover.timer`

#### 1. Sorunun Tanımı ve Arıza Modu
`node2` üzerindeki `redis_failover.sh` scripti, Node1'deki ana Redis'e 3 kez erişilemediğinde otomatik failover yapar:
```bash
redis-cli -h 127.0.0.1 -p 6379 -a "${CORE_REDIS_PASS}" REPLICAOF NO ONE
touch "$PROMOTED_FLAG"
```
Script yerel replica'yı master yapar ve Telegram'a bildirim gönderir.

**Arıza Modu (False Sense of Security):**
1. Node1 çöktüğünde Node2'deki Redis başarıyla master olur (`REPLICAOF NO ONE`).
2. Ancak sistemdeki tüm istemcilerin konfigürasyonu sabittir:
   - `node1` FastAPI: `REDIS_URL=redis://127.0.0.1:6379/0`
   - `node3`, `node4` LiveKit: `redis_url = 10.10.0.1:6379`
   - `node5`, `node6` Worker/AI: `redis_url = 10.10.0.1:6379`
3. Node2'deki Redis master olsa bile, hiçbir istemci `10.10.0.2` adresine bağlanacak şekilde güncellenmez!
4. Ne sanal bir IP (floating IP / keepalived) vardır, ne de Redis Sentinel veya DNS güncellemesi tetiklenir.
5. Sonuç: Failover scripti başarıyla çalıştığını ve master olduğunu raporlar, ancak tüm teqlif platformu `10.10.0.1:6379 ConnectionRefusedError` alarak kararmış ve çökmüş kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. Gerçek ve çalışan bir failover için istemciler Redis Sentinel ile bağlanmalı (`sentinel://...`) veya WireGuard üzerinde bir Floating IP (VIP: `10.10.0.100`) tanımlanmalıdır.
2. Alternatif olarak, `redis_failover.sh` çalıştığında WireGuard mesh üzerinde `10.10.0.1` alias IP'sini Node2'nin `wg0` arayüzüne eklemeli (`ip addr add 10.10.0.1/32 dev wg0`) veya mesh DNS/hosts tablosunu güncelleyip tüm servisleri yeniden başlatmalıdır.

---

### SRE-54 · 🟡 P2 (Orta) · Sözdizim Hatası Nedeniyle Snapshot Başarısızlığı ve Fallback Modunda Eksik Tablo Yedeklenmesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/node2/resources/scripts/clickhouse_backup.sh` (Satır 22–48)
* **İlgili Servis:** `teqlif-clickhouse-backup.service`

#### 1. Sorunun Tanımı ve Arıza Modu
`clickhouse_backup.sh` scriptinde Yöntem 1 (birincil snapshot) şu komutla çalıştırılmaktadır:
```bash
DEST="${BACKUP_DIR}/${CH_DB}_${TIMESTAMP}"
if clickhouse-backup create --tables "${CH_DB}.*" "${DEST}" 2>/dev/null; then
```
`clickhouse-backup` CLI aracı, yedek adını parametre olarak alır ancak **mutlak dizin yolu (`/project/...`) kabul etmez**; yedekleri kendi konfigüre edilmiş shadow dizininde oluşturur. Ayrıca `--tables` bayrağı komuttan sonra gelmelidir.
Bu sözdizim hatası nedeniyle Yöntem 1 sessizce (`2>/dev/null`) başarısız olur.

Yöntem 2 (`BACKUP DATABASE ... TO Disk('backups', ...)`) ClickHouse konfigürasyonunda özel `backups` diski tanımlı değilse o da başarısız olur.

Script doğrudan Yöntem 3'e (Fallback) düşer:
```bash
for TABLE in user_events feed_analytics search_events swipe_live_events direct_sale_events mv_listing_events_daily; do
    clickhouse-client ... --query "SELECT * FROM ${CH_DB}.${TABLE} FORMAT Native" > "${DEST}/${TABLE}.native"
done
```

**Arıza Modu:**
1. Fallback döngüsü yalnızca hardcoded 6 tabloyu çeker.
2. Sisteme yeni eklenen ClickHouse tabloları (ör. `story_views`, `call_metrics`, `ab_test_impressions`, `wallet_events` vb.) bu listede yer almaz!
3. Bu tablolar her gece alınan yedeklere **HİÇBİR ZAMAN DAHİL EDİLMEZ**.
4. Felaket kurtarma anında yedekten geri yükleme yapıldığında, analitik verilerinin önemli bir bölümünün sonsuza dek kaybolduğu fark edilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `clickhouse-backup create <backup_name> --tables="<db>.*"` sözdizimi düzeltilmeli ve oluşturulan snapshot `clickhouse-backup upload` veya `tar` ile taşınmalıdır.
2. Fallback mekanizması sabit tablo listesi yerine veritabanındaki tüm tabloları dinamik sorgulamalıdır:
   `clickhouse-client --query "SHOW TABLES FROM ${CH_DB}"`

---

### SRE-55 · 🔴 P0 (Kritik) · Kampanya Oluşturmada Tüm Aktif Kampanyaların Harcanmış Bütçelerinin Sıfırlanması

* **Etkilenen Dosya:** `backend/app/routers/ads.py` (Satır 148–150), `backend/app/services/ad_service.py` (Satır 46–82)
* **İlgili Fonksiyonlar:** `create_campaign`, `load_active_campaigns_to_redis`

#### 1. Sorunun Tanımı ve Arıza Modu
Satıcı yeni bir reklam/boost kampanyası açtığında `POST /api/ads/campaigns` endpoint'i veritabanı kaydını oluşturduktan hemen sonra şu çağrıyı yapmaktadır:
```python
# ads.py:148
from app.services.ad_service import load_active_campaigns_to_redis
await load_active_campaigns_to_redis()
```
`load_active_campaigns_to_redis()` fonksiyonunun işleyişi şöyledir:
```python
# ad_service.py:46
async def load_active_campaigns_to_redis() -> int:
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(AdCampaign).where(AdCampaign.status == "active"))
        campaigns = result.scalars().all()
    ...
    for c in campaigns:
        remaining = max(0, c.total_budget - c.spent_budget)
        pipe.setex(_BUDGET_KEY.format(c.id), _CAMPAIGN_TTL, str(remaining))
```
Veritabanındaki `AdCampaign.spent_budget` alanı anlık olarak değil, sadece 10 dakikada bir çalışan arka plan sync cron'u (`sync_ad_campaigns_task`) ile PostgreSQL'e yansıtılmaktadır.

**Arıza Modu (Reklam Bütçesi Sıfırlanması & Sınırsız Bedava Trafik):**
1. Sistemde aktif bir Kampanya A vardır (toplam bütçe 1.000 tıklama).
2. Kullanıcılar Kampanya A'ya tıklar ve Redis'teki `ad_campaign_budget:{A}` değeri 1.000'den 50'ye iner (950 tıklama harcanmıştır). DB'deki `spent_budget` ise henüz senkronize edilmediği için 0'dır.
3. Tam bu sırada bambaşka bir kullanıcı kendi ilanı için yeni bir Kampanya B açar (`POST /api/ads/campaigns`).
4. `create_campaign`, `load_active_campaigns_to_redis()` çağırır.
5. Fonksiyon DB'den TÜM aktif kampanyaları okur. Kampanya A'nın DB'deki bütçesi `1000 - 0 = 1000` olarak hesaplanır.
6. `pipe.setex("ad_campaign_budget:A", 48*3600, "1000")` çalıştırılır!
7. **Kampanya A'nın Redis'te 50'ye düşmüş olan bütçesi tek bir hamlede ezilerek tekrar 1.000'e çıkarılır!**
8. Sonuç: Platformda her yeni reklam kampanyası başlatıldığında, yayında olan mevcut tüm diğer reklamverenlerin bütçeleri tavana vurur. Reklamverenler 50 TL ödeyip binlerce liralık sınırsız bedava tıklama/gösterim tüketir; platform devasa altyapı ve para kaybına uğrar.

#### 2. Çözüm / Refactoring Reçetesi
1. `ads.py:149` satırındaki genel `load_active_campaigns_to_redis()` çağrısı kaldırılmalıdır.
2. Yerine sadece yeni oluşturulan tek bir kampanyayı Redis'e ekleyen `_reload_campaign_to_redis(campaign.id)` fonksiyonu çağrılmalıdır.

> ✅ **Çözüldü** — commit 88923032, 2026-10-30

---

### SRE-56 · 🟠 P1 (Yüksek) · `cleanup_expired_stories` İçinde Açık DB Oturumunda Senkron MinIO Silme ve Yetim DB Kayıtları

* **Etkilenen Dosya:** `backend/app/services/story_service.py` (Satır 590–674)
* **İlgili Fonksiyon:** `StoryService.cleanup_expired_stories`
* **Zamanlama:** `worker.py:4330`: `cron(cleanup_expired_stories_task, minute=0)` (Her saat başı)

#### 1. Sorunun Tanımı ve Arıza Modu
`cleanup_expired_stories` fonksiyonu süresi dolan hikayeleri temizlemektedir:
```python
query = select(Story).where(Story.expires_at < func.now())
result = await db.execute(query)
expired = result.scalars().all()

for story in expired:
    if story.video_path:
        await storage.delete_object(story.video_path)
    if story.thumbnail_url:
        await storage.delete_object(storage.url_to_key(story.thumbnail_url))
    await db.delete(story)

await db.commit()
```

**Arıza Modu (Açık Transaction Blokajı & Yetim Kayıtlar):**
1. **Uzun Süreli DB Kilitlenmesi:** 500 adet süresi dolan hikaye olduğunda, döngü her hikaye için MinIO'ya 2 adet HTTP DELETE isteği atar ($500 \times 2 = 1.000\text{ ağ çağrısı}$). 50ms gecikme ile bu işlem **50 saniye** sürer. Satır 604'te açılan PostgreSQL transaction'ı 50 saniye boyunca açık kalır; `stories` tablosunda ve cascade `story_views` tablolarında satır kilitleri birikir, DB connection pool kilitlenir.
2. **Kısmi Başarısızlık / Yetim Kayıt (Orphan Records):** Eğer döngünün 400. adımında veritabanı bağlantısı koparsa veya `db.commit()` hata verirse, PostgreSQL tüm `db.delete(story)` işlemlerini **ROLLBACK** eder. Ancak ilk 400 hikayenin MinIO'daki videoları ve resimleri **ZATEN SİLİNMİŞTİR**!
3. Veritabanında hikaye kayıtları aktif görünmeye devam eder ancak MinIO'daki fiziksel dosyaları yok olmuştur. Kullanıcılar feed veya profil ekranında bu hikayelere tıkladığında video oynatılamaz ve `HTTP 404 / NoSuchKey` hatası patlar.

#### 2. Çözüm / Refactoring Reçetesi
1. **İki Aşamalı Temizlik (Soft-Delete & Async Drain):** Süresi dolan hikayeler önce veritabanında toplu bir `DELETE FROM stories WHERE expires_at < NOW() RETURNING id, video_path, thumbnail_url` ile silinip anında commit edilmelidir (işlem süresi < 5ms).
2. Dönen `video_path` ve `thumbnail_url` listesi ARQ kuyruğuna toplu bir görev (`batch_delete_minio_objects_task`) olarak devredilmeli; MinIO silme işlemleri veritabanı transaction'ı tamamen kapandıktan sonra arka planda yürütülmelidir.

---

### SRE-57 · 🔴 P0 (Kritik) · Systemd `ExecStartPre` İçinde Ağır Lokasyon/Kategori Sync Scripti Nedeniyle 30s Kesinti

* **Etkilenen Dosya:** `deploy/scale/V2.1/node1/systemd/teqlif.service` (Satır 13–14), `backend/scripts/sync_main.py` (Satır 13–20)
* **İlgili Servis:** `teqlif.service`

#### 1. Sorunun Tanımı ve Arıza Modu
`node1` üzerindeki `teqlif.service` FastAPI systemd servis tanımında:
```ini
ExecStartPre=/var/www/teqlif.com/.venv/bin/alembic upgrade head
ExecStartPre=/var/www/teqlif.com/.venv/bin/python scripts/sync_main.py
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000 --workers 8
Restart=always
RestartSec=5
```
Ve `sync_main.py`:
```python
async def main() -> None:
    await sync_categories()
    await sync_subcategories()
    await sync_fields()
    await sync_locations()     # Binlerce Türkiye il, ilçe ve mahalle verisi
    await sync_translations()
    await warm_feed_cache()
```

**Arıza Modu (30 Saniyelik Kesinti & Lock Starvation):**
1. Uvicorn herhangi bir unhandled exception veya OOM ile çöktüğünde veya `systemctl restart teqlif` dendiğinde, Uvicorn başlamadan önce `ExecStartPre` scriptleri çalıştırılır.
2. `sync_main.py` tek başına binlerce satırlık kategori, form konfigürasyonu ve coğrafi lokasyon verisini veritabanına basar ve feed cache ısıtır. Bu işlem ortalama **20–35 saniye** sürer!
3. Bu 35 saniye boyunca `teqlif.service` `activating (start-pre)` durumunda kalır. Port 8000 kapalıdır ve Nginx arkasındaki tüm kullanıcılar 35 saniye boyunca `502 Bad Gateway` alır.
4. **Lock Starvation:** Eğer bir migration veya DB kilitlenmesi nedeniyle script hata verirse, systemd `RestartSec=5` gereği **her 5 saniyede bir** yeni bir `alembic upgrade head` ve `sync_main.py` süreci başlatarak veritabanını kilit açmazına sokar.

#### 2. Çözüm / Refactoring Reçetesi
1. `teqlif.service` içinden `ExecStartPre` satırları kaldırılmalıdır. Systemd yalnızca Uvicorn sürecini yönetmelidir.
2. `alembic upgrade head` ve `sync_main.py` yalnızca deployment anında (`teqlif-restart.sh` scripti içinde) Uvicorn yeniden başlatılmadan önce **tek bir kez** çalıştırılmalıdır.

> ✅ **Çözüldü** — commit 15d41e98, 2026-10-30

---

### SRE-58 · 🟠 P1 (Yüksek) · Nginx Konfigürasyonunda Canlı Yayın ve Açık Artırma WebSocket Rotalarında Upgrade Eksikliği

* **Etkilenen Dosya:** `deploy/scale/V2.1/node1/resources/nginx/conf.d/teqlif.conf` (Satır 41–65)
* **İlgili Rotalar:** `ws://.../api/chat/ws/{stream_id}`, `ws://.../api/auction/{stream_id}/ws`

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif.conf` Nginx dosyasında WebSocket proxy ayarları yalnızca DM rotası için açıkça tanımlanmıştır:
```nginx
location /api/messages/ws {
    proxy_pass         http://teqlif_app;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade    $http_upgrade;
    proxy_set_header   Connection $connection_upgrade;
    ...
}
```
Ancak canlı yayın sohbeti (`/api/chat/ws/{stream_id}`) ve canlı açık artırma (`/api/auction/{stream_id}/ws`) için özel bir WebSocket bloğu bulunmamaktadır. Bu rotalar genel `location /api/` bloğuna düşer:
```nginx
location /api/ {
    proxy_pass         http://teqlif_app;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $http_cf_connecting_ip;
    proxy_set_header   X-Forwarded-For   $http_cf_connecting_ip;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout    300s;
    limit_req zone=api_limit burst=100 nodelay;
}
```

**Arıza Modu:**
1. `location /api/` bloğunda `Upgrade` ve `Connection` başlıkları yer almadığı için istemciden gelen WebSocket handshake istekleri FastAPI'ye standart HTTP isteği olarak iletilir.
2. FastAPI/Uvicorn handshake yapamaz ve bağlantı `HTTP 400 Bad Request` ile sonlanır veya anında kopar.
3. Ayrıca `limit_req zone=api_limit burst=100` direktifi nedeniyle canlı yayına aynı anda giren yüzlerce izleyicinin bağlantı istekleri HTTP 503 ile reddedilir.
4. İzleyiciler yayındaki sohbete ve teklif ekranına bağlanamaz.

#### 2. Çözüm / Refactoring Reçetesi
`teqlif.conf` içine canlı yayın ve açık artırma WebSocket rotalarını kapsayan regex location bloğu eklenmelidir:
```nginx
location ~ ^/api/(chat|auction|messages)/.*ws {
    proxy_pass         http://teqlif_app;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade    $http_upgrade;
    proxy_set_header   Connection $connection_upgrade;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $http_cf_connecting_ip;
    proxy_set_header   X-Forwarded-For   $http_cf_connecting_ip;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}
```

---

### SRE-59 · 🟠 P1 (Yüksek) · Video Kaydında Senkron VP8 Encode ve Matriks Rotasyonunun Event-Loop'u Kilitlemesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/teqlif-agent/livekit_subscriber.py` (Satır 237–256)
* **İlgili Fonksiyon:** `_record_video`

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın kayıt subprocess'inde her gelen video karesi (30 FPS) için `_record_video` coroutine'i şu işlemleri işletmektedir:
```python
arr = np.frombuffer(bytes(lk.data), dtype=np.uint8).reshape(lk.height, lk.width, 4)
if rot == 90:
    arr = np.rot90(arr, k=1)
frame = av.VideoFrame.from_ndarray(arr, format="bgra")
frame = frame.reformat(format="yuv420p")
pkts = writer.write_video(frame, ts_us)
```
Tüm bu işlemler (NumPy bellek kopyalamaları, 90 derece matriks rotasyonu, PyAV renk uzayı dönüşümü ve `libvpx` VP8 CPU tabanlı yazılımsal encode) doğrudan Python'ın tek iş parçacıklı `asyncio` event-loop'unda senkron olarak yürütülür.

**Arıza Modu (Frame Stutter & Audio Drop):**
1. 720p/1080p bir kareyi CPU ile döndürmek ve encode etmek 25–40 milisaniye sürer.
2. 30 FPS hızında çalışan bu döngü, event-loop'un işlem kapasitesinin %90–100'ünü tüketerek döngüyü sürekli bloke eder.
3. Event-loop bloke olduğu için aynı süreçteki `_record_audio` coroutine'i ses paketlerini zamanında işleyemez; ses arabelleği taşar ve kayıtlarda ses kesilmeleri / cızırtılar oluşur.
4. Ağ soketlerinden gelen WebRTC paketleri zamanında okunamadığı için LiveKit sunucusunda NACK / packet drop fırtınası başlar.

#### 2. Çözüm / Refactoring Reçetesi
Kare rotasyonu ve VP8 paketleme işlemi ana event-loop dışına çıkarılmalı; `asyncio.get_running_loop().run_in_executor(thread_pool, ...)` veya özel bir worker kuyruğuna devredilmelidir.

---

### SRE-60 · 🟡 P2 (Orta) · Relay Subprocess'inin Streaming Node'larında Olmayan Yerel Redis'e Bağlanması

* **Etkilenen Dosya:** `deploy/scale/V2.1/teqlif-agent/livekit_relay.py` (Satır 279, 215–226)
* **İlgili Fonksiyonlar:** `_main_async`, `_write_ready_and_heartbeat`

#### 1. Sorunun Tanımı ve Arıza Modu
`livekit_relay.py` entry point'inde komut satırı argümanları tanımlanırken:
```python
parser.add_argument("--redis-url", default=os.environ.get("REDIS_URL", "redis://127.0.0.1:6379"))
```
varsayılan değer olarak yerel Redis adresi atanmıştır.
Ancak teqlif V2.1 mimarisinde `node3` ve `node4` streaming düğümlerinde yerel bir Redis servisi bulunmamaktadır (`SRE-36`).
Eğer relay süreci başlatılırken `--redis-url` bayrağı verilmezse veya ortam değişkeni tanımlı değilse:
```python
r = _redis.from_url(redis_url, decode_responses=True)
await r.set(ready_key, payload, ex=_RELAY_READY_TTL)
```
bağlantısı anında `ConnectionRefusedError: [Errno 111] Connect call failed ('127.0.0.1', 6379)` alır.

**Arıza Modu:**
1. Relay süreci başarıyla LiveKit video akışını aktarmaya başlasa bile Redis'e `live:relay:ready:{room}` anahtarını yazamaz.
2. Edge orchestrator (`allocate_relay_node`) Redis'teki bu anahtarı görmediği için relay kanalını hiçbir zaman "hazır" kabul etmez.
3. İkincil node'daki izleyiciler yayına bağlanamaz, yayın trafiği diğer node'lara taşınamaz.

#### 2. Çözüm / Refactoring Reçetesi
`livekit_relay.py` içindeki varsayılan adres WireGuard mesh üzerindeki Core Redis adresi olan `redis://10.10.0.1:6379/0` olarak güncellenmelidir.

---

### SRE-61 · 🟠 P1 (Yüksek) · `purchase_sale` İçinde Satıcının Kendi Satışını Satın Alması Kontrolünün Bulunmaması ve Bakiye Doğrulamasız Sipariş Üretimi

* **Etkilenen Dosya:** `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py` (Satır 370–425)
* **İlgili Fonksiyonlar:** `purchase_sale`

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın doğrudan satış (direct sale) satın alma akışında:
```python
async def purchase_sale(sale_id: int, data: DirectSalePurchaseIn,
                        user: User, uow: SqlAlchemyUnitOfWork) -> dict:
    sale = await _get_sale(sale_id, uow.session)
    if sale.status != "active":
        raise DirectSaleNotActiveException()

    remaining = await redis_mgr.decrement_stock(sale.stream_id, data.quantity)
    ...
    order = DirectSaleOrder(
        sale_id=sale_id,
        seller_id=sale.host_id,
        buyer_id=user.id,
        listing_id=sale.listing_id,
        quantity=data.quantity,
        unit_price=unit_price,
        status="completed",
    )
    uow.session.add(order)
    sale.remaining_stock = remaining
    if remaining == 0:
        sale.status = "sold_out"
```

**Kritik Mantıksal ve Güvenlik Zaafı:**
1. **Satıcı Öz-Satın Alım Denetimi Yok:** Satıcının veya yayıncının kendi başlattığı doğrudan satış ürününü satın almasını engelleyen hiçbir doğrulama (`sale.host_id == user.id`) bulunmamaktadır.
2. **Cüzdan / Ödeme Doğrulaması Yok:** Satın alma esnasında alıcının cüzdan bakiyesi (`user.teqlik_balance` veya kart/ödeme onayı) hiçbir şekilde kontrol edilmemekte ve düşülmemektedir. Sipariş anında `status="completed"` yapılmaktadır.

**Arıza Modu (Exploit & Manipulation):**
1. Kötü niyetli bir yayıncı doğrudan satış açıp saniyeler içinde kendi API isteği veya bot hesapları üzerinden kendi ürünlerini satın alabilir (`seller_id == buyer_id == user.id`).
2. Sıfır maliyetle anında stok `sold_out` durumuna getirilir, sahte tamamlanmış siparişler (`DirectSaleOrder status='completed'`) üretilir.
3. Sistem yayıncıya kendi kendine tebrik DM'i ve Telegram kanalına satış bildirimi göndererek izleyiciler üzerinde sahte talep ve fomo (yapay hype) oluşturur.
4. Sıralama ve tavsiye algoritmaları bu sahte siparişleri gerçek satış sayarak yayıncıyı platformun en üst sıralarına taşır.

#### 2. Çözüm / Refactoring Reçetesi
1. Satıcının kendi ürününü alması engellenmelidir:
   ```python
   if sale.host_id == user.id:
       raise BadRequestException(code="SELLER_CANNOT_PURCHASE_OWN_SALE")
   ```
2. Sipariş oluşturulmadan önce ödeme rezervasyonu / cüzdan bakiyesi doğrulanmalı, ödeme teyidi alınmadan `status="completed"` verilmemelidir.

---

### SRE-62 · 🟡 P2 (Orta) · HTTP GET Endpoint'inde (`GET /api/messages/{other_user_id}`) Yan Etkili DB Commit ve Mesaj Okundu İşareti

* **Etkilenen Dosyalar:**
  * `backend/app/routers/messages.py` (Satır 95–105)
  * `backend/app/use_cases/messages/commands/mark_messages_read_command.py` (Satır 11–26)
* **İlgili Fonksiyonlar:** `get_messages`, `MarkMessagesReadCommand.execute`

#### 1. Sorunun Tanımı ve Arıza Modu
`GET /api/messages/{other_user_id}` HTTP endpoint'i:
```python
@router.get("/{other_user_id}", response_model=List[MessageOut])
async def get_messages(
    other_user_id: int,
    before_id: int | None = Query(None),
    current_user: User = Depends(get_current_user),
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    messages = await GetMessagesQuery(uow).execute(current_user.id, other_user_id, before_id)
    await MarkMessagesReadCommand(uow).execute(current_user.id, other_user_id)
    return messages
```
`MarkMessagesReadCommand.execute` içerisinde ise:
```python
result = await self.uow.session.execute(
    update(DirectMessage)
    .where(
        DirectMessage.sender_id == other_user_id,
        DirectMessage.receiver_id == uid,
        DirectMessage.is_read == False,
    )
    .values(is_read=True)
    .returning(DirectMessage.id)
)
read_ids = [row[0] for row in result.fetchall()]
await self.uow.session.commit()
if read_ids:
    await broadcast_dm(other_user_id, {"type": "messages_read", "by_user_id": uid})
```

**Standart İhlali ve Arıza Modu:**
1. **RFC 7231 / 9110 Güvenlik ve İdempotentlik İhlali:** HTTP `GET` metodları "safe" (güvenli) olmak zorundadır; sunucuda kalıcı durum değişikliği üretmemelidir.
2. **Kullanıcı Görmeden Erken Okundu İşareti:** Mobil WebView / tarayıcı bağlantı ön-yüklemesi (link prefetching), web crawler'lar veya kullanıcının eski mesajları görmek için sayfalama yapması (`before_id`) durumunda, kullanıcı yeni gelen mesajları henüz ekranında görmeden mesajlar sessizce `is_read = True` yapılır ve karşı tarafa "okundu" bildirimi gider.
3. **Read-Replica Çökmesi:** PostgreSQL Primary-Replica ayrımı yapıldığında GET istekleri doğal olarak Read-Replica'ya yönlendirilir. `get_messages` çalıştığı anda read-only bağlantıda `UPDATE` ve `commit()` çağrıldığı için işlem `read-only transaction` hatası verir ve mesaj geçmişi HTTP 500 ile çöker.

#### 2. Çözüm / Refactoring Reçetesi
1. `GET /api/messages/{other_user_id}` endpoint'inden `MarkMessagesReadCommand` çağrısı kaldırılmalıdır.
2. Mesaj okundu bildirimi için bağımsız bir endpoint tanımlanmalıdır:
   ```python
   @router.post("/{other_user_id}/read")
   async def mark_messages_read(
       other_user_id: int,
       current_user: User = Depends(get_current_user),
       uow: SqlAlchemyUnitOfWork = Depends(get_uow),
   ):
       await MarkMessagesReadCommand(uow).execute(current_user.id, other_user_id)
       return {"ok": True}
   ```
   İstemci mesajları ekranda gerçekten görüntülediğinde bu endpoint'i açıkça çağırmalıdır.

---

### SRE-63 · 🟡 P2 (Orta) · `chat.py:_check_whale_status` İçindeki Hatalı `user_type` Kontrolü Nedeniyle Tüm Yayınlarda Ağır SQL Aggregation Çalıştırılması

* **Etkilenen Dosya:** `backend/app/routers/chat.py` (Satır 84–98)
* **İlgili Fonksiyonlar:** `_check_whale_status`

#### 1. Sorunun Tanımı ve Arıza Modu
İzleyici canlı yayına katıldığında balina (büyük harcama yapan VIP kullanıcı) tespiti yapan `_check_whale_status` fonksiyonunda:
```python
host_row = await db.execute(select(User.user_type).where(User.id == host_id))
if not host_row.scalar_one_or_none():
    return  # Balina radarı yalnızca Pro host'lara gönderilir

result = await db.execute(
    select(func.coalesce(func.sum(Purchase.price), 0.0)).where(
        Purchase.buyer_id == user_id,
        Purchase.created_at >= cutoff,
    )
)
total: float = float(result.scalar() or 0.0)
```

**Mantıksal Kod Hatası:**
`User.user_type` alanı standart kullanıcılar için `"standard"`, PRO kullanıcılar için `"pro"` dizesini döner.
Python'da `bool("standard")` ifadesi `True` olduğundan, `not host_row.scalar_one_or_none()` ifadesi `"standard"` için `False` üretir ve fonksiyon **sonlanmaz (return etmez)**!
Yorum satırında `"Balina radarı yalnızca Pro host'lara gönderilir"` denmesine rağmen, kontrol `!= "pro"` yerine `not ...` yapıldığı için balina radarı **standart kullanıcıların yayınlarında da çalışır**.

**Arıza Modu:**
Sistemdeki herhangi bir standart (ücretsiz) kullanıcının yayınına yeni bir izleyici girdiğinde `Purchase` tablosu taranarak `SUM(Purchase.price) WHERE buyer_id = :uid AND created_at >= :cutoff` aggregate sorgusu işletilir. Canlı yayına binerce izleyici katıldığında, bu gereksiz sorgular PostgreSQL bağlantı havuzunu (connection pool) doldurur ve sunucuyu kilitler.

#### 2. Çözüm / Refactoring Reçetesi
Kontrol doğrudan hedef role göre düzeltilmelidir:
```python
host_type = host_row.scalar_one_or_none()
if host_type != "pro":
    return  # Balina radarı yalnızca Pro host'lara gönderilir
```

---

### SRE-64 · 🟠 P1 (Yüksek) · Resim Yüklemede Senkron Pillow LANCZOS Thumbnail Üretimi Nedeniyle Event-Loop Blokajı

* **Etkilenen Dosyalar:**
  * `backend/app/routers/upload.py` (Satır 134–170)
  * `backend/app/utils/media_processor.py` (Satır 103–122)
* **İlgili Fonksiyonlar:** `upload_image`, `_make_thumbnail`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/upload` endpoint'i `async def` olarak ana event-loop üzerinde çalışmaktadır:
```python
@router.post("")
@limiter.limit("20/minute")
async def upload_image(...):
    ...
    thumb_data = _make_thumbnail(data, ext)
```
`_make_thumbnail` fonksiyonu ise:
```python
def make_thumbnail(data: bytes, ext: str) -> bytes:
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    img.thumbnail(_THUMB_SIZE, Image.LANCZOS)
    ...
    img.save(buf, format=fmt, quality=85, optimize=True)
    return buf.getvalue()
```
Tüm bu Pillow resim işleme, EXIF rotasyonu, `Image.LANCZOS` küçültme ve optimize JPEG kaydetme işlemleri tamamen **senkron (blocking)** CPU kodudur.

**Arıza Modu:**
1. Akıllı telefonlardan gelen 10–20 Megapiksel fotoğrafların LANCZOS ile yeniden örneklenmesi ve optimize JPEG olarak encode edilmesi tek bir çekirdekte **300 ila 800 milisaniye** CPU tüketir.
2. Bu işlem doğrudan ana asyncio event-loop'ta yürütüldüğü için FastAPI worker süreci bu süre boyunca tamamen donar.
3. Donma süresince aynı worker üzerinde çalışan WebSocket bağlantıları (canlı yayın chat mesajları, teklifler, ping/pong heartbeat'leri) zamanında yanıt veremez; istemciler sunucudan düşer.
4. Eşzamanlı 5 ilan fotoğrafı yüklendiğinde worker 3-4 saniye kilitlenir ve genel API gecikmesi tavan yapar.

#### 2. Çözüm / Refactoring Reçetesi
Senkron Pillow işlemi `run_in_executor` ile arka plan thread pool'una devredilmelidir:
```python
loop = asyncio.get_running_loop()
thumb_data = await loop.run_in_executor(None, _make_thumbnail, data, ext)
```

---

### SRE-65 · 🔴 P0 (Kritik) · `/generate-description` İçinde TOCTOU Bakiye Yarış Koşulu ile Sınırsız Bedava AI İlan Açıklaması Üretimi

* **Etkilenen Dosya:** `backend/app/routers/listings.py` (Satır 721–788)
* **İlgili Fonksiyonlar:** `generate_description`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/listings/generate-description` endpoint'inde bakiye kontrolü (Time-of-Check) ile bakiye düşümü (Time-of-Use) arasında 5 ila **45 saniye süren** asenkron `generate_via_proxy(params)` ağ çağrısı bulunmaktadır:
```python
# 1. Aşama: Bakiye Kontrolü (Satır 743)
if current_user.teqlik_balance < _ai_desc_cost:
    raise InsufficientFundsException()

# 2. Aşama: 5-45 sn süren Harici LLM Çağrısı (Satır 758)
description, provider = await generate_via_proxy(params)

# 3. Aşama: Bakiye Düşümü (Satır 781)
await db.execute(
    sql_text("UPDATE users SET teqlik_balance = GREATEST(0, teqlik_balance - :cost) WHERE id = :uid"),
    {"cost": _ai_desc_cost, "uid": current_user.id},
)
await db.commit()
```

**Mali İstismar Akışı (Exploit Scenario):**
1. Standart bir kullanıcının hesabında yalnızca 5 TEQlik (tek bir AI açıklaması bedeli) bulunmaktadır.
2. Kullanıcı aynı anda paralel 10 adet HTTP `POST /api/listings/generate-description` isteği ateşler.
3. Bakiye henüz düşülmediği için 10 isteğin tamamı 1. Aşamayı (Satır 743) başarıyla geçer.
4. 10 istek birden 2. Aşamaya girer ve harici AI servislerinden (Groq / Gemini) 10 farklı ilan açıklaması üretir. Toplam maliyet platform için 50 TEQlik değerindedir.
5. 3. Aşamaya gelindiğinde ilk tamamlanan istek bakiyeyi 5'ten 0'a indirir.
6. Diğer 9 istek ise `GREATEST(0, 0 - 5) = 0` çalıştırarak bakiyeyi 0'da bırakır ve hata vermeden commit eder.
7. Sonuç: Kullanıcı sadece 5 TEQlik ödeyerek 50 TEQlik'lik AI içeriği elde eder. Bu işlem tekrarlanarak platformun kurumsal LLM API kotaları sıfır maliyetle boşaltılabilir.

#### 2. Çözüm / Refactoring Reçetesi
Bakiye kontrolü ve rezervasyonu LLM çağrısından **ÖNCE** atomik olarak veritabanında gerçekleştirilmelidir:
```python
result = await db.execute(
    sql_text(
        "UPDATE users SET teqlik_balance = teqlik_balance - :cost "
        "WHERE id = :uid AND teqlik_balance >= :cost "
        "RETURNING teqlik_balance"
    ),
    {"cost": _ai_desc_cost, "uid": current_user.id},
)
if not result.scalar_one_or_none():
    raise InsufficientFundsException()
await db.commit()

try:
    description, provider = await generate_via_proxy(params)
except Exception:
    # LLM başarısız olursa iade işlemi (Compensating Transaction)
    await db.execute(
        sql_text("UPDATE users SET teqlik_balance = teqlik_balance + :cost WHERE id = :uid"),
        {"cost": _ai_desc_cost, "uid": current_user.id},
    )
    await db.commit()
    raise
```

> ✅ **Çözüldü** — commit 88923032, 2026-10-30

---

### SRE-66 · 🟠 P1 (Yüksek) · AI Proxy Servislerinin WireGuard Yerine `0.0.0.0:8001` ile Genel İnternete Açık Olması

* **Etkilenen Dosyalar:**
  * `deploy/scale/V2.1/node6/systemd/teqlif-ai-proxy.service` (Satır 10–14)
  * `deploy/scale/V2.1/node5/systemd/teqlif-ai-proxy.service` (Satır 10–14)
* **İlgili Servisler:** `teqlif-ai-proxy.service`

#### 1. Sorunun Tanımı ve Arıza Modu
Node6 ve Node5 üzerindeki AI Proxy Uvicorn başlatma komutları:
```ini
ExecStart=/var/www/teqlif.com/.venv/bin/uvicorn app.ai_proxy_main:app \
    --host 0.0.0.0 \
    --port 8001 \
    --workers 2
```
şeklindedir.
Node6, Virginia ABD veri merkezinde genel IPv4 adresine (`5.249.165.10`) sahip bir sanal sunucudur.
`--host 0.0.0.0` kullanıldığında, Uvicorn tüm ağ arayüzlerini dinler.
Sonuç olarak, dahili kullanım için tasarlanmış olan AI Proxy mikroservisi doğrudan **genel internete (Public Internet WAN)** açılmaktadır.
İnternet üzerindeki herhangi bir IP'den `http://5.249.165.10:8001/generate` ve `/health` endpoint'lerine doğrudan HTTP istekleri gönderilebilir.
Saldırganlar `X-Internal-Token` başlığını kaba kuvvet (brute-force) ile deneyebilir veya DoS amaçlı portu flood ederek Node6 CPU'sunu tüketebilir. Token ele geçirildiği takdirde platformun tüm Groq ve Gemini kurumsal API anahtarları yetkisiz kişilerce bedava kullanılabilir.

#### 2. Çözüm / Refactoring Reçetesi
Servisin dinleme adresi mutlaka sunucunun WireGuard VPN arayüzü IP'si ile sınırlandırılmalıdır:
* Node6 için: `--host 10.10.0.6`
* Node5 için: `--host 10.10.0.5`
Ayrıca UFW / iptables kurallarında 8001 portunun sadece `wg0` arayüzünden kabul edilmesi güvence altına alınmalıdır.

---

### SRE-67 · 🟡 P2 (Orta) · `recommendation_service.py` İçinde Dinamik Salt'lı `ORDER BY hashtext(...)` ile PostgreSQL Tam Tablo Hash Sort Felaketi

* **Etkilenen Dosya:** `backend/app/services/recommendation_service.py` (Satır 370–407)
* **İlgili Fonksiyonlar:** `_ids_from_categories`

#### 1. Sorunun Tanımı ve Arıza Modu
Kişiselleştirilmiş akışta exploit ve explore ilan havuzu çekilirken şu SQL sorgusu çalıştırılmaktadır:
```python
params = {"uid": user_id, "lim": limit, "salt": str(_rand.randint(0, 999999))}
...
result = await db.execute(
    text(f"SELECT l.id FROM listings l WHERE {where} ORDER BY (hashtext(l.id::text || :salt) & 2147483647) LIMIT :lim"),
    params,
)
```

**Veritabanı Darboğazı:**
PostgreSQL'de `ORDER BY` ifadesi sabit olmayan dinamik bir ifade (`hashtext(l.id::text || :salt)`) içerdiğinde:
1. PostgreSQL **B-Tree veya herhangi bir indeksi sıralama için kullanamaz**.
2. Kategorideki tüm aktif ilanlar (on binlerce kayıt) diskten okunur.
3. Her satır için metin birleştirme (`||`) ve hash hesaplama CPU işlemi yapılır.
4. Tüm sonuç kümesi `Sort` (veya Top-N Heap Sort) algoritmasına sokulur.
5. `_ids_from_categories` fonksiyonu tek bir feed yüklemesinde en az 2 defa (exploit ve explore için), havuz boş ise fallback ile birlikte 3-4 defa çağrılır.
Mobil kullanıcılar feed'i her yenilediğinde veya sonsuz kaydırma yaptıklarında PostgreSQL üzerinde eşzamanlı onlarca tam tablo hash sort çalışır. Bu durum Node1 üzerinde CPU kullanımını %100'e kilitleyerek diğer tüm veritabanı işlemlerini geciktirir.

#### 2. Çözüm / Refactoring Reçetesi
Rastgele örnekleme için maliyetli tam tablo hash sort yerine, önceden indekslenmiş veya aralık tabanlı hafif rastgelelik teknikleri kullanılmalıdır:
1. `TABLESAMPLE BERNOULLI` veya rastgele ID aralığı seçimi (`l.id >= :rand_id LIMIT :lim`).
2. Veya kategori bazlı aktif ilan ID listelerinin Redis Set (`SMEMBERS` / `SRANDMEMBER`) üzerinde tutulması ve veritabanı sorgusu yerine Redis'ten 1 milisaniyede rastgele N ilan ID'si çekilmesi.

---

### SRE-68 · 🔴 P0 (Kritik) · `auth.py:delete_account` ve `admin_data.py:delete_user` İçinde `session:user:{uid}` Cache'inin Silinmemesi ve Token Versiyonunun Artırılmaması Nedeniyle Zombi Oturumlar

* **Etkilenen Dosyalar:** `backend/app/routers/auth.py` (satırlar 1565–1630), `backend/app/routers/admin_data.py` (satırlar 405–440, 465–495), `backend/app/utils/auth.py` (satırlar 270–340)
* **İlgili Fonksiyonlar:** `delete_account()`, `delete_user()`, `permanently_delete_user()`, `_fetch_and_cache_user()`, `get_current_user()`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı güvenliği ve oturum doğrulaması `app/utils/auth.py` içinde performans optimizasyonu amacıyla **15 dakikalık Redis oturum önbelleği** (`session:user:{user_id}`) ile korunmaktadır:
```python
# app/utils/auth.py
cached = await _redis.get(f"session:user:{user_id}")
if cached:
    return _user_from_dict(json.loads(cached))
```
Kullanıcı hesabı silindiğinde (`DELETE /api/auth/me`), admin tarafından soft-delete yapıldığında (`DELETE /api/admin-data/users/{id}`) veya kalıcı silindiğinde (`DELETE /api/admin-data/users/{id}/permanent`):
1. Veritabanında `user.status = UserStatus.DELETED` yapılır veya satır silinir (`db.commit()`).
2. **ANCAK `invalidate_user_session_cache(user_id)` ASLA ÇAĞRILMAMAKTADIR!**
3. `user.token_version` artırılmamakta veya kullanıcının refresh token anahtarları temizlenmemektedir.
4. Redis üzerindeki `session:user:{user_id}` anahtarı içerisinde `status: "active"` bilgisiyle 15 dakika (900 saniye) boyunca yaşamaya devam eder.

**Güvenlik ve İstismar Darboğazı:**
Hesabını kapatmış veya kötü niyetli hareketleri (dolandırıcılık, taciz, sahte açık artırma) sebebiyle admin tarafından banlanmış/silinmiş bir kullanıcı, tarayıcısında veya mobil cihazındaki mevcut JWT Access Token ile **tam 15 dakika boyunca**:
* API'ye istek gönderebilir,
* Yeni ilan oluşturabilir,
* Müzayedelere katılıp teklif verebilir,
* Diğer kullanıcılara özel mesaj ve taciz iletileri gönderebilir!
Kullanıcının silindiği veritabanına işlenmiş olsa dahi, `get_current_user` doğrudan Redis önbelleğinden döndüğü için silinmiş kullanıcı sistemde **zombi oturum (zombie session)** olarak tam yetkiyle çalışmaya devam eder.

#### 2. Çözüm / Refactoring Reçetesi
1. `backend/app/routers/auth.py:delete_account`, `backend/app/routers/admin_data.py:delete_user` ve `permanently_delete_user` fonksiyonlarında:
   * Hesap silinmeden/güncellenmeden hemen önce `user.token_version += 1` yapılmalıdır.
   * `await invalidate_user_session_cache(user.id)` derhal çağrılmalıdır.
   * Kullanıcıya ait tüm aktif refresh token'lar silinmelidir:
     ```python
     await invalidate_user_session_cache(user_id)
     _redis = await get_redis()
     keys = await _redis.keys(f"user:refresh:{user_id}:*")
     if keys:
         await _redis.delete(*keys)
     ```
2. Böylece silinen veya banlanan kullanıcının bir sonraki milisaniyedeki tüm istekleri `401 Unauthorized` / `USER_DELETED` ile engellenir.

> ✅ **Çözüldü** — commit `2ad08dd4`, 2026-10-30

---

### SRE-69 · 🟠 P1 (Yüksek) · `auction.py` WebSocket Handler'ının `ws_manager` Yerine İzole `AuctionConnectionManager` Kullanması ve Graceful Shutdown'da Kapanmaması

* **Etkilenen Dosyalar:** `backend/app/routers/auction.py` (satırlar 169–239), `backend/app/use_cases/auctions/auction_utils.py` (satırlar 52–110), `backend/main.py` (satırlar 155–157)
* **İlgili Sınıflar:** `AuctionConnectionManager`, `GlobalWSManager` (`ws_manager`)

#### 1. Sorunun Tanımı ve Arıza Modu
Platform genelinde tüm WebSocket bağlantıları (`chat`, `notifications`, `stream_likes`, `calls`) `app.core.ws_manager.GlobalWSManager` (`ws_manager`) üzerinden yönetilmektedir. `backend/main.py` dosyasındaki FastAPI lifespan shutdown hook'unda:
```python
# backend/main.py
@asynccontextmanager
async def lifespan(app: FastAPI):
    ...
    yield
    # SHUTDOWN
    await ws_manager.shutdown()  # Tüm açık WS bağlantılarına 1001 (Going Away) gönderip kapatır
```
Ancak `backend/app/routers/auction.py` dosyasındaki müzayede WebSocket endpoint'i (`/ws/{stream_id}`), `ws_manager` yerine modül içinde tekil tanımlanmış eski `manager = AuctionConnectionManager()` nesnesini kullanmaktadır:
```python
# backend/app/routers/auction.py:194
await manager.connect(websocket, stream_id)
```
`AuctionConnectionManager` sınıfı `ws_manager`'a kayıtlı değildir ve kendi shutdown metodu lifespan'e bağlanmamıştır.

**Arıza Modu:**
Production ortamında `teqlif-restart` çalıştırıldığında veya Uvicorn worker yeniden başlatıldığında:
1. `ws_manager.shutdown()` sadece chat ve bildirim soketlerini zarifçe kapatır.
2. Müzayededeki yüzlerce aktif teklifçi soketi `AuctionConnectionManager` içinde asılı kalır.
3. Uvicorn OS seviyesinde SIGTERM/SIGKILL alarak kapandığında, bu soketler istemciye **kirli TCP RST (Connection Reset by Peer)** ile aniden kopar.
4. Mobil istemciler zarif `1001 Going Away` kodu alamadığı için otomatik yeniden bağlanma (exponential backoff) mantığını işletemez, müzayede ortasında "Bağlantı Hatası" alarak teklif veremez ve ihale kayıpları yaşanır.

#### 2. Çözüm / Refactoring Reçetesi
1. `auction.py` içindeki `AuctionConnectionManager` doğrudan `app.core.ws_manager.ws_manager` üzerine delege edilmelidir:
   ```python
   channel = f"auction:{stream_id}"
   ws_manager.connect(websocket, channel)
   ```
2. Müzayede broadcast mesajları `ws_manager.broadcast_json(channel, data)` ile gönderilmelidir.
3. Böylece Uvicorn kapandığında tüm müzayede WebSocket'leri de tek bir merkezi noktadan kod 1001 ile zarifçe kapatılır ve mobil uygulamalar temiz failover yapar.

---

### SRE-70 · 🟠 P1 (Yüksek) · `story_service.py:delete_story` İçinde DB Commit Öncesi MinIO Nesnelerinin Silinmesi ve Hata Durumunda Yetim (Bozuk) DB Kayıtları

* **Etkilenen Dosya:** `backend/app/services/story_service.py` (satırlar 554–580)
* **İlgili Metot:** `StoryService.delete_story()`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı bir hikayesini sildiğinde `StoryService.delete_story` fonksiyonu çalışır:
```python
# backend/app/services/story_service.py
# 1. MinIO'dan video ve thumbnail'i sil
if story.video_url:
    ...
    await self.storage.delete_object(settings.s3_bucket, video_key)
if story.thumbnail_url:
    ...
    await self.storage.delete_object(settings.s3_bucket, thumb_key)

# 2. Bildirimleri ve Story kaydını sil
await self.db.execute(delete(Notification).where(Notification.related_id == story_id))
await self.db.delete(story)
await self.db.commit()  # <-- HATA: MinIO silindikten SONRA commit!
```
MinIO nesneleri veritabanı transaction'ı commit edilmeden **ÖNCE** kalıcı olarak silinmektedir (`storage.delete_object`).

**Arıza Modu:**
1. Eğer veritabanında `Notification` silinirken satır kilitlenmesi (lock timeout), serialization hatası veya `db.commit()` sırasında bağlantı kopması meydana gelirse transaction **ROLLBACK** olur.
2. `Story` kaydı ve bağlı `StoryView` kayıtları veritabanında silinmemiş olarak kalır.
3. Fakat MinIO üzerindeki video ve thumbnail dosyaları **geri döndürülemez şekilde silinmiştir**.
4. Takipçiler ana sayfada hikaye tepsisinde kullanıcının hikayesini görmeye devam eder; tıkladıklarında MinIO CDN'i **404 Not Found** döner ve mobil video oynatıcı siyah ekranda donup hata verir.

#### 2. Çözüm / Refactoring Reçetesi
Dağıtık sistemlerde harici depolama silme işlemleri DB commit'i sonrasına alınmalı veya iki aşamalı (soft-delete + outbox) yapılmalıdır:
1. `story.is_deleted = True` veya doğrudan `await self.db.delete(story)` yapılıp **önce `await self.db.commit()` başarıyla tamamlanmalıdır**.
2. Yalnızca `commit()` başarılı olduktan sonra `try/except` bloğu içinde MinIO nesneleri silinmeli; MinIO silme hatası olsa bile DB tutarlı kalmalı, arka plandaki janitor görevi yetim S3 dosyalarını temizlemelidir.

---

### SRE-71 · 🟡 P2 (Orta) · `catalog.py:/version` Endpoint'inde Tüm Veritabanı Taksonomisinin Baştan Sona Yüklenip MD5 Hash Hesaplanması

* **Etkilenen Dosya:** `backend/app/routers/catalog.py` (satırlar 15–80, 105–118)
* **İlgili Endpoint:** `GET /api/catalog/version`

#### 1. Sorunun Tanımı ve Arıza Modu
Mobil istemciler açılışta ve ağ geçişlerinde yerel kategori/filtre verilerinin güncel olup olmadığını denetlemek için hafif bir sürüm kontrolü olan `GET /api/catalog/version` endpoint'ini çağırır.
Mevcut implementasyon şöyledir:
```python
# backend/app/routers/catalog.py
@router.get("/version")
async def get_catalog_version():
    catalog_data = await _build_catalog()  # <-- TÜM VERİTABANINI ÇEKER!
    content_str = json.dumps(catalog_data, sort_keys=True)
    version_hash = hashlib.md5(content_str.encode()).hexdigest()[:8]
    return {"version": version_hash}
```
`_build_catalog()` fonksiyonu PostgreSQL'den:
* Tüm kategorileri (`Category`),
* Tüm alt kategorileri (`SubCategory`),
* Tüm dinamik form alanlarını (`CategoryField`),
* Binlerce seçenek satırını (`FieldOption`) sırayla çeker ve devasa bir Python dict üretir.

**Performans Darboğazı:**
1. Redis cache süresi dolduğunda veya binlerce mobil istemci aynı anda açıldığında, sadece 8 karakterlik bir hash öğrenmek için sunucu **tüm taksonomi veritabanını baştan sona sorgulayıp megabaytlarca JSON serileştirmesi** yapar.
2. Sürüm kontrolü yapmak, tüm kataloğu indirmekle aynı CPU ve DB I/O maliyetine sebep olur.

#### 2. Çözüm / Refactoring Reçetesi
1. Taksonomi sürümü Redis'te tek bir `catalog:version` tamsayısı (veya Unix timestamp) olarak tutulmalıdır.
2. Admin panelinden bir kategori, alt kategori veya alan güncellendiğinde bu sayaç `INCR catalog:version` ile 1 artırılmalıdır.
3. `/api/catalog/version` endpoint'i veritabanına ve `_build_catalog`'a hiç dokunmadan doğrudan Redis'teki sayacı dönmelidir:
   ```python
   @router.get("/version")
   async def get_catalog_version():
       _redis = await get_redis()
       ver = await _redis.get("catalog:version") or "1"
       return {"version": str(ver)}
   ```
Böylece yanıt süresi 40ms'den 0.5ms'ye iner, DB yükü sıfırlanır.

---

### SRE-72 · 🔴 P0 (Kritik) · `notifications.py` İçinde Eksik `AsyncSessionLocal` Import'u Nedeniyle Tüm Canlı Bildirim WebSocket'lerinin Çökmesi

> ✅ **Çözüldü** — Commit `3aaeab50` · 2026-10-29

* **Etkilenen Dosya:** `backend/app/routers/notifications.py` (satırlar 9, 121, 155)
* **İlgili Endpoint:** `WebSocket /api/notifications/ws`

#### 1. Sorunun Tanımı ve Arıza Modu
`notifications.py` dosyasının import bölümünde:
```python
# backend/app/routers/notifications.py:9
from app.database import get_db
# DİKKAT: AsyncSessionLocal BURADA İMPORT EDİLMEMİŞTİR!
```
Ancak satır 121 ve 155'te WebSocket bağlantısını doğrularken ve okunmamış bildirim sayısını hesaplarken şu kod çalıştırılmaktadır:
```python
# Satır 121:
async with AsyncSessionLocal() as db:
    result = await db.execute(select(User).where(User.id == user_id))
    ...
# Satır 155:
async with AsyncSessionLocal() as db:
    result = await db.execute(select(func.count()).where(...))
```

**Arıza Modu:**
1. Bir mobil veya web istemci `ws:///api/notifications/ws` adresine bağlandığında `websocket.accept()` çalışır.
2. İstemci ilk token mesajını gönderir.
3. Token çözülüp satır 121'e gelindiğinde Python derhal:
   `NameError: name 'AsyncSessionLocal' is not defined`
   hatası fırlatır!
4. Satır 131'deki `except Exception as exc:` bloğu tetiklenir:
   `logger.error("[NOTIF WS] DB doğrulama hatası | user_id=%s | %s", user_id, exc, exc_info=True)`
   ve `await websocket.close(code=1011)` çağrılarak bağlantı sonlandırılır!
5. **Sonuç:** Platformdaki hiçbir kullanıcı için bildirim WebSocket'i çalışmamaktadır. Mobil uygulamalar canlı bildirim (yeni beğeni, teklif, takip, DM bildirim sayısı) alamamakta ve sürekli 1011 koduyla yeniden bağlanma döngüsüne girerek Uvicorn'a lüzumsuz TCP el sıkışma yükü bindirmektedir.

#### 2. Çözüm / Refactoring Reçetesi
`backend/app/routers/notifications.py` dosyasının 9. satırındaki import ifadesine `AsyncSessionLocal` eklenmelidir:
```python
from app.database import get_db, AsyncSessionLocal
```
Bu tek satırlık düzeltmeyle tüm canlı bildirim altyapısı anında çalışır hale gelir.

---

### SRE-73 · 🔴 P0 (Kritik) · `bootstrap_node2.sh` İçinde `postgresql-17` Sunucu Paketinin Kurulmaması ve Felaket Kurtarmada PITR Restore Çöküşü

* **Etkilenen Dosyalar:** `deploy/scale/V2.1/scripts/bootstrap_node2.sh` (satırlar 100–104), `deploy/scale/V2.1/node2/resources/scripts/runbook.sh` (satırlar 122, 143–151, 179–183), `deploy/scale/V2.1/documents/01_architecture.md` (satırlar 740–770)
* **İlgili Servis:** `postgresql.service` (Node2 üzerinde)

#### 1. Sorunun Tanımı ve Arıza Modu
Mimari tasarım dokümanı (`01_architecture.md §9.4`) ve felaket kurtarma runbook'u (`runbook.sh`), Node1 çöktüğünde Node2'de PostgreSQL'in ayağa kaldırılmasını, `pg_basebackup` ve `WAL` segmentlerinin bu sunucudaki PostgreSQL'e yüklenip PITR (Point-in-Time Recovery) ile veritabanının promote edilmesini emretmektedir:
```bash
# runbook.sh
cat > /etc/postgresql/17/main/conf.d/recovery.conf <<EOF
restore_command = 'cp ${WAL_DIR}/%f %p'
recovery_target = 'immediate'
EOF
sudo -u postgres touch /var/lib/postgresql/17/main/recovery.signal
systemctl start postgresql
```
Fakat `deploy/scale/V2.1/scripts/bootstrap_node2.sh` scriptine bakıldığında:
```bash
# bootstrap_node2.sh:100-104
install_pg_client() {
    log_step "PostgreSQL client (pg_dump, pg_receivewal)"
    apt-get install -y -qq "postgresql-client-${PG_VERSION}"
    log_ok "pg_client-${PG_VERSION} kuruldu"
}
```
Node2 üzerinde **yalnızca istemci paketi (`postgresql-client-17`)** kurulmaktadır! **`postgresql-17` sunucu paketi HİÇ KURULMAMAKTADIR!**

**Felaket Senaryosu (Disaster Failure):**
1. Node1 donanım arızası veya yangın sebebiyle aniden çöker.
2. SRE / Operatör `ssh node2` yapıp `sudo bash runbook.sh` komutunu çalıştırır.
3. Script satır 143'e geldiğinde:
   `/etc/postgresql/17/main/conf.d/recovery.conf: No such file or directory` hatasıyla patlar çünkü PostgreSQL sunucu dizini sistemde mevcut değildir!
4. Script atlatılsa dahi `systemctl start postgresql` komutu:
   `Failed to start postgresql.service: Unit postgresql.service not found.` döner.
5. Node2'de veritabanı açılamaz, felaket kurtarma planı çöker ve sistem kapalı kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. `bootstrap_node2.sh` scriptine PostgreSQL 17 sunucu paketi kurulumu eklenmelidir:
   ```bash
   install_postgresql_server() {
       log_step "PostgreSQL 17 Server (Standby Recovery Node)"
       apt-get install -y -qq postgresql-17 postgresql-client-17
       systemctl disable --now postgresql
       log_ok "PostgreSQL 17 kuruldu ve standby modda durduruldu"
   }
   ```
2. `/etc/postgresql/17/main/conf.d` dizini oluşturulmalı ve yetkileri `postgres:postgres` yapılmalıdır.
3. Böylece felaket anında `runbook.sh` hazır sunucu üzerinde WAL replay işlemini 2 dakika içinde tamamlayabilir.

> ✅ **Çözüldü** — commit `40c02937`, 2026-10-30

---

### SRE-74 · 🟠 P1 (Yüksek) · `search_alerts.py:delete_alert` İçinde Tanımsız Enum Değeri (`'passive'`) Ataması Nedeniyle HTTP 500 Çökmesi

* **Etkilenen Dosyalar:** `backend/app/routers/search_alerts.py` (satır 103), `backend/app/models/enums.py` (satırlar 22–25), `backend/app/models/search_alert.py` (satır 24)
* **İlgili Endpoint:** `DELETE /api/search-alerts/{alert_id}`

#### 1. Sorunun Tanımı ve Arıza Modu
`app/models/enums.py` dosyasındaki `SearchAlertStatus` enum tanımı şöyledir:
```python
class SearchAlertStatus(str, enum.Enum):
    ACTIVE = "active"
    PAUSED = "paused"
    DELETED = "deleted"
```
Ve `app/models/search_alert.py` modelinde:
```python
status: Mapped[SearchAlertStatus] = mapped_column(
    SQLEnum(SearchAlertStatus, values_callable=lambda obj: [e.value for e in obj]),
    default=SearchAlertStatus.ACTIVE, nullable=False, index=True
)
```
Ancak `backend/app/routers/search_alerts.py` dosyasında kullanıcı alarmını silmek istediğinde (`DELETE /{alert_id}`):
```python
# backend/app/routers/search_alerts.py:103
alert.status = 'passive'  # <-- HATA: 'passive' DİYE BİR ENUM DEĞERİ YOK!
await db.commit()
```
`SearchAlertStatus` enum'unda `'passive'` değeri mevcut değildir (doğru değer `SearchAlertStatus.DELETED` veya `SearchAlertStatus.PAUSED`'dır).

**Arıza Modu:**
Kullanıcı mobil veya web üzerinden bir arama alarmını silmek istediğinde:
1. SQLAlchemy ve PostgreSQL `status` alanına `'passive'` yazmaya çalışırken:
   `LookupError: 'passive' is not among the defined enum values: ['active', 'paused', 'deleted']` veya PostgreSQL `DataError: invalid input value for enum search_alert_status: "passive"` hatası fırlatır.
2. İstek **HTTP 500 Internal Server Error** ile çöker.
3. Kullanıcı arama alarmlarını asla silemez. Limit (5 alarm) dolduğunda yeni alarm da kuramaz.

#### 2. Çözüm / Refactoring Reçetesi
`backend/app/routers/search_alerts.py` satır 103 şu şekilde düzeltilmelidir:
```python
alert.status = SearchAlertStatus.DELETED
await db.commit()
```
Böylece alarm kaydı geçerli enum değeriyle güncellenir ve HTTP 204 No Content başarıyla döner.

---

### SRE-75 · 🟡 P2 (Orta) · `ratings.py:get_ratings` ve `favorites.py:get_favorites` Endpoint'lerinde Sayfalama (Pagination) Eksikliği ve O(N) IN Şişmesi

* **Etkilenen Dosyalar:** `backend/app/routers/ratings.py` (satırlar 235–269), `backend/app/routers/favorites.py` (satırlar 44–65)
* **İlgili Endpoint'ler:** `GET /api/ratings/{user_id}`, `GET /api/favorites`

#### 1. Sorunun Tanımı ve Arıza Modu
1. `GET /api/ratings/{user_id}`:
   ```python
   # backend/app/routers/ratings.py:240
   rows = await db.execute(
       select(Rating, User)
       .join(User, User.id == Rating.rater_id)
       .where(Rating.rated_id == user_id)
       .order_by(Rating.updated_at.desc())
   )
   pairs = rows.all()
   rating_ids = [r.id for r, _ in pairs]
   history_map = await _fetch_history(db, rating_ids)
   ```
   Sorguda herhangi bir `limit` veya `offset` bulunmamaktadır. Popüler bir satıcının 3.000 değerlendirmesi varsa, veritabanından 3.000 satır çekilir; ardından `_fetch_history` içinde:
   `RatingHistory.rating_id.in_(rating_ids)` (3.000 ID'li IN clause) çalıştırılır.
2. `GET /api/favorites`:
   ```python
   # backend/app/routers/favorites.py:46
   rows = (await db.execute(
       select(Listing, User, Favorite)
       .join(Favorite, Favorite.listing_id == Listing.id)
       ...
   )).all()
   listing_ids = [l.id for l, _, _ in rows]
   like_counts, liked_set = await LikeService.batch_listing_likes(db, listing_ids, current_user.id)
   ```
   Yine hiçbir sayfalama yoktur.

**Arıza ve Performans Modu:**
* Binlerce kaydı olan kullanıcılar profil veya favori sayfalarını her açtığında yüz binlerce nesne Python RAM'ine yüklenir (OOM riski).
* `IN (...)` ifadesi asyncpg ve PostgreSQL parametre limitlerini zorlar.
* İstemcilere 10-20 MB büyüklüğünde devasa JSON payload'ları iletilir; mobil cihazlar yanıtı parse ederken kilitlenir.

#### 2. Çözüm / Refactoring Reçetesi
Her iki endpoint'e de zorunlu sayfalama eklenmelidir:
```python
limit: int = Query(20, ge=1, le=50),
offset: int = Query(0, ge=0),
```
Sorgulara `.limit(limit).offset(offset)` eklenmeli; `_fetch_history` ve `batch_listing_likes` yalnızca o sayfadaki en fazla 20-50 kayıt için çağrılmalıdır.

---

### SRE-76 · 🔴 P0 (Kritik) · `read_cache.py:invalidate_cache("user_profile")` ile Global Profil Önbellek Çöküşü (Cache Stampede)

* **Etkilenen Dosyalar:** `backend/app/core/read_cache.py` (satırlar 69–84), `backend/app/routers/follows.py` (satırlar 112, 170, 230, 272), `backend/app/routers/auth.py` (satır 534)
* **İlgili Fonksiyonlar:** `invalidate_cache()`, `follow_user()`, `unfollow_user()`, `accept_follow_request()`, `reject_follow_request()`, `update_me()`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı profil verileri okunurken performans için CQRS Read Cache kullanılmaktadır:
```python
# backend/app/routers/users.py:277
_cache_params = {"username": username, "viewer_id": current_user.id if current_user else 0}
cached = await cache_get("user_profile", _cache_params)
...
await cache_set("user_profile", _cache_params, result, ttl=300)
```
Bu tasarımda anahtarlar `cqrs:user_profile:{hash}` formatında saklanır.
Ancak bir kullanıcı başka birini takip ettiğinde, takipten çıktığında, takip isteğini kabul/red ettiğinde veya profilini güncellediğinde şu kod çalıştırılmaktadır:
```python
# follows.py satır 112, 170, 230, 272
asyncio.create_task(invalidate_cache("user_profile"))
```
Ve `read_cache.py:invalidate_cache` implementasyonu şöyledir:
```python
# backend/app/core/read_cache.py:69
async def invalidate_cache(namespace: str) -> int:
    redis = await get_redis()
    pattern = f"{_PREFIX}:{namespace}:*"  # cqrs:user_profile:*
    keys = [k async for k in redis.scan_iter(pattern)]
    if keys:
        await redis.delete(*keys)
```

**Arıza Modu ve Felaket Senaryosu (Global Cache Stampede):**
1. Sistemde 50.000 aktif kullanıcı varken Redis'te binlerce `cqrs:user_profile:*` anahtarı birikir.
2. Platformdaki **HERHANGİ BİR kullanıcı** başka **HERHANGİ BİR kullanıcıyı** takip ettiğinde (`POST /api/follows/{id}`):
   `invalidate_cache("user_profile")` fonksiyonu tetiklenir ve **TÜM PLATFORMDAKİ TÜM KULLANICILARIN PROFİL CACHE'LERİNİ BİRDEN SİLER!**
3. Takip edilen veya eden kişiyle hiçbir ilgisi olmayan 49.998 kullanıcının önbelleği de anında buharlaşır!
4. O saniyede profilleri gezen tüm mobil/web istemciler Cache Miss yaşar ve eşzamanlı olarak PostgreSQL'e `GetUserProfileQuery` (User, Follows, Listings, Ratings sorguları) bombardımanı yapar.
5. Veritabanı bağlantı havuzu (connection pool) tükenir, yanıt süreleri 20ms'den 5 saniyeye fırlar ve sunucu kilitlenir.
6. Ayrıca `redis.delete(*keys)` ifadesinde binlerce key tek bir komutla silinirken Redis tek iş parçacığı onlarca milisaniye bloklanır.

#### 2. Çözüm / Refactoring Reçetesi
Cache anahtarı namespace düzeyinde değil, **kullanıcı bazlı** ayrıştırılmalıdır:
1. Cache anahtarı formatı `cqrs:user_profile:{target_username}:{viewer_id}` olmalıdır.
2. Takip veya profil güncellemesinde tüm namespace değil, **yalnızca etkilenen kullanıcıların profilleri** temizlenmelidir:
   ```python
   async def invalidate_user_profile_cache(username: str) -> None:
       redis = await get_redis()
       pattern = f"cqrs:user_profile:{username}:*"
       keys = [k async for k in redis.scan_iter(pattern)]
       if keys:
           await redis.delete(*keys)
   ```
3. Böylece bir kullanıcı birini takip ettiğinde sadece o 2 kullanıcının profil cache'i silinir; platformun geri kalan 49.998 kullanıcısının cache'i korunur.

> ✅ **Çözüldü** — commit `2ad08dd4`, 2026-10-30

---

### SRE-77 · 🟠 P1 (Yüksek) · `admin_data.py:admin_send_push` İçinde Senkron Döngüde 10.000 FCM Çağrısı ve Uvicorn Worker Blokajı

* **Etkilenen Dosya:** `backend/app/routers/admin_data.py` (satırlar 651–674)
* **İlgili Endpoint:** `POST /api/admin-data/push/send`

#### 1. Sorunun Tanımı ve Arıza Modu
Admin panelinden tüm kullanıcılara duyuru push bildirimi gönderilmek istendiğinde (`user_id = None`):
```python
# backend/app/routers/admin_data.py:663-673
res = await db.execute(select(User.fcm_token).where(User.fcm_token.isnot(None), User.status == UserStatus.ACTIVE))
tokens = [r[0] for r in res.all() if r[0]]
sent = 0
for token in tokens:
    try:
        await send_push(token=token, title=data.title, body=data.body, notif_type="admin_broadcast")
        sent += 1
    except Exception:
        pass
```
Aktif kullanıcıların tüm FCM token'ları çekilmekte ve **HTTP endpoint'i içerisinde sıralı bir `for` döngüsüyle** tek tek Google Firebase FCM sunucularına HTTP isteği atılmaktadır (`send_push`).

**Arıza Modu:**
1. Platformda 10.000 aktif cihaz token'ı olduğunda, tek bir HTTP isteği içinde 10.000 adet harici HTTPS gidiş-dönüşü (round-trip) yapılır.
2. Her bir FCM HTTPS çağrısı ortalama 150ms sürerse: `10.000 * 0.15s = 1.500 saniye (25 DAKİKA)!`
3. Nginx ters proxy'si 60 saniye sonra `504 Gateway Timeout` vererek istemci bağlantısını koparır.
4. Ancak FastAPI/Uvicorn worker'ı arka planda 25 dakika boyunca tek bir HTTP isteğinin for döngüsünü koşturmaya devam eder; bu worker başka hiçbir API isteğine cevap veremez.
5. Admin arayüzde bildirim gitmedi zannedip butona tekrar bastığında ikinci bir worker daha 25 dakikalık döngüye girer ve tüm Uvicorn iş parçacıkları kilitlenir.

#### 2. Çözüm / Refactoring Reçetesi
1. Toplu bildirim gönderimi derhal HTTP katmanından çıkarılıp ARQ arka plan worker kuyruğuna devredilmelidir:
   ```python
   await arq_pool.enqueue_job("admin_broadcast_push_task", title=data.title, body=data.body)
   return {"status": "queued", "total_targets": len(tokens)}
   ```
2. Worker tarafında bildirimler tek tek değil, Firebase Admin SDK'nın **`messaging.send_each_for_multicast()`** toplu API'si ile 500'lük gruplar halinde (batch) gönderilmelidir. 10.000 bildirim 25 dakika yerine 3 saniyede tamamlanır.

---

### SRE-78 · 🟠 P1 (Yüksek) · `cleaner.py` (teqlif-agent) İçinde Süresi Dolan Hikayelerin DB'den Silinirken MinIO Nesnelerinin Silinmemesi

* **Etkilenen Dosyalar:** `deploy/scale/V2.1/teqlif-agent/modules/cleaner.py` (satırlar 31–33, 111–125), `deploy/scale/V2.1/teqlif-agent/modules/janitor.py` (satır 149)
* **İlgili Tablo:** `stories`

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif-agent` her gece 00:02 UTC'de süresi dolmuş hikayeleri temizlemek için `ScheduledCleaner` çalıştırır:
```python
# cleaner.py satır 31-33
(0,  2,  "stories", "expires_at < NOW()", "Hikayeler")
```
Ve temizlik fonksiyonu doğrudan ham SQL DELETE komutu yürütür:
```python
# cleaner.py satır 115
result = await conn.execute(f"DELETE FROM {table} WHERE {where}")
```
Bu sorguyla süresi dolmuş (24 saatten eski) tüm `stories` satırları PostgreSQL'den silinir.

**Depolama Sızıntısı (Storage Leak Darboğazı):**
* `cleaner.py` MinIO (S3) nesne depolama servisinden tamamen habersizdir; `MinioClient` bağlantısı dahi içermez.
* Hikaye kaydı DB'den silindiğinde, MinIO üzerindeki `stories/{story_id}.mp4` ve `stories/thumbnails/{story_id}.jpg` dosyaları **MinIO bucket'ında silinmeden kalır**.
* DB'de referansı kalmadığı için bu nesneler **kalıcı olarak yetim (orphan blob)** haline gelir.
* Günde ortalama 500 video hikaye paylaşılan bir sistemde, her gün ~5-10 GB yetim video MinIO NVMe diskinde birikir ve aylar içinde sunucu diskini tamamen doldurur (`DiskSpaceLow` alarmı).

#### 2. Çözüm / Refactoring Reçetesi
1. `cleaner.py` doğrudan `DELETE FROM stories` çalıştırmamalıdır.
2. Silme işlemi öncesinde silinecek hikayelerin `video_url` ve `thumbnail_url` bilgileri `SELECT` ile alınmalı; MinIO nesneleri silindikten sonra veya `StoryService.cleanup_expired_stories` ARQ görevi çağrılarak DB + MinIO atomik olarak temizlenmelidir.

---

### SRE-79 · 🟡 P2 (Orta) · `users.py:get_suggested_sellers` İçinde Her İstekte Tüm `follows` Tablosunun Taranması

* **Etkilenen Dosya:** `backend/app/routers/users.py` (satırlar 178–209)
* **İlgili Endpoint:** `GET /api/users/suggested-sellers`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcılara takip etmeleri için satıcı öneren `suggested-sellers` endpoint'i şu SQL sorgusunu çalıştırmaktadır:
```sql
SELECT
    u.id, u.username, ..., COUNT(l.id) AS listing_count,
    COALESCE(fol.follower_count, 0) AS follower_count
FROM users u
INNER JOIN listings l ON l.user_id = u.id AND l.status = 'active'
LEFT JOIN (
    SELECT followed_id, COUNT(*) AS follower_count
    FROM follows GROUP BY followed_id  -- <-- FELAKET BURADA!
) fol ON fol.followed_id = u.id
WHERE u.id != :uid AND u.status = 'active' ...
GROUP BY u.id, ..., fol.follower_count
ORDER BY (...) DESC LIMIT :lim
```

**Veritabanı Performans Felaketi:**
1. `LEFT JOIN (SELECT followed_id, COUNT(*) FROM follows GROUP BY followed_id)` alt sorgusu, **filtresiz olarak tüm `follows` tablosunu baştan sona okur (Seq Scan)** ve tüm satıcıların takipçi sayılarını toplar.
2. 500.000 takip ilişkisi olan bir sistemde, her kullanıcı ana sayfayı açtığında veya profil sekmesine geçtiğinde PostgreSQL yarım milyon satırı gruplayıp RAM'e hash tablo olarak yazar.
3. 20 eşzamanlı mobil kullanıcı bu ekranı açtığında PostgreSQL CPU kullanımı %100'e fırlar ve veritabanı kilitlenir.

#### 2. Çözüm / Refactoring Reçetesi
1. Tüm tabloyu `GROUP BY` yapan alt sorgu kaldırılmalıdır.
2. Takipçi sayısı doğrudan `users` tablosuna `follower_count (INTEGER DEFAULT 0)` denormalize sütun olarak eklenmeli ve follow/unfollow anında `+1/-1` güncellenmelidir.
3. Ya da sadece aday satıcılar seçildikten sonra skaler alt sorgu `(SELECT COUNT(*) FROM follows WHERE followed_id = u.id)` ile yalnızca LIMIT dahilindeki satıcılar için hesaplanmalıdır.

---

### SRE-80 · 🟡 P2 (Orta) · `admin_data.py:admin_delete_listing` İçinde Ardışık Hatalı Atama Nedeniyle İlanın Silinememesi

* **Etkilenen Dosya:** `backend/app/routers/admin_data.py` (satırlar 318–326)
* **İlgili Endpoint:** `DELETE /api/admin-data/listings/{listing_id}`

#### 1. Sorunun Tanımı ve Arıza Modu
Admin panelinden bir ilanın silinmesi için çağrılan fonksiyonda:
```python
# backend/app/routers/admin_data.py:318-326
@router.delete("/listings/{listing_id}")
async def admin_delete_listing(listing_id: int, db: AsyncSession = Depends(get_db), admin: User = Depends(check_admin_access)):
    listing = await db.get(Listing, listing_id)
    if not listing: raise NotFoundException(code="LISTING_NOT_FOUND")
    listing.status = ListingStatus.DELETED
    listing.status = ListingStatus.PASSIVE  # <-- HATA: DELETED ATAMASINI ANINDA EZİYOR!
    await db.commit()
    return {"message": "Listing deleted."}
```
Kod önce `listing.status = ListingStatus.DELETED` atamakta, ancak **hemen bir alt satırda `listing.status = ListingStatus.PASSIVE`** ataması yapmaktadır!

**Mantık ve İş Mantığı Hatası:**
* İlan hiçbir zaman `DELETED` durumuna geçmemektedir; daima `PASSIVE` olarak güncellenmektedir.
* Admin panelinde "İlan silindi" mesajı gösterilmesine rağmen, ilan kullanıcının profilinde pasif ilanlar arasında kalmaya devam eder, arama indekslerinden `DELETED` statüsüyle temizlenemez ve veri tutarsızlığı oluşur.

#### 2. Çözüm / Refactoring Reçetesi
323. satırdaki `listing.status = ListingStatus.PASSIVE` fazlalık satırı silinmeli, ilan doğrudan `ListingStatus.DELETED` olarak bırakılmalı ve arama/feed önbellekleri temizlenmelidir:
```python
listing.status = ListingStatus.DELETED
await db.commit()
from app.services.feed.listing_cache_service import remove_from_recent_feed_cache
await remove_from_recent_feed_cache(listing_id)
```

---

### SRE-81 · 🔴 P0 (Kritik) · `request_withdrawal_command.py` İçindeki SQL Sorgusunun `exchange_rates` Tablosunda Olmayan Sütunları Araması ve Tüm Dövizli Para Çekimlerinin Patlaması

> ✅ **Çözüldü** — Commit `96efef80` · 2026-10-29

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/wallet/commands/request_withdrawal_command.py` (satırlar 103–115)
  * `backend/app/models/market_index.py` (satırlar 6–13)
  * `backend/app/services/tcmb_service.py` (satırlar 38–45)
* **İlgili Endpoint:** `POST /api/wallet/withdraw`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı cüzdanındaki Teqlik bakiyesini USD veya EUR cinsinden banka hesabına çekmek istediğinde (`POST /api/wallet/withdraw`), sistem `request_withdrawal_command.py` satır 104'te güncel TCMB döviz kurunu çekmek için şu ham SQL sorgusunu çalıştırmaktadır:

```python
# backend/app/use_cases/wallet/commands/request_withdrawal_command.py:103-108
rate_row = await self._session.execute(
    text(
        "SELECT rate FROM exchange_rates "
        "WHERE base = 'TRY' AND target = :cur "
        "ORDER BY fetched_at DESC LIMIT 1"
    ),
    {"cur": currency},
)
```

**Veritabanı Şeması Çelişkisi ve Anında Çökme:**
PostgreSQL veritabanındaki `exchange_rates` tablosunun gerçek şeması (`backend/app/models/market_index.py:6-13` ve `tcmb_service.py:38-45`):
```python
class ExchangeRates(Base):
    __tablename__ = "exchange_rates"
    date = Column(Date, primary_key=True)
    usd_try = Column(Float, nullable=False)
    eur_try = Column(Float, nullable=False)
```
1. `exchange_rates` tablosunda `rate`, `base`, `target` veya `fetched_at` adında **HİÇBİR SÜTUN YOKTUR!**
2. Bir kullanıcı USD veya EUR seçerek çekim talebi gönderdiğinde PostgreSQL anında şu hatayı fırlatır:
   ```text
   psycopg2.errors.UndefinedColumn: column "rate" does not exist
   LINE 1: SELECT rate FROM exchange_rates WHERE base = 'TRY' AND target = ...
   ```
3. İstek HTTP 500 Internal Server Error alır; kullanıcı hiçbir zaman döviz cinsinden para çekemez, işlem kilitlenir.
4. Ayrıca `ExchangeRates` modelinde kurlar `1 USD = X TRY` (örneğin 35.50 TRY) olarak saklanmaktadır. Eğer sorgu `rate` alsa dahi, TRY'den USD'ye dönüşüm için `fiat_amount = try_amount / rate` yapılması gerekirken, satır 114'te `fiat_amount = round(try_amount * rate, 2)` yazılmıştır! Bu durum kur bulunsa bile kullanıcının 1.000 TL yerine 35.500 USD çekim talebi oluşturmasına yol açacak devasa bir finansal çarpan hatası barındırmaktadır!

#### 2. Çözüm / Refactoring Reçetesi
1. `request_withdrawal_command.py` içindeki sorgu `ExchangeRates` tablosunun gerçek sütunlarına (`usd_try`, `eur_try`, `date`) göre güncellenmelidir.
2. Döviz tutarı doğru formülle (`try_amount / rate`) hesaplanmalıdır:
```python
if currency == "USD":
    col_name = "usd_try"
elif currency == "EUR":
    col_name = "eur_try"
else:
    raise BadRequestException(code="UNSUPPORTED_CURRENCY")

rate_row = await self._session.execute(
    text(f"SELECT {col_name} FROM exchange_rates ORDER BY date DESC LIMIT 1")
)
row = rate_row.fetchone()
if not row or not row[0]:
    raise BadRequestException(code="EXCHANGE_RATE_NOT_AVAILABLE")

usd_or_eur_per_try_rate = float(row[0])  # Örn: 1 USD = 35.50 TRY
# Fiat tutarı hesapla: TRY tutarı / Döviz Kuru
fiat_amount = round(try_amount / usd_or_eur_per_try_rate, 2)
```

---

### SRE-82 · 🟠 P1 (Yüksek) · `credit_service.py` ve `leads.py` İçinde TOCTOU Yarış Durumu (Race Condition) ile Kullanıcıların Ücretsiz Haklarını Sınırsız Aşabilmesi

* **Etkilenen Dosyalar:**
  * `backend/app/services/credit_service.py` (satırlar 118–176)
  * `backend/app/routers/leads.py` (satırlar 187–322)
  * `backend/app/routers/listings.py` (satırlar 412–440)
* **İlgili Endpoint:** `POST /api/leads/send-blast`, `POST /api/listings/{id}/boost`, `POST /api/listings/generate-description`

#### 1. Sorunun Tanımı ve Arıza Modu
Teqlif platformunda PRO ve Standart kullanıcılara aylık ücretsiz haklar (Blast push bildirimleri, ilan boost, AI açıklama üretimi) tanımlanmaktadır.
Hakların kontrolü ve tüketimi iki ayrı asenkron adımda yapılmaktadır:

```python
# 1. Adım: Kullanım miktarını kontrol et (leads.py:189-190)
used = await credit_service.get_used(CreditFeature.BLAST, current_user.id, current_user.premium_since)
credits_remaining = max(0, limit - used)
...
# 2. Adım: Ağır işler (ClickHouse sorgusu, PG sorguları, FCM hazırlıkları) bittikten sonra sayacı artır (leads.py:320-321)
if free_used > 0:
    await credit_service.increment(CreditFeature.BLAST, current_user.id, current_user.premium_since, count=free_used)
```

**TOCTOU (Time-of-Check to Time-of-Use) Güvenlik Açığı:**
1. Kullanıcının aylık 3 adet ücretsiz blast hakkı olduğunu varsayalım (`limit = 3`, `used = 0`).
2. Kullanıcı/saldırgan aynı anda (100 ms aralıkla) 10 adet paralel `POST /api/leads/send-blast` isteği gönderir.
3. 10 isteğin tamamı `await credit_service.get_used(...)` satırını çalıştırır ve hepsi `used = 0` değerini okur.
4. 10 isteğin tümü `credits_remaining = 3` görür ve kendini "ücretsiz hak" kapsamında yetkilendirir.
5. İşlemler bittiğinde `await credit_service.increment(...)` çağrılır ve Redis sayacı 30'a fırlar; ancak tüm 10 istek de bedavaya gönderilmiş olur!
6. Kullanıcı 3 adetlik aylık hakkı yerine onlarca ücretsiz blast veya boost çalıştırarak şirkete SMS/FCM ve LLM maliyeti yaratır.

#### 2. Çözüm / Refactoring Reçetesi
Kredi kontrolü ve rezervasyonu Redis Lua scripti ile tek bir atomik adımda (Atomic Check-and-Consume) yapılmalıdır:

```lua
-- credit_consume.lua
-- KEYS[1]: credits:{feature}:{user_id}:{period}
-- ARGV[1]: count_to_consume
-- ARGV[2]: free_limit
-- ARGV[3]: ttl_seconds
local current = tonumber(redis.call('GET', KEYS[1]) or '0')
local limit = tonumber(ARGV[2])
local count = tonumber(ARGV[1])

if current >= limit then
    return 0 -- Ücretsiz hak kalmadı
end

local allowed = math.min(count, limit - current)
local new_val = redis.call('INCRBY', KEYS[1], allowed)
if new_val == allowed then
    redis.call('EXPIRE', KEYS[1], tonumber(ARGV[3]))
end
return allowed -- Tüketilen gerçek hak sayısı
```
Router içinde işlem başlamadan önce bu atomik script çalıştırılmalı; scriptin onayladığı kadar miktar (`allowed`) ücretsiz kabul edilmeli, kalanı için TEQlik tahsil edilmelidir.

---

### SRE-83 · 🟠 P1 (Yüksek) · `tcmb_service.py` İçinde Hafta Sonu ve Tatillerde Boş TCMB XML ForexBuying Nedeniyle `AttributeError` ile Güncellemenin Durması

* **Etkilenen Dosya:** `backend/app/services/tcmb_service.py` (satırlar 25–40)
* **İlgili Görev:** `fetch_and_save_tcmb_rates`

#### 1. Sorunun Tanımı ve Arıza Modu
TCMB günlük döviz kurlarını çeken serviste XML verisi ayrıştırılırken şu kod çalıştırılmaktadır:

```python
# backend/app/services/tcmb_service.py:29-33
if code == "USD":
    usd_try = float(currency.find("ForexBuying").text.replace(",", "."))
elif code == "EUR":
    eur_try = float(currency.find("ForexBuying").text.replace(",", "."))
```

**Hafta Sonu / Resmi Tatil Çöküşü:**
1. Hafta sonlarında, resmi tatillerde veya TCMB XML bülteninin henüz yayımlanmadığı sabah saatlerinde `<ForexBuying></ForexBuying>` etiketi boş gelebilir veya `currency.find("ForexBuying")` düğümünün `.text` özelliği `None` döner.
2. `None.replace(",", ".")` çağrıldığında Python anında:
   ```text
   AttributeError: 'NoneType' object has no attribute 'replace'
   ```
   fırlatır.
3. Hata `except Exception as exc:` bloğuna düşer, günlük kur güncellemesi başarısız olur ve veritabanına o günün kurları yazılamaz.
4. Hafta sonu boyunca dövizle çekim yapmak isteyen kullanıcılar `EXCHANGE_RATE_NOT_AVAILABLE` hatası alarak bloke olur.

#### 2. Çözüm / Refactoring Reçetesi
`currency.find("ForexBuying")` düğümünün `text` değeri güvenli biçimde kontrol edilmeli; `ForexBuying` boşsa `BanknoteBuying` etiketine veya en son geçerli iş günü kuruna fallback yapılmalıdır:

```python
def _extract_rate(currency_elem, tag: str = "ForexBuying") -> float | None:
    node = currency_elem.find(tag)
    if node is not None and node.text and node.text.strip():
        try:
            return float(node.text.strip().replace(",", "."))
        except ValueError:
            pass
    return None

usd_rate = _extract_rate(currency, "ForexBuying") or _extract_rate(currency, "BanknoteBuying")
if usd_rate is None:
    # Önceki günün kurunu koru
    prev = await session.scalar(select(ExchangeRates.usd_try).order_by(ExchangeRates.date.desc()).limit(1))
    usd_rate = prev or 35.0
```

---

### SRE-84 · 🟠 P1 (Yüksek) · `relationship_service.py` İçinde Canlı Arama Durumunun (`user_busy`) 1 Saatlik İzin Önbelleğine Yazılarak Aramaların Kilitlenmesi (Cache Poisoning)

* **Etkilenen Dosyalar:**
  * `backend/app/services/relationship_service.py` (satırlar 270–286)
  * `backend/app/services/call_presence.py` (satırlar 47–60)
  * `backend/app/use_cases/messages/queries/get_thread_status_query.py` (satırlar 18–25)
* **İlgili Endpoint:** `GET /api/messages/threads/{thread_id}/status`, `POST /api/calls`

#### 1. Sorunun Tanımı ve Arıza Modu
`RelationshipStateService.recompute_and_cache` fonksiyonu, iki kullanıcı arasındaki takip, mesajlaşma ve arama izinlerini hesaplar ve sonucu Redis'e `rel:{min_uid}:{max_uid}` anahtarıyla **3600 saniye (1 saat) TTL** ile önbelleğe kaydeder.

Ancak satır 270–278'de anlık telefon görüşmesi durumu izin önbelleğine dahil edilmiştir:
```python
# backend/app/services/relationship_service.py:270-279
# Call presence override: hedef aramadaysa can_call → False + user_busy
from app.services.call_presence import is_busy as _is_busy
if state.can_call_ab and await _is_busy(b):
    state.can_call_ab = False
    state.reason_ab = _REASON_USER_BUSY
if state.can_call_ba and await _is_busy(a):
    state.can_call_ba = False
    state.reason_ba = _REASON_USER_BUSY

await RelationshipStateService.cache(state)  # <-- FELAKET: 1 SAAT REDIS'E KİLİTLENİR!
```

**Geçici Durumla Önbellek Zehirlenmesi (Cache Poisoning):**
1. Kullanıcı B, Kullanıcı A ile 20 saniyelik bir telefon görüşmesi yapmaktadır (`is_busy(B) == True`).
2. O anda üçüncü bir kişi olan Kullanıcı C, Kullanıcı B'nin profilini veya mesajlaşma ekranını açar.
3. `GetThreadStatusQuery` çalışır, önbellek olmadığı için `recompute_and_cache(C, B)` fonksiyonunu tetikler.
4. B o anda meşgul olduğu için, `rel:B:C` çifti için `can_call = False` ve `reason = "user_busy"` olarak hesaplanır ve **Redis'e 1 saat boyunca bu şekilde kaydedilir!**
5. Kullanıcı B 10 saniye sonra görüşmesini tamamlar ve kapatır (`clear_presence(B)`).
6. `clear_presence(B)` yalnızca görüşmede olduğu kişiyle (`A`) olan önbelleği geçersiz kılar; çünkü kimlerin B'yi o esnada sorguladığını bilemez!
7. **Sonuç:** Kullanıcı C'nin ekranında Kullanıcı B için `can_call: false (user_busy)` durumu sonraki **59 DAKİKA BOYUNCA** önbellekte kalır! Kullanıcı B boşta olmasına rağmen Kullanıcı C onu arayamaz; arama butonu kilitli kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. Statik ilişki izinleri (takip, engel, mesaj izni) ile canlı meşguliyet durumu (`is_busy`) birbirinden kesin olarak ayrılmalıdır.
2. `RelationshipStateService.recompute_and_cache` ve `cache` fonksiyonlarından `is_busy` kontrolü tamamen kaldırılmalıdır. Önbellekte sadece izinler (`can_call_permission: true/false`) tutulmalıdır.
3. `is_busy` kontrolü, yalnızca kullanıcı aramayı başlatmak üzere butona bastığında (`calls.py:start_call`) veya `GetThreadStatusQuery` endpoint seviyesinde önbellekten okunan statik izin `True` ise anlık Redis sorgusuyla dinamik olarak birleştirilmelidir.

---

### SRE-85 · 🟡 P2 (Orta) · `delete_conversation_command.py` ve `delete_message_command.py` İçinde Silinen Mesajların Okunmamış Rozet Filtresinde Kalarak "Hayalet Rozet" Üretmesi

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/messages/queries/get_unread_count_query.py` (satırlar 11–18)
  * `backend/app/use_cases/messages/commands/delete_conversation_command.py` (satırlar 48–56)
  * `backend/app/use_cases/messages/commands/delete_message_command.py` (satırlar 33–37)
  * `backend/app/services/notification_service.py` (satır 155, 282)
* **İlgili Endpoint:** `GET /api/messages/unread-count`, `GET /api/notifications/badge-counts`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı kendisine gelen okunmamış mesajların bulunduğu bir sohbeti gelen kutusundan sildiğinde (`DeleteConversationCommand`), sohbetin `message_threads.deleted_at_a/b` sütunu güncellenir ve sohbet gelen kutusu listesinden kaybolur. Benzer şekilde tekil mesaj silindiğinde (`DeleteMessageCommand(scope="me")`) `DirectMessage.deleted_for_receiver = True` atanır.
Ancak mesajlar `direct_messages` tablosunda `is_read = False` olarak kalmaya devam eder.

Uygulamanın okunmamış mesaj rozetini (badge count) hesaplayan `GetUnreadCountQuery`:
```python
# backend/app/use_cases/messages/queries/get_unread_count_query.py:11-18
result = await self.uow.session.execute(
    select(func.count()).where(
        DirectMessage.receiver_id == uid,
        DirectMessage.is_read == False,
        DirectMessage.is_shadowbanned == False,
    )
)
```
**Hayalet Okunmamış Rozeti (Ghost Unread Badge):**
1. Bu sorgu, ne `deleted_for_receiver == False` şartını ne de `MessageThread.deleted_at` zaman damgasını kontrol etmektedir!
2. Kullanıcı sohbeti sildiği için gelen kutusunda artık o sohbeti ve mesajları göremez. Dolayısıyla mesajı açıp "okundu" (`is_read = True`) yapması imkansızdır.
3. Ancak veritabanı sorgusu silinen o mesajları saymaya devam eder.
4. **Kullanıcı Deneyimi Bozulması:** Mobil uygulamanın mesaj ikonu ve iOS/Android uygulama rozeti üzerinde sürekli "3 okunmamış mesaj" bildirimi kalır; kullanıcı gelen kutusunu açtığında hiçbir okunmamış mesaj göremez ve bu rozeti temizleyemez.

#### 2. Çözüm / Refactoring Reçetesi
1. `DeleteConversationCommand` içinde sohbet silinirken, o kullanıcıya gelen tüm okunmamış mesajlar da `is_read = True` olarak güncellenmelidir:
```python
await self.uow.session.execute(
    update(DirectMessage).where(
        DirectMessage.receiver_id == uid,
        DirectMessage.sender_id == other_user_id,
        DirectMessage.is_read == False,
    ).values(is_read=True)
)
```
2. `GetUnreadCountQuery` ve `notification_service.py` içindeki rozet sorgularına `DirectMessage.deleted_for_receiver == False` filtresi eklenmelidir.

---

### SRE-86 · 🟠 P1 (Yüksek) · Kampanya Duraklatma ve Bütçe Bitişinde `ad_campaigns:active` Setinden `SREM` Yapılmaması (Dead Ad Slot Bloat)

* **Etkilenen Dosyalar:**
  * `backend/app/services/ad_service.py` (satırlar 171–196, 199–226)
  * `backend/app/use_cases/feed/queries/feed_queries.py` (satırlar 1101–1132)
* **İlgili Endpoint:** `POST /api/ads/campaigns/{id}/pause`, `POST /api/ads/click`, `GET /api/feed`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı bir reklam kampanyası başlattığında `ad_service.py` bu kampanyayı Redis'e iki aşamada kaydeder:
1. `ad_campaign_budget:{id}` ve `ad_campaign_cpc:{id}` anahtarları oluşturulur.
2. Kampanya ID'si aktif havuza eklenir: `pipe.sadd("ad_campaigns:active", str(campaign_id))`.

Ancak kampanya satıcı tarafından duraklatıldığında (`pause_campaign`) veya tıklama sonucu bütçesi tükendiğinde (`record_ad_click`), `ad_service.py` yalnızca anahtarları silmektedir:
```python
# backend/app/services/ad_service.py:188-193 (pause_campaign)
async with redis.pipeline() as pipe:
    pipe.delete(f"ad_campaign_budget:{campaign_id}")
    pipe.delete(f"ad_campaign_cpc:{campaign_id}")
    await pipe.execute()
    # <-- HATA: pipe.srem("ad_campaigns:active", str(campaign_id)) UNUTULMUŞTUR!
```
Benzer şekilde `record_ad_click` içinde bütçe tükendiğinde de `pipe.srem` çalıştırılmamaktadır.

**Ölü Slotların Aktif Reklamları Tıkaması (Dead Ad Slot Bloat):**
Kullanıcılar keşfet akışını gezerken reklam seçimi yapan `feed_queries.py`:
```python
# backend/app/use_cases/feed/queries/feed_queries.py:1103-1111
raw_ids = await redis.smembers("ad_campaigns:active")
if not raw_ids:
    return []
sample_ids = [int(i) for i in list(raw_ids)[:50]]  # İlk 50 adayı al
candidates = (await session.execute(
    select(AdCampaign).where(AdCampaign.id.in_(sample_ids), AdCampaign.status == "active")
)).scalars().all()
```
1. Duraklatılan veya bütçesi tükenen her kampanya `ad_campaigns:active` Set'inde **sonsuza kadar kalmaya devam eder.**
2. Sistemde zaman içinde 50 kampanya duraklatıldığında veya bütçesini tamamladığında, `list(raw_ids)[:50]` listesi tamamen bu pasif kampanyalarla dolar.
3. SQL sorgusu `WHERE status == 'active'` koşulu koyduğu için bu 50 ID'nin hiçbiri dönmez (`candidates = []`).
4. **Felaket Etkisi:** Sistemde yeni bütçe yüklemiş yüzlerce gerçek aktif kampanya bulunmasına rağmen, Set'in ilk 50 sırası ölü kayıtlarla tıkandığı için akışta hiçbir kullanıcıya reklam gösterilemez (`Sponsored` ilanlar yok olur). Şirket ciro ve reklam geliri kaybına uğrar.

#### 2. Çözüm / Refactoring Reçetesi
1. `backend/app/services/ad_service.py` içinde `pause_campaign`, `cancel_campaign` ve `record_ad_click` (bütçe bittiğinde) bloklarına `pipe.srem("ad_campaigns:active", str(campaign_id))` satırı eklenmelidir.
2. `feed_queries.py` içinde `sample_ids` rastgele örneklenmeli (`random.sample(..., min(len(raw_ids), 50))`) ve veritabanında pasif olduğu tespit edilen ID'ler arka planda `srem` ile setten temizlenmelidir (self-healing cache).

---

### SRE-87 · 🟠 P1 (Yüksek) · Süresi Dolan İlanlar Pasife Alınırken Redis Feed ve İlan Cache'inin Temizlenmemesi (Desynchronized Zombie Feed)

* **Etkilenen Dosyalar:**
  * `backend/app/tasks/listing_tasks.py` (satırlar 66–73)
  * `backend/app/services/feed/listing_cache_service.py` (satırlar 77–126)
  * `backend/app/routers/feed.py` (satırlar 103–131)
* **Zamanlama:** `schedule.yaml` / ARQ: Her gün 04:00 UTC (`deactivate_expired_listings_task`)

#### 1. Sorunun Tanımı ve Arıza Modu
Platformda 30 gün boyunca satılmayan veya güncellenmeyen ilanlar her sabah 04:00'te çalışan `deactivate_expired_listings_task` göreviyle toplu olarak pasife alınır:
```python
# backend/app/tasks/listing_tasks.py:66-73
await db.execute(
    update(Listing)
    .where(Listing.id.in_(expired_ids))
    .values(status=ListingStatus.PASSIVE, deactivated_at=now)
)
await db.commit()
```
Ancak bu görev, `listing_cache_service.py` içindeki önbellek temizleme fonksiyonlarını **kesinlikle çağırmamaktadır**:
1. `feed:recent` ZSet yapısından ilan ID'leri silinmemektedir (`remove_from_recent_feed_cache(lid)` çağrılmıyor).
2. `listing:{id}` Redis anahtarı (7 günlük TTL'e sahip zengin ilan JSON'u) geçersiz kılınmamaktadır (`invalidate_listing(lid)` çağrılmıyor).

**Zombi İlan Akışı (Desynchronized Zombie Feed):**
1. Mobil kullanıcı sabah uygulamayı açtığında feed doğrudan Redis'ten (`feed:recent` ve `listing:{id}`) beslenir.
2. Kullanıcının akışında 04:00'te pasife alınmış yüzlerce zombi ilan "Aktif" ve "Satılık" olarak listelenmeye devam eder.
3. Kullanıcı ilana tıkladığında veya "Teklif Ver / Satın Al" butonuna bastığında API veritabanına gider; veritabanında `status == 'passive'` olduğu için işlem 400 Bad Request / "İlan yayında değil" hatasıyla patlar.
4. Kullanıcı deneyimi ciddi şekilde zarar görür, sahte ilan izlenimi oluşur.

#### 2. Çözüm / Refactoring Reçetesi
`deactivate_expired_listings_task` fonksiyonunda `await db.commit()` sonrasında süresi dolan tüm ID'ler Redis pipeline ile temizlenmelidir:
```python
from app.services.feed.listing_cache_service import invalidate_listing, remove_from_recent_feed_cache
for lid in expired_ids:
    await remove_from_recent_feed_cache(lid)
    await invalidate_listing(lid)
```

---

### SRE-88 · 🟡 P2 (Orta) · `teqlif-agent` İçinde Asenkron Event Loop'ta Senkron `time.sleep(1)` ile Agent Kilitlenmesi

* **Etkilenen Dosya:** `deploy/scale/V2.1/teqlif-agent/modules/health.py` (satırlar 257–330)
* **Bileşen:** Node 1–6 üzerinde çalışan `teqlif-agent` donanım ve sağlık izleme servisi

#### 1. Sorunun Tanımı ve Arıza Modu
`teqlif-agent`, her 5 saniyede bir CPU, RAM, disk ve ağ metriklerini toplayarak Redis'e ve UDP gossip ağına raporlar.
`modules/health.py` satır 257'de donanım metrikleri toplanırken `_net_mbps()` çağrılır:
```python
# deploy/scale/V2.1/teqlif-agent/modules/health.py:320-330
def _net_mbps() -> dict:
    ...
    # İki örneklem arasındaki farkı ölçmek için 1 saniye beklenir:
    time.sleep(1)  # <-- FELAKET: SENKRON VE BLOKLAYICI!
    ...
```
**Asenkron Event Loop'un Dondurulması:**
1. `teqlif-agent` tek bir Python iş parçacığı (single-threaded asyncio event loop) üzerinde çalışır.
2. `time.sleep(1)` çağrıldığında, işletim sistemi seviyesinde tüm Python süreci 1 tam saniye boyunca dondurulur (CPU yield olmadan blokaj).
3. Bu 1 saniyelik kör noktada:
   * Diğer node'lardan gelen UDP gossip sağlık paketleri alınamaz (UDP socket buffer taşması ve paket kaybı).
   * Watchdog timer ve systemd heartbeat ping'leri aksar.
   * `edge_orchestrator` bu gecikmeyi "node yanıt vermiyor / sağlıksız" sanarak sahte failover tetikleyebilir.
4. Agent çalışma süresinin %20'sini (her 5 saniyenin 1 saniyesini) tamamen kilitli geçirir.

#### 2. Çözüm / Refactoring Reçetesi
1. Senkron `time.sleep(1)` derhal kaldırılmalıdır.
2. Anlık uyku yerine, iki ölçüm arasındaki süre önceki metrik döngüsünden saklanan zaman damgasıyla (`delta_t = now - last_time`) ve arayüz bayt farkıyla hesaplanmalıdır:
```python
_last_net_bytes = 0
_last_net_time = 0.0

def _get_net_mbps_nonblocking(current_bytes: int, now: float) -> float:
    global _last_net_bytes, _last_net_time
    if _last_net_time == 0.0:
        _last_net_bytes, _last_net_time = current_bytes, now
        return 0.0
    dt = now - _last_net_time
    mbps = ((current_bytes - _last_net_bytes) * 8) / (dt * 1_000_000)
    _last_net_bytes, _last_net_time = current_bytes, now
    return round(max(0.0, mbps), 2)
```

---

### SRE-89 · 🔴 P0 (Kritik) · `start_call` İçinde Tek Taraflı Callee Lock Nedeniyle Simetrik Arama Çakışması (Glare) ve Ayrık Odalar (Split Rooms)

* **Etkilenen Dosya:** `backend/app/routers/calls.py` (satırlar 619–645)
* **İlgili Endpoint:** `POST /api/calls/start`

#### 1. Sorunun Tanımı ve Arıza Modu
`calls.py` içinde iki kullanıcının aynı anda aranmasını engellemek için PostgreSQL advisory lock kullanılmıştır:
```python
# backend/app/routers/calls.py:624
await db.execute(text("SELECT pg_advisory_xact_lock(42, :cid)"), {"cid": callee_id})
```
Buradaki kritik güvenlik ve mantık açığı, kilidin **yalnızca `callee_id` (aranan kişi) üzerine alınmasıdır.**

**Simetrik Arama Çakışması (Symmetric Glare & Split Rooms):**
1. Kullanıcı A ve Kullanıcı B, aynı anda birbirlerini aramak üzere "Ara" butonuna basar (mobil uygulamalarda çok sık görülen bir durumdur).
2. İstek 1 (A -> B): `pg_advisory_xact_lock(42, B)` kilidini alır. B'nin aktif araması olmadığı görülür.
3. İstek 2 (B -> A): `pg_advisory_xact_lock(42, A)` kilidini alır. A'nın aktif araması olmadığı görülür.
4. **İki kilit farklı anahtarlarda olduğu için birbirini asla engellemez!** Her iki işlem de `status = 'calling'` olan iki farklı `Call` satırı üretir:
   * Arama 1: `room_name = "call_A_B_..._1111"`
   * Arama 2: `room_name = "call_B_A_..._2222"`
5. Her iki kullanıcının da telefonu aynı anda çalar.
6. A kullanıcısı gelen aramayı kabul ettiğinde ODA 2'ye bağlanır; B kullanıcısı gelen aramayı kabul ettiğinde ODA 1'e bağlanır.
7. **Sonuç:** İki kullanıcı tamamen farklı iki LiveKit odasında tek başlarına otururlar! Karşı tarafın sesi gelmez; sistemde "hayalet arama" ve tam bir sessizlik/çökme yaşanır.
8. Ayrıca kötü niyetli bir kullanıcı, aynı anda 10 farklı kişiye paralel istek atarak çoklu arama (multicall DoS) başlatabilir çünkü arayan kişinin (`caller_id`) eşzamanlı istekleri hiçbir kilit tarafından sınırlandırılmamaktadır.

#### 2. Çözüm / Refactoring Reçetesi
Arama işlemlerinde kilit, tekil bir katılımcı yerine sıralı ikili (`min(id), max(id)`) üzerine alınmalı veya hem arayan hem aranan kişi sırayla kilitlenmelidir:
```python
u1 = min(current_user.id, callee_id)
u2 = max(current_user.id, callee_id)
# Küçük ID sonra büyük ID kilitlenerek Deadlock (40P01) tamamen önlenir:
await db.execute(
    text("SELECT pg_advisory_xact_lock(42, :u1), pg_advisory_xact_lock(42, :u2)"),
    {"u1": u1, "u2": u2}
)
```
Böylece A ve B birbirini aynı anda aradığında ikinci gelen istek ilkinin commit olmasını bekler; commit sonrasında veritabanında aktif çağrı (`caller_busy` / `active_call`) tespit edilerek ikinci çağrı anında `409 Conflict (USER_BUSY)` ile reddedilir.

> ✅ **Çözüldü** — `calls.py:624` `min(current_user.id, callee_id), max(...)` canonical çift kilidi önceden uygulanmış; damga eklendi. 2026-10-30

---

### SRE-90 · 🟠 P1 (Yüksek) · `calls.py` ve `webhooks.py` İçinde Grup Katılımcılarına Kapanışın Bildirilmemesi ve Webhook'ta `clear_presence` Eksikliği (Stuck Presence)

* **Etkilenen Dosyalar:**
  * `backend/app/routers/calls.py` (satırlar 940–1010)
  * `backend/app/routers/webhooks.py` (satırlar 73–110)
  * `backend/app/services/call_presence.py` (satırlar 47–60)
* **İlgili Endpoint:** `POST /api/calls/{id}/end`, LiveKit Webhook `room_finished`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Grup Katılımcılarının Askıda Kalması:**
   Platformda bir 1-on-1 arama `POST /api/calls/{call_id}/invite` ile grup aramasına dönüştürüldüğünde davetli misafirler `CallParticipant` tablosuna ve Redis `call:{id}:participants` setine eklenir.
   Ancak aramayı başlatan kişi aramayı sonlandırdığında (`POST /api/calls/{call_id}/end`), satır 989'da:
   ```python
   # backend/app/routers/calls.py:989
   await _ws_broadcast(other_id, {"type": ws_type, "call_id": call_id_val})
   ```
   Bildirim **yalnızca** orijinal eşe (`other_id`) gönderilmektedir! Davet edilmiş olan diğer tüm katılımcılara hiçbir WebSocket bildirimi gitmez, `CallParticipant` kayıtları veritabanında `joined` durumunda kalır. Misafirlerin mobil ekranlarında arama açık kalır, LiveKit odası silindiğinde ise beklenmedik bağlantı kopması hatası alırlar.
2. **Webhook Kapanışında `clear_presence` Çağrılmaması:**
   Arama normal şekilde API'den değil de, katılımcıların uygulamayı kapatması/düşmesi sonucu LiveKit odasının boşalıp kapanmasıyla bittiğinde `webhooks.py:_on_call_room_finished` çalışır.
   Bu fonksiyonda `call.status = 'ended'` yapılır ve commit edilir; ancak **`clear_presence(caller_id)` ve `clear_presence(callee_id)` ASLA ÇAĞRILMAMAKTADIR!**
3. **10 Dakikalık Meşgul Kilitlenmesi:**
   `call_presence.py` dosyasında `_PRESENCE_TTL = 600` (10 dakika) olarak tanımlıdır. Webhook kapanışında presence temizlenmediği için, hem arayan hem aranan kullanıcı Redis'te sonraki 10 dakika boyunca `is_busy: true` olarak kalır! Bu süre zarfında kimse bu kullanıcıları arayamaz (arama butonları `user_busy` diyerek kilitlenir).

#### 2. Çözüm / Refactoring Reçetesi
1. `calls.py:end_call` içinde `broadcast_to_call_participants(call_id_val, {"type": "call_ended", "call_id": call_id_val})` çağrılmalı ve tüm `CallParticipant` kayıtları `status = 'ended'` yapılmalıdır.
2. `webhooks.py:_on_call_room_finished` içine `clear_presence` ve `clear_call_redis` çağrıları eklenmelidir:
```python
await clear_presence(caller_id)
await clear_presence(callee_id)
await clear_call_redis(call_id)
```

---

### SRE-91 · 🟠 P1 (Yüksek) · `refresh_stream_token.py` İçinde `resolve_stream_endpoint` Çağrılmayarak İzleyicilerin Relay'den Atılması ve Origin Yığılması

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/streams/queries/refresh_stream_token.py` (satırlar 33–67)
  * `backend/app/services/edge_orchestrator.py` (satırlar 94–115)
  * `backend/app/use_cases/streams/commands/join_stream.py` (satırlar 38–45)
* **İlgili Endpoint:** `GET /api/streams/{id}/token`

#### 1. Sorunun Tanımı ve Arıza Modu
Platformda popüler bir canlı yayın başladığında izleyici sayısı arttıkça `edge_orchestrator`, yükü kaynak (origin) node'dan dağıtmak için bir Relay node'u tahsis eder (`live:relay:ready:{room_name}`).
Kullanıcı yayına ilk katıldığında `JoinStreamCommand`:
```python
# backend/app/use_cases/streams/commands/join_stream.py:38
endpoint = await orchestrator.resolve_stream_endpoint(stream)
token = make_livekit_token(endpoint["room_name"], user, can_publish=False)
```
kodunu çalıştırır ve izleyiciyi doğru şekilde Relay node'una (`relay_url` ve `relay_room`) bağlar.

Ancak LiveKit token'larının süresi dolduğunda veya mobil istemci bağlantı yenilediğinde çağrılan `RefreshStreamTokenQuery`:
```python
# backend/app/use_cases/streams/queries/refresh_stream_token.py:52-64
token = make_livekit_token(stream.room_name, current_user, can_publish=is_publisher)
return StreamTokenOut(
    stream_id=stream.id,
    room_name=stream.room_name,        # <-- FELAKET: HARDCODED ORIGIN!
    livekit_url=stream.livekit_url,    # <-- FELAKET: HARDCODED ORIGIN!
    token=token,
    ...
)
```
`orchestrator.resolve_stream_endpoint` metodunu **tamamen atlamakta** ve izleyiciye doğrudan kaynak node'un URL'ini ve odasını vermektedir!

**Relay Mimarisinin Çökmesi ve Kaynak Node Yığılması:**
1. 1.000 izleyicili bir yayında izleyiciler başarıyla relay node'larına dağıtılmıştır.
2. 15-20 dakika sonra izleyicilerin token yenileme zamanı geldiğinde mobil uygulamalar `GET /api/streams/{id}/token` çağrısı yapar.
3. `RefreshStreamTokenQuery`, 1.000 izleyicinin tamamına relay yerine **kaynak sunucu (node3/origin)** bilgilerini döner.
4. Yüzlerce izleyici aniden kaynak sunucuya hücum eder; kaynak sunucunun bant genişliği ve CPU'su kilitlenir, yayıncının yayını kopar ve relay sistemi tamamen işlevsiz hale gelir.

#### 2. Çözüm / Refactoring Reçetesi
`RefreshStreamTokenQuery.execute` içinde yayıncı olmayan (`not is_publisher`) kullanıcılar için `resolve_stream_endpoint` kullanılmalıdır:
```python
room_name = stream.room_name
livekit_url = stream.livekit_url
if not is_publisher:
    from app.services.edge_orchestrator import orchestrator
    endpoint = await orchestrator.resolve_stream_endpoint(stream)
    room_name = endpoint["room_name"]
    livekit_url = endpoint["livekit_url"]

token = make_livekit_token(room_name, current_user, can_publish=is_publisher)
return StreamTokenOut(
    stream_id=stream.id,
    room_name=room_name,
    livekit_url=livekit_url,
    token=token,
    category=stream.category,
    video_quality_profile=quality_profile,
)
```

---

### SRE-92 · 🟡 P2 (Orta) · `chat_commands.py` İçinde Bağımsız `INCR/DECR` ile İzleyici Sayacı Bozulması ve `live:viewer_set` TTL'siz RAM Sızıntısı

* **Etkilenen Dosya:** `backend/app/use_cases/chat/commands/chat_commands.py` (satırlar 146–177)
* **İlgili Metotlar:** `add_viewer`, `remove_viewer`

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın izleyici sayısını takip etmek için Redis'te iki yapı paralel kullanılmaktadır:
1. `live:viewer_set:{stream_id}` (Set: o yayındaki tekil kullanıcı adları)
2. `live:viewers:{stream_id}` (Integer sayaç: anlık sayı)

`chat_commands.py` içindeki implementasyon:
```python
# backend/app/use_cases/chat/commands/chat_commands.py:149-153
await redis.sadd(f"live:viewer_set:{stream_id}", username)
key = f"live:viewers:{stream_id}"
count = await redis.incr(key)
await redis.expire(key, _VIEWER_TTL)
```
**1. Desenkronizasyon ve Yapay Sayaç Şişmesi:**
`redis.sadd` komutu kullanıcı kümede zaten varsa `0`, yeni eklendiyse `1` döner. Ancak kod dönen değeri **asla denetlemeden** her WebSocket bağlantısında `redis.incr(key)` çalıştırmaktadır.
Mobil bir kullanıcı zayıf hücresel ağda 10 kez bağlantı koparıp yeniden bağlandığında, izleyici sayısı 1 iken sayaç 11'e fırlar! Kullanıcı yayından çıktığında ise tek bir `decr` çalışır; sayaç 10 izleyicide asılı kalır.

**2. TTL Eksikliği ve Redis RAM Sızıntısı:**
`live:viewers:{stream_id}` anahtarına `expire` verilirken, `live:viewer_set:{stream_id}` anahtarına **HİÇBİR ZAMAN EXPIRE VERİLMEMEKTEDİR!**
Yayın olağan dışı kapandığında veya worker çöktüğünde binlerce kullanıcı adını içeren bu Set yapıları Redis belleğinde öksüz (orphan) kalarak kalıcı bellek sızıntısına yol açar.

#### 2. Çözüm / Refactoring Reçetesi
1. Sayaç artırımı, yalnızca `sadd` yeni bir eleman eklediyse (`added == 1`) yapılmalı veya doğrudan O(1) maliyetli `SCARD` komutu kullanılmalıdır:
```python
added = await redis.sadd(f"live:viewer_set:{stream_id}", username)
await redis.expire(f"live:viewer_set:{stream_id}", _VIEWER_TTL)
if added:
    count = await redis.incr(f"live:viewers:{stream_id}")
else:
    count = int(await redis.get(f"live:viewers:{stream_id}") or 1)
```
2. Ya da daha temiz bir mimariyle `live:viewers:{stream_id}` yerine tek kaynak olarak doğrudan `await redis.scard(f"live:viewer_set:{stream_id}")` kullanılmalıdır.

---

### SRE-93 · 🟠 P1 (Yüksek) · `firebase_adapter.py` İçinde Sözde Multicast ve Sıralı Senkron HTTP ile Kritik ARQ Kuyruğunun 25 Dakika Kilitlenmesi

* **Etkilenen Dosyalar:**
  * `backend/app/infrastructure/adapters/firebase_adapter.py` (satırlar 172–220)
  * `backend/app/worker.py` (satırlar 213–265)
  * `backend/app/use_cases/streams/stream_utils.py` (satırlar 98–118)
* **İlgili Görev:** `send_stream_started_notifications` (ARQ kuyruğu: `_queue_name="critical"`)

#### 1. Sorunun Tanımı ve Arıza Modu
Yayıncı canlı yayını başlattığında tüm takipçilerine bildirim göndermek için `notify_followers_task` tetiklenir ve bu işlem ARQ'nun en öncelikli kuyruğu olan `critical` kuyruğuna `send_stream_started_notifications` olarak eklenir.
`worker.py`, takipçilerin FCM token'larını toplayıp `push_port.send_multicast(tokens, ...)` çağırır.
Metot başlığında `FCM V1 multicast — her 500 token'a bir toplu HTTP döngüsü` yazmaktadır.

Ancak `firebase_adapter.py` içindeki gerçek implementasyon şöyledir:
```python
# backend/app/infrastructure/adapters/firebase_adapter.py:207-217
def _send_multicast_batch(self, tokens: list[str], ...):
    ...
    for token in tokens:
        msg = self._build_message(token, ...)
        resp = session.post(url, json={"message": msg}, timeout=30)  # <-- FELAKET!
```
**Sıralı Senkron HTTP Döngüsü ve Kritik Kuyruk Felci:**
1. Fonksiyon gerçek bir multicast (toplu paket) göndermemektedir. Bunun yerine **her bir takipçi için Google FCM sunucularına tek tek, sıralı ve senkron HTTP POST isteği atmaktadır!**
2. Google FCM sunucularına tek bir TLS HTTP/1.1 isteği ortalama 120–180 ms sürer.
3. 2.000 takipçisi olan bir yayıncı canlı yayın başlattığında:
   `2.000 token * 0.150 sn = 300 saniye (5 DAKİKA KİLİTLENME)`
4. 10.000 takipçisi olan bir yayıncıda:
   `10.000 token * 0.150 sn = 1.500 saniye (25 DAKİKA KİLİTLENME)`
5. Bu görev `_queue_name="critical"` üzerinde çalıştığı için, o worker 25 dakika boyunca başka hiçbir iş yapamaz!
6. **Sistem Genelinde Zincirleme Çöküş:** Kritik kuyrukta bekleyen arama zaman aşımları (`delayed_call_timeout_task`), canlı yayın kapanış kontrolleri (`delayed_close_stream_task`) ve acil durum bildirimleri 25 dakika boyunca bekletilir ve işlenemez.

#### 2. Çözüm / Refactoring Reçetesi
1. Firebase Admin SDK'nın resmi toplu gönderim metodu olan `messaging.send_each_for_multicast(messages)` kullanılmalıdır (tek HTTP bağlantısında 500 mesajı paketler).
2. Ya da `aiohttp` ile asenkron HTTP istemcisi üzerinden sınırlı bir eşzamanlılık havuzuyla (`asyncio.Semaphore(50)`) paralel gönderim yapılmalıdır; böylece 10.000 bildirim 25 dakikada değil, 3–4 saniyede tamamlanır.
3. Yayın başlangıç bildirimleri `critical` kuyruğundan alınıp düşük öncelikli `notifications` veya `bulk` kuyruğuna taşınmalıdır.

---

### SRE-94 · 🔴 P0 (Kritik) · Para Çekim İptalinde Eksik `FOR UPDATE` ile Çift İade ve Çekim-İptal Yarışı (Double Refund & Free Cash Exploit)

> ✅ **Çözüldü** — Commit `b4290d35` · 2026-10-29

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/wallet/commands/cancel_withdrawal_request_command.py` (satırlar 19–55)
  * `backend/app/use_cases/wallet/commands/process_withdrawal_command.py` (satırlar 36–62)
* **İlgili Endpoint:** `DELETE /api/wallet/withdraw/{request_id}`, `POST /api/admin-data/wallet/withdrawals/{request_id}/process`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı çekim talebini iptal etmek istediğinde çalışan `CancelWithdrawalRequestCommand`:
```python
# backend/app/use_cases/wallet/commands/cancel_withdrawal_request_command.py:19-27
row = await self._session.execute(
    text("SELECT user_id, teqlik_amount, status FROM withdrawal_requests WHERE id = :rid"),
    {"rid": request_id},
)
...
if status != "pending":
    raise ConflictException(code="WITHDRAWAL_NOT_CANCELLABLE")

await self._session.execute(
    text("UPDATE user_wallet_earnings SET available = available + :amt WHERE user_id = :uid"),
    {"amt": teqlik_amount, "uid": user_id},
)
await self._session.execute(
    text("UPDATE withdrawal_requests SET status = 'cancelled' WHERE id = :rid"),
    {"rid": request_id},
)
```
Benzer şekilde adminin çekimi onaylayıp reddettiği `ProcessWithdrawalCommand` içinde de `SELECT id, user_id, teqlik_amount, status FROM withdrawal_requests WHERE id = :rid` sorgusu **satır kilidi (`FOR UPDATE`) olmadan çalışmaktadır.**

**İki Büyük Finansal İstismar Senaryosu:**

1. **Paralel İptal ile Bakiyeyi İkiye/Üçe Katlama (Double Refund):**
   * Kullanıcı 1.000 Teqlik (500 TL) tutarında bir çekim talebi açar.
   * Kullanıcı aynı anda iki paralel HTTP isteği gönderir: `DELETE /api/wallet/withdraw/{request_id}`.
   * `SELECT` sorgusu kilitsiz olduğu için her iki transaction da `status == 'pending'` okur.
   * İstek 1: `available += 1000` ve `status = 'cancelled'` yapar.
   * İstek 2: `available += 1000` ve `status = 'cancelled'` yapar.
   * Her iki transaction da commit olur!
   * **Sonuç:** Kullanıcı 1.000 Teqlik çekim istemişken hesabına **2.000 Teqlik iade edilir!** Eşzamanlı 5 istek atıldığında bakiye 5 katına çıkarılır. Kullanıcı platformun tüm parasını saniyeler içinde karşılıksız çoğaltabilir.

2. **Nakit Para + İade Edilmiş Bakiye Çift Kazanımı (Approval-Cancel Race):**
   * Admin panelinde admin kullanıcı için banka havalesini hazırlar ve `action="approve"` butonuna basar.
   * Tam o milisaniyede kullanıcı mobil uygulamadan çekim talebini iptal eder (`cancel`).
   * Kullanıcının isteği: `available += 1000` yaparak bakiyeyi cüzdana iade eder.
   * Adminin isteği: `status = 'approved'` yapar ve muhasebe banka üzerinden kullanıcının IBAN'ına gerçek nakit parayı transfer eder.
   * **Sonuç:** Kullanıcı hem gerçek nakit parayı banka hesabına alır hem de platformdaki 1.000 Teqlik bakiyesini geri kazanır. Şirket doğrudan nakit para kaybına uğrar.

#### 2. Çözüm / Refactoring Reçetesi
1. Hem `CancelWithdrawalRequestCommand` hem de `ProcessWithdrawalCommand` içinde `withdrawal_requests` kaydı kesinlikle `FOR UPDATE` ile kilitlenmelidir:
```python
row = await self._session.execute(
    text("SELECT user_id, teqlik_amount, status FROM withdrawal_requests WHERE id = :rid FOR UPDATE"),
    {"rid": request_id},
)
```
2. Güncelleme sorguları mutlaka atomik koşul (`WHERE id = :rid AND status = 'pending'`) içermeli ve dönen satır sayısı kontrol edilmelidir:
```python
upd = await self._session.execute(
    text(
        "UPDATE withdrawal_requests "
        "SET status = 'cancelled', cancelled_at = NOW() "
        "WHERE id = :rid AND status = 'pending' RETURNING id"
    ),
    {"rid": request_id},
)
if upd.fetchone() is None:
    raise ConflictException(code="WITHDRAWAL_ALREADY_PROCESSED")
```
Satır güncellenememişse `user_wallet_earnings` bakiye iadesi kesinlikle yapılmamalıdır.

---

### SRE-95 · 🟠 P1 (Yüksek) · Sistem Hesabının (id=0) `teqlik_balance`'ının Güncellenmemesi ve Defter (Ledger) Tutarsızlığı

* **Etkilenen Dosyalar:**
  * `backend/app/use_cases/wallet/commands/convert_to_teqlik_command.py` (satırlar 60–91)
  * `backend/app/use_cases/wallet/commands/send_gift_command.py` (satırlar 173–190)
  * `backend/app/models/wallet_ledger.py`

#### 1. Sorunun Tanımı ve Arıza Modu
Platformda çift taraflı defter (double-entry bookkeeping) tutulmaktadır. Sistem tarafından kesilen komisyonlar (`platform_revenue`) ve verilen bonuslar (`bonus_mint`), sistem kullanıcısına (`user_id = 0`) yazılır.

`SendGiftCommand` satır 174–189 ve `ConvertToTeqlikCommand` satır 78–90:
```python
# backend/app/use_cases/wallet/commands/send_gift_command.py:174-189
sys_bal_row = await self._session.execute(
    text("SELECT teqlik_balance FROM users WHERE id = 0")
)
sys_balance = sys_bal_row.scalar() or 0
await self._session.execute(
    text(
        "INSERT INTO wallet_ledger "
        "(user_id, delta_teqlik, balance_after, tx_type, reference_id, reference_type) "
        "VALUES (0, :delta, :bal, 'platform_revenue', :ref_id, 'gift_event')"
    ),
    {
        "delta": platform_teqlik,
        "bal": sys_balance + platform_teqlik,
        "ref_id": gift_event_id,
    },
)
```
**Sistem Bakiyesinin Donması ve Defter Tutarsızlığı:**
1. Kod `wallet_ledger` tablosuna `user_id = 0` için `balance_after` hesaplayıp yazar; ancak **`UPDATE users SET teqlik_balance = teqlik_balance + ... WHERE id = 0` SORGUSUNU ASLA ÇALIŞTIRMAMAKTADIR!**
2. Platformda 1 milyon hediye gönderilse ve şirket 500.000 Teqlik komisyon kazansa bile, `users` tablosundaki `id = 0` kullanıcısının `teqlik_balance` değeri **hep 0 kalır!**
3. Sonraki her hediye işleminde `SELECT teqlik_balance FROM users WHERE id = 0` sorgusu 0 döner; dolayısıyla `wallet_ledger`'a yazılan `balance_after` sütununda kümülatif artış yerine sürekli tekil işlem tutarı (örneğin 30, 15, 30...) yazılır.
4. Ayrıca `ConvertToTeqlikCommand` içinde kullanıcının `user_wallet_earnings.available` bakiyesinden düşülen tutar sanki `teqlik_balance`'dan düşülmüş gibi `wallet_ledger`'a `-teqlik_amount` olarak yazılmakta ancak `balance_after` değiştirilmemektedir. Kullanıcının defter hareketleri toplamı ile gerçek `teqlik_balance` değişimi arasında her dönüşümde kalıcı mutabakat açığı (reconciliation mismatch) oluşur.

#### 2. Çözüm / Refactoring Reçetesi
1. Sistem kullanıcısı için `users` tablosu atomik olarak güncellenmelidir:
```python
await self._session.execute(
    text("UPDATE users SET teqlik_balance = teqlik_balance + :delta WHERE id = 0"),
    {"delta": platform_teqlik},
)
```
2. `ConvertToTeqlikCommand` içinde cüzdan dönüşümü çift taraflı defterde `wallet_ledger`'a kullanıcı bazında sahte eksi bakiye yazmak yerine, ayrı bir kazanç defteri (earnings ledger) üzerinden veya net `+bonus_teqlik` şeklinde kaydedilmelidir.

---

### SRE-96 · 🟠 P1 (Yüksek) · `send-gift` İçinde Canlı Yayın ve Host Doğrulaması Olmaması Nedeniyle Kapanmış Yayın Üzerinden Kara Para ve Sahte Gelir Transferi

* **Etkilenen Dosyalar:**
  * `backend/app/routers/wallet.py` (satırlar 308–323)
  * `backend/app/use_cases/wallet/commands/send_gift_command.py` (satırlar 35–65)
  * `backend/app/models/gift_event.py` (satırlar 27–29)
* **İlgili Endpoint:** `POST /api/wallet/send-gift`

#### 1. Sorunun Tanımı ve Arıza Modu
`POST /api/wallet/send-gift` endpoint'i istek gövdesinde `stream_id`, `receiver_username`, `gift_name` ve `cost` parametrelerini alır.
`SendGiftCommand.execute` fonksiyonunda:
```python
# backend/app/use_cases/wallet/commands/send_gift_command.py:51-65
receiver_row = await self._session.execute(
    text("SELECT id, user_type FROM users WHERE username = :uname AND status = 'active' LIMIT 1"),
    {"uname": receiver_username},
)
...
if receiver_id == sender_id:
    raise BadRequestException(code="SELF_GIFT_FORBIDDEN")
```
**Sıfır Yayın ve Host Doğrulaması:**
Kod, `stream_id` parametresinin veritabanında var olup olmadığını, yayının o anda **CANLI (`is_live == True`)** olup olmadığını ve `receiver_username`'in o yayının gerçek sahibi (host) olup olmadığını **HİÇBİR ŞEKİLDE DENETLEMEMEKTEDİR!**

**Ağır İstismar Senaryoları:**
1. **Kapanmış Yayın Üzerinden Kara Para / Bakiye Transferi:**
   Kullanıcı 6 ay önce sona ermiş herhangi bir `stream_id` kullanarak canlı yayında olmayan rastgele bir kullanıcıya hediye gönderebilir. Gönderilen hediye alıcının hesabında anında nakde çevrilebilir (`user_wallet_earnings.pending`) paraya dönüşür. Teqlik doğrudan transfer edilemezken, bu açık sayesinde kullanıcılar kapalı döngüyü kırarak istedikleri kişiye komisyonsuz/denetimsiz nakit transferi yapabilir.
2. **Yayıncı Başkasıyken Hediyeyi Üçüncü Kişiye Yönlendirme (Sahte Hype & Dolandırıcılık):**
   Saldırgan `stream_id = 42` (popüler yayıncı Ayşe'nin canlı yayını) verir; ancak `receiver_username = "mehmet"` yazar. Ayşe'nin canlı yayın ekranında ve tüm izleyicilerin sohbetinde `publish_chat` ile "Ahmet 1000 Teqlik değerinde Roket gönderdi!" animasyonu patlar. Ancak para Ayşe'ye değil, arka planda yayında bile olmayan Mehmet'e aktarılır.
3. **Foreign Key Violation ve HTTP 500:**
   Geçersiz veya silinmiş bir `stream_id` girildiğinde `gift_events` tablosundaki `ForeignKey("live_streams.id")` kısıtı patlar ve endpoint `ForeignKeyViolation` ile HTTP 500 çöker.

#### 2. Çözüm / Refactoring Reçetesi
`SendGiftCommand` fonksiyonunun başına yayının aktifliğini ve yayıncı kimliğini doğrulayan kontrol eklenmelidir:
```python
stream_row = await self._session.execute(
    text("SELECT id, host_id, is_live, status FROM live_streams WHERE id = :sid"),
    {"sid": stream_id},
)
stream = stream_row.fetchone()
if not stream or not stream.is_live or stream.status != 'live':
    raise BadRequestException(code="STREAM_NOT_LIVE")

if stream.host_id != receiver_id:
    raise BadRequestException(code="RECEIVER_IS_NOT_STREAM_HOST")
```

---

### SRE-97 · 🟠 P1 (Yüksek) · Admin Kampanya Duraklatma ve İlan Pasifleştirmede Redis'in Güncellenmemesi (Admin vs Redis Desync)

* **Etkilenen Dosya:** `backend/app/routers/admin_data.py` (satırlar 310–326, 602–610)
* **İlgili Endpointler:** `POST /api/admin-data/ad-campaigns/{id}/pause`, `POST /api/admin-data/listings/{id}/toggle`, `DELETE /api/admin-data/listings/{id}`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Admin Kampanya Duraklatma:**
   Admin panelinden şüpheli veya kural ihlali yapan bir reklam kampanyası duraklatıldığında:
   ```python
   # backend/app/routers/admin_data.py:607-608
   campaign.status = "paused" if campaign.status == "active" else "active"
   await db.commit()
   ```
   Admin router'ı **Redis'e kesinlikle dokunmamaktadır!** Redis'teki `ad_campaign_budget:{id}` ve `ad_campaigns:active` Set'i silinmez. Kampanya veritabanında `paused` görünmesine rağmen, mobil kullanıcıların akışında gösterilmeye ve kullanıcılardan bütçe/tıklama tüketmeye devam eder.
2. **Admin İlan Pasifleştirme ve Silme:**
   Admin panelinden dolandırıcılık veya sahte ürün içeren bir ilan silindiğinde veya pasife alındığında (`admin_toggle_listing`, `admin_delete_listing`), sadece veritabanı güncellenir.
   `feed:recent` ZSet'inden ve `listing:{id}` Redis anahtarından (TTL 7 gün) ilan silinmez. Kullanıcılar yasaklanmış dolandırıcı ilanını feed'de görmeye devam eder.

#### 2. Çözüm / Refactoring Reçetesi
1. `admin_pause_campaign` fonksiyonu doğrudan `app.services.ad_service.pause_campaign` servisini çağırmalı; kampanya Redis setinden ve bütçe anahtarlarından temizlenmelidir.
2. `admin_toggle_listing` ve `admin_delete_listing` fonksiyonlarında `await remove_from_recent_feed_cache(listing_id)` ve `await invalidate_listing(listing_id)` çağrılmalıdır.

---

### SRE-98 · 🟡 P2 (Orta) · İlan Tekliflerinin Kimlik Doğrulamasız ve Gizliliksiz Halka Açık Sızması

* **Etkilenen Dosyalar:**
  * `backend/app/routers/listings.py` (satırlar 339–345)
  * `backend/app/use_cases/listings/queries/get_listing_offers.py` (satırlar 10–32)
* **İlgili Endpoint:** `GET /api/listings/{listing_id}/offers`

#### 1. Sorunun Tanımı ve Arıza Modu
İlan detay sayfasında verilen teklifleri getiren endpoint:
```python
# backend/app/routers/listings.py:339-344
@router.get("/{listing_id}/offers")
async def get_listing_offers(
    listing_id: int,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
):
    return await GetListingOffersQuery(uow).execute(listing_id)
```
1. **Kimlik Doğrulama Yok (Unauthenticated):** Endpoint üzerinde hiçbir `current_user` bağımlılığı yoktur. İnternetteki herhangi bir anonim bot veya kazıyıcı (scraper) bu endpoint'i çağırabilir.
2. **Gizlilik İhlali ve Veri Sızıntısı:** İkinci el pazarlık teklifleri alıcı ile satıcı arasında özeldir. Bu endpoint, ilana teklif veren tüm kullanıcıların ID'lerini, kullanıcı adlarını, profil fotoğraflarını ve verdikleri teklif miktarlarını açıkça döndürür.
3. Rakip satıcılar veya kötü niyetli kişiler, popüler bir ilana yüksek teklif veren alıcıları tespit edip onlara doğrudan spam mesaj atarak kendi ilanlarına çekebilir.
4. Ayrıca sayfalama (pagination) bulunmadığı için popüler ilanlarda yüzlerce teklif tek seferde hafızaya yüklenir.

#### 2. Çözüm / Refactoring Reçetesi
1. Endpoint'e `current_user: User = Depends(get_current_user)` eklenmelidir.
2. Sadece ilanın sahibi (`listing.user_id == current_user.id`) gelen tüm teklifleri görebilmeli; diğer kullanıcılar sadece kendi verdikleri teklifi görebilmelidir.
3. Sayfalama (`limit: int = 20, offset: int = 0`) eklenmelidir.

---

### SRE-99 · 🔴 P0 (Kritik) · Redis Oturum Önbelleğinde Eksik Tarih Deserializasyonu (`TypeError` Çökmesi) ve Cüzdan Bakiyesi Desenkronizasyonu

> ✅ **Çözüldü** — Commit `975457aa` · 2026-10-29

* **Etkilenen Dosyalar:** `backend/app/utils/auth.py`, `backend/app/models/user.py`, `backend/app/routers/wallet.py`
* **İlgili Satırlar:** `auth.py:96-153` (`_USER_DATETIME_COLS`, `_fetch_and_cache_user`), `user.py:62-71`, `wallet.py:100-380`

#### 1. Sorunun Tanımı ve Arıza Modu
1. `auth.py` içindeki oturum önbelleğinde (`session:user:{id}`):
   ```python
   _USER_DATETIME_COLS = ("voip_token_updated_at", "created_at", "premium_since", "referral_code_expires_at", "locale_updated_at")
   ```
   Ancak `User` modelinde `age_confirmed_at`, `cross_border_consent_at`, `cross_border_consent_revoked_at`, `pro_expires_at`, `pro_grace_until` olmak üzere 5 adet daha `DateTime(timezone=True)` sütunu mevcuttur.
2. `_serialize_user` tüm `datetime` alanlarını `val.isoformat()` yaparak JSON'a çevirir. Ancak `_fetch_and_cache_user` deserialize ederken sadece `_USER_DATETIME_COLS` içindekileri `datetime.fromisoformat` ile çevirir. Kalan 5 alan **`str` (string) olarak kalır**!
3. `User(**data)` oluşturulup `await db.merge(user, load=False)` ile session'a eklendiğinde, `user.pro_expires_at` bir string'dir.
   Uygulama içinde herhangi bir yerde Pro süresi kontrolü yapıldığında:
   `if user.pro_expires_at and user.pro_expires_at > datetime.now(timezone.utc):`
   Python derhal patlar:
   `TypeError: '>' not supported between instances of 'str' and 'datetime.datetime'`.
4. Ayrıca, `current_user` üzerinde herhangi bir alan güncellenip `await db.commit()` dendiğinde, SQLAlchemy ve `asyncpg` Timestamp sütununa string gittiği için `DataError` üretir.
5. **Cüzdan Bakiye Zehirlenmesi:** `_USER_SESSION_TTL = 900` (15 dakika) boyunca kullanıcının `teqlik_balance` değeri bu önbellekte tutulur. Kullanıcı `wallet.py` üzerinden hediye gönderdiğinde, para yüklediğinde veya TEQlik dönüştürdüğünde `invalidate_user_session_cache` çağrılmamaktadır! Kullanıcı bakiyesini harcadıktan sonra dahi sonraki 15 dakika boyunca `current_user.teqlik_balance` eski yüksek bakiyeyi gösterir ve bakiye kontrollerini baypas edebilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `_USER_DATETIME_COLS` sabitini statik tutmak yerine, `User.__table__.columns` üzerinden tipi `DateTime` olan tüm sütunları dinamik olarak deserialize et:
   ```python
   _DATETIME_COL_NAMES = {col.name for col in User.__table__.columns if isinstance(col.type, (DateTime, sa.DateTime))}
   for dt_col in _DATETIME_COL_NAMES:
       val = data.get(dt_col)
       if val and isinstance(val, str):
           try:
               data[dt_col] = datetime.fromisoformat(val.replace("Z", "+00:00"))
           except (ValueError, TypeError):
               data[dt_col] = None
   ```
2. `wallet.py`, `send_gift_command.py`, `convert_to_teqlik_command.py`, `verify_purchase_command.py` ve `transfer_teqlik.py` içinde bakiye değiştiğinde `await invalidate_user_session_cache(uid)` çağrısı eklenmelidir.

---

### SRE-100 · ✅ Çözüldü (`492932f0` · 2026-10-29) · Toplu Bildirimde (Blast) Önce Gönderim - Sonra Düşüm, `GREATEST(0, ...)` ile Negatif Bakiye Açığı ve Eksik Cache İptali

* **Etkilenen Dosya:** `backend/app/routers/listings.py`
* **İlgili Satırlar:** 840–930 (`mass_notify_listing`)

#### 1. Sorunun Tanımı ve Arıza Modu
1. `listings.py:847` satırında `if teqlik_cost > 0 and current_user.teqlik_balance < teqlik_cost:` kontrolü yapılır. Bu kontrol DB'yi kilitlemeden, kullanıcının oturum önbelleğindeki eski bakiyesine güvenir.
2. Ardından satır 893–896'da push bildirimleri **gerçekte gönderilir**:
   ```python
   for i in range(0, len(fcm_tokens), 50):
       chunk = fcm_tokens[i: i + 50]
       await asyncio.gather(*[_send_one(t) for t in chunk])
   ```
   Binlerce kullanıcıya FCM push bildirimi gitmiştir.
3. Bildirimler gittikten SONRA satır 910–913'te bakiye düşülmeye çalışılır:
   ```python
   await db.execute(
       sql_text("UPDATE users SET teqlik_balance = GREATEST(0, teqlik_balance - :cost) WHERE id = :uid"),
       {"cost": teqlik_cost, "uid": current_user.id},
   )
   ```
   Burada `GREATEST(0, ...)` kullanıldığı için, kullanıcının veritabanında sadece 1 TEQlik'i olsa veya 0 olsa bile sorgu başarıyla çalışır, bakiyeyi 0 yapar ve hata fırlatmaz! Kullanıcı 1000 TEQlik değerindeki blast kampanyasını bedavaya göndermiş olur.
4. İşlem sonunda `invalidate_user_session_cache(current_user.id)` çağrılmadığı için `current_user.teqlik_balance` Redis oturumunda 15 dakika boyunca eski yüksek değerinde kalmaya devam eder. Kullanıcı art arda sınırsız bedava blast gönderebilir!

#### 2. Çözüm / Refactoring Reçetesi
1. Önce atomik bakiye düşümü yapılmalı (`leads.py:298`'deki gibi):
   ```python
   if teqlik_cost > 0:
       res = await db.execute(
           sql_text("UPDATE users SET teqlik_balance = teqlik_balance - :cost WHERE id = :uid AND teqlik_balance >= :cost RETURNING teqlik_balance"),
           {"cost": teqlik_cost, "uid": current_user.id}
       )
       if res.fetchone() is None:
           raise InsufficientFundsException()
   ```
2. Bildirimler yalnızca bakiye başarıyla düşüldükten (`db.commit()`) sonra ARQ arka plan kuyruğu üzerinden asenkron gönderilmelidir.
3. Bakiye düşümünün hemen ardından `await invalidate_user_session_cache(current_user.id)` çağrılmalıdır.

---

### SRE-101 · ✅ Çözüldü (`8eb02c9e` · 2026-10-29) · Direkt Satışta Eşzamanlı Alımlarda Kilitsiz Stok Güncellemesi (Lost Update) ve İptal Sonrası Sipariş

* **Etkilenen Dosya:** `backend/app/use_cases/direct_sales/commands/direct_sale_commands.py`
* **İlgili Satırlar:** 370–455 (`purchase_sale`), 280–327 (`cancel_sale`), 54–59 (`_get_sale`)

#### 1. Sorunun Tanımı ve Arıza Modu
1. `purchase_sale` içinde `sale = await _get_sale(sale_id, uow.session)` çağrılır. `_get_sale` fonksiyonunda `with_for_update()` kilidi yoktur.
2. İki alıcı (Alıcı A ve Alıcı B) aynı anda sipariş verdiğinde:
   - Alıcı A Redis'te stoğu 5'ten 4'e düşürür (`remaining = 4`).
   - Alıcı B Redis'te stoğu 4'ten 3'e düşürür (`remaining = 3`).
   - Alıcı B'nin işlemi önce commit olur: `sale.remaining_stock = 3`.
   - Alıcı A'nın işlemi sonra commit olur: `sale.remaining_stock = 4`.
   Veritabanında 2 ürün satıldığı halde kalan stok 3 yerine 4 olarak kaydedilir (Lost Update).
3. Benzer şekilde, stok 1 iken son ürünü alan kişinin işlemi erken commit edip `status = "sold_out"` yapsa bile, yarışan diğer işlem commit ettiğinde `sale.remaining_stock = remaining` atayarak satışı tekrar `active` durumunda bırakabilir.
4. `cancel_sale` fonksiyonu satışı iptal edip siparişleri geçersiz kılarken (`orders_voided=True`):
   - Alıcıların hiçbirine DM veya bildirim gönderilmez; alıcılar ürünü aldıklarını zanneder.
   - İptal anında çalışan bir `purchase_sale` satır kilidi olmadığı için iptal edilen satışa `status="completed"` sipariş ekleyip commit edebilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `_get_sale` içine opsiyonel `for_update=False` parametresi eklenmeli; `purchase_sale` ve `cancel_sale` içinde `with_for_update()` ile çağrılmalıdır.
2. Python tarafında Redis'ten dönen `remaining` doğrudan atanmak yerine, SQL seviyesinde atomik stok düşümü yapılmalıdır:
   ```python
   await uow.session.execute(
       update(DirectSale)
       .where(DirectSale.id == sale_id, DirectSale.status == "active")
       .values(
           remaining_stock=DirectSale.remaining_stock - data.quantity,
           status=case((DirectSale.remaining_stock - data.quantity <= 0, "sold_out"), else_=DirectSale.status)
       )
   )
   ```
3. `cancel_sale` içinde `orders_voided=True` olduğunda etkilenen tüm alıcılara iptal bildirimi (DM ve push) gönderilmelidir.

---

### SRE-102 · ✅ Çözüldü (`916de451` · 2026-10-29) · `get_suggested_streamers` İçinde Her İstekte Milyonluk `follows` ve `live_streams` Full Tablo Taranması

* **Etkilenen Dosya:** `backend/app/routers/streams.py`
* **İlgili Satırlar:** 518–665 (`get_suggested_streamers`)

#### 1. Sorunun Tanımı ve Arıza Modu
1. Yayın keşif ekranında çağrılan `get_suggested_streamers` endpoint'i, hiçbir Redis önbelleği barındırmaz.
2. Her HTTP GET isteğinde çalıştırılan sorgu:
   ```sql
   LEFT JOIN (
       SELECT followed_id, COUNT(*) AS follower_count
       FROM follows GROUP BY followed_id
   ) fol ON fol.followed_id = u.id
   ```
   Postgres'teki tüm `follows` tablosunu filtresiz olarak `GROUP BY` ile toplar.
3. Ayrıca son 90 günün tüm yayınlarını (`live_streams WHERE started_at >= NOW() - INTERVAL '90 days'`) iki kez `GROUP BY host_id` ile tarar.
4. Eğer kullanıcının takip etmediği yayıncı bulunamazsa, aynı devasa sorgu `follow_filter=""` ile **ikinci kez** sıfırdan çalıştırılır.
5. 50 mobil kullanıcının canlı yayınlar sekmesini açması, saniyede 100 kez milyonlarca satırlık `follows` ve `live_streams` taraması demektir. Postgres CPU'su anında %100'e çıkar ve PgBouncer havuzundaki 40 bağlantı tükenir.

#### 2. Çözüm / Refactoring Reçetesi
1. `follows` tablosunu her istekte tümüyle taramak yerine:
   - Yayıncıların takipçi sayıları ya `users.follower_count` sütununda denormalize tutulmalı ya da skaler alt sorgu (`SELECT COUNT(*) FROM follows WHERE followed_id = u.id`) ile sadece filtrelenen yayıncılar için hesaplanmalıdır.
2. Öneri listesi kullanıcı bazında veya genel havuz olarak 5-10 dakika süreyle Redis'te önbelleklenmelidir (`cache:suggested_streamers:{uid}`).

---

### SRE-103 · ✅ Çözüldü (`e3be467d` · 2026-10-29) · Hikaye Görüntüleyenler Endpoint'inde (`get_story_viewers`) Sayfalama Eksikliği ve OOM Riski

* **Etkilenen Dosya:** `backend/app/services/story_service.py`
* **İlgili Satırlar:** 471–515 (`get_story_viewers`)

#### 1. Sorunun Tanımı ve Arıza Modu
1. `get_story_viewers` endpoint'inde sorgu şu şekildedir:
   ```python
   query = (
       select(StoryView, User)
       .join(User, User.id == StoryView.viewer_id)
       .where(StoryView.story_id == story_id)
       .order_by(StoryView.viewed_at.desc())
   )
   result = await self.db.execute(query)
   rows = result.all()
   ```
2. Sorguda hiçbir `limit` veya `offset` bulunmamaktadır.
3. 20.000–50.000 izlenmeye ulaşan bir fenomen veya satıcının hikayesinde, tek bir HTTP isteğinde 50.000 `StoryView` nesnesi ve 50.000 adet 74 sütunlu `User` SQLAlchemy modeli belleğe yüklenir.
4. Bu durum tek bir istek için 300–500 MB RAM tüketimine yol açar. Mobil uygulamanın sekmeyi art arda yenilemesi Uvicorn worker'ını OOM (Out Of Memory) ile çökerterek diğer tüm API isteklerini kesintiye uğratır.

#### 2. Çözüm / Refactoring Reçetesi
1. `get_story_viewers` endpoint'ine zorunlu sayfalama eklenmelidir:
   `limit: int = Query(50, ge=1, le=100), offset: int = Query(0, ge=0)`.
2. Tüm `User` modelini çekmek yerine sadece görüntüleme listesinde ihtiyaç duyulan alanlar (`id`, `username`, `full_name`, `profile_image_url`, `is_verified`) seçilmelidir.

---

### SRE-104 · 🟡 P2 (Orta) · Hype Highlight Videolarının Yerel Diske Kaydedilmesi, Kümede 404 ve Dosya Silinmeme Bellek Sızıntısı

* **Etkilenen Dosyalar:** `backend/app/tasks/video_tasks.py`, `backend/app/use_cases/streams/commands/misc_commands.py`
* **İlgili Satırlar:** `video_tasks.py:24-30, 91-149`, `misc_commands.py:33-38`

#### 1. Sorunun Tanımı ve Arıza Modu
1. Canlı yayında hype skoru 90'ı aştığında `capture_hype_highlight` fonksiyonu tetiklenir ve 15 saniyelik WHEP akışı kaydedilir.
2. Dosya merkezi nesne depolama (MinIO) yerine yerel diske yazılır:
   `_HIGHLIGHTS_DIR = pathlib.Path(__file__).resolve().parents[2] / "static" / "highlights"`
   ve `listings` tablosuna `vurl = f"/highlights/highlight_{room_id}.mp4"` olarak eklenir.
3. `teqlif` çoklu sunucu mimarisinde (Node1, Node2, Node3..), istemci isteği dosyayı üreten sunucu dışındaki bir sunucuya veya Nginx CDN'ine gittiğinde video **HTTP 404 Not Found** döner.
4. `EndStreamCommand` içinde yayın sonlandırılırken:
   `DELETE FROM listings WHERE active_room_id = :rid AND is_highlight = TRUE`
   çalıştırılır; veritabanındaki kayıt silinir ANCAK yerel diskteki MP4 dosyası asla silinmez.
5. Eğer yayın anormal kapanırsa veya webhook tarafından temizlenirse, hem veritabanındaki listing satırı hem de diskteki MP4 dosyası sonsuza dek yetim kalır; yüzlerce GB disk alanı tükenir.

#### 2. Çözüm / Refactoring Reçetesi

> ✅ **Çözüldü** — commit `b23b8e3a` · 2026-10-29
> - `video_tasks.py`: `tempfile.mkstemp` → FFmpeg → `storage.upload_file("highlights/highlight_{room_id}.mp4")` → `finally: os.unlink(tmp)`. Yerel `_HIGHLIGHTS_DIR` ve `_highlight_path()` kaldırıldı.
> - `misc_commands.py` `EndStreamCommand`: `DELETE` öncesi `SELECT video_url` ile URL'leri topla; commit sonrası `storage.delete_object(url)` ile MinIO temizliği.
> - `analytics_tasks.py` `cleanup_hype_highlights_task`: disk scan kaldırıldı; `SELECT video_url` → `DELETE` → commit → MinIO cleanup akışı eklendi.

---

### SRE-105 · 🔴 P0 (Kritik) · Canlı Yayın Kalplerinde Senkron DB Commit, Her Kalpte Expire ve Bireysel WS Broadcast Patlaması (C10K/Postgres Crash)

* **Etkilenen Dosya:** `backend/app/services/like_service.py`
* **İlgili Satırlar:** [like_service.py:180-239](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/like_service.py#L180-L239)
* **Tetiklenme Noktası:** İstemcinin canlı yayın sırasında ekrana ardı ardına dokunarak kalp göndermesi (`POST /api/streams/{stream_id}/like` veya WS kalp event'i).

#### 1. Sorunun Tanımı ve Arıza Modu
1. Canlı yayınlarda izleyicilerin ortalama kalp gönderme sıklığı saniyede 5–15 adettir. 1.000 izleyicili orta ölçekli bir yayında anlık olarak saniyede **3.000 ila 8.000 kalp sinyali** üretilir.
2. `LikeService.add_stream_like` metodu incelendiğinde her tekil kalp için:
   ```python
   self.db.add(StreamLike(stream_id=stream_id, user_id=user_id))
   await self.db.commit()
   ```
   yapılmaktadır. Saniyede 5.000 kez Postgres'e tek satırlık `INSERT INTO stream_likes` ve ardından `COMMIT` çağrılmaktadır. Bu durum Postgres PgBouncer havuzunu saniyeler içinde tüketir, WAL fsync disk I/O doygunluğuna ulaşır ve tüm backend genelinde veritabanı kilitlenmelerine (500 DatabaseException) yol açar.
3. Ayrıca her kalp için:
   ```python
   await redis.incr(f"stream:likes:{stream_id}")
   await redis.expire(f"stream:likes:{stream_id}", 48 * 3600)
   ```
   çağrılarak Redis'e fazladan EXPIRE komutları bindirilmektedir.
4. En felaket nokta ise WebSocket yayınıdır:
   ```python
   await publish_chat(stream_id, {
       "type": WS.STREAM_LIKE,
       "user_id": user_id,
       "username": username,
   })
   ```
   Her kalp sinyali için odadaki tüm izleyicilere tekil bir WebSocket paketi yayımlanmaktadır. 1.000 izleyici × saniyede 5.000 kalp = **saniyede 5.000.000 WebSocket paketi**! Bu hacim Uvicorn event loop'unu ve Redis Pub/Sub buffer'larını anında şişirir; bellek tükenmesi (OOM kill) ve tüm aktif WebSocket bağlantılarının kopması kaçınılmazdır.

#### 2. Çözüm / Refactoring Reçetesi

> ✅ **Çözüldü** — commit `3a939bd1` · 2026-10-29
> - `like_service.py` `add_stream_like`: DB INSERT+COMMIT kaldırıldı. `INCRBY stream:likes:{id}` + `INCRBY stream:likes:pending:{id}`; EXPIRE yalnızca ilk kez; `count` parametresi eklendi (max 50).
> - `stream_like_ticker.py` (yeni): lifespan background task — saniyede 1 kez `stream:likes:pending:*` key'lerini SCAN+GETDEL, `stream_like_batch {count}` WS sinyali olarak yayar.
> - `stream_finalizer.py`: yayın kapanışında Redis sayacını `total_likes` DB sütununa yazar; `stream:likes:pending:{id}` key'i temizlenir.
> - `like_service.py` `batch_stream_likes`: `COUNT(stream_likes)` yerine `live_streams.total_likes` sütununu okur.
> - `ws_types.py`: `STREAM_LIKE_BATCH` sabiti eklendi.
> - Alembic `zzzzzz_stream_total_likes`: `live_streams.total_likes INTEGER NOT NULL DEFAULT 0`.

---

### SRE-107 · 🔴 P0 (Kritik) · Arama Alarmı Silmede Enum Uyuşmazlığı (`'passive'`) Nedeniyle Alarmların Asla Silinememesi (`DataError` 500) ve Zombi Alarm Birikmesi

* **Etkilenen Dosyalar:** `backend/app/routers/search_alerts.py`, `backend/app/models/enums.py`, `backend/app/models/search_alert.py`
* **İlgili Satırlar:** [search_alerts.py:103](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/search_alerts.py#L103), [enums.py:22-25](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/enums.py#L22-L25), [search_alert.py:24](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/search_alert.py#L24)
* **Tetiklenme Noktası:** Kullanıcının aktif bir arama alarmını silmek istemesi (`DELETE /api/search-alerts/{alert_id}`).

#### 1. Sorunun Tanımı ve Arıza Modu
1. `models/enums.py` dosyasında `SearchAlertStatus` enum'ı şu şekilde tanımlıdır:
   ```python
   class SearchAlertStatus(str, enum.Enum):
       ACTIVE = "active"
       PAUSED = "paused"
       DELETED = "deleted"
   ```
   Ve `SearchAlert` tablosundaki `status` sütunu PostgreSQL seviyesinde `SQLEnum(SearchAlertStatus, ...)` tipiyle kısıtlanmıştır.
2. Ancak `search_alerts.py:delete_alert` endpoint'inde:
   ```python
   @router.delete("/{alert_id}", status_code=status.HTTP_204_NO_CONTENT)
   async def delete_alert(...):
       ...
       alert.status = 'passive'  # <-- KRİTİK HATA!
       await db.commit()
   ```
   `'passive'` değeri `SearchAlertStatus` enum'ında mevcut değildir!
3. Kullanıcı alarmı silmek istediğinde SQLAlchemy veya PostgreSQL sürücüsü anında:
   `DataError: invalid input value for enum search_alert_status: "passive"`
   veya `LookupError: 'passive' is not among the valid values` hatası fırlatarak HTTP 500 ile çöker.
4. Bu nedenle hiçbir kullanıcı oluşturduğu arama alarmını silemez!
5. `worker.py` içindeki `check_search_alerts_task` her 15 dakikada bir tüm `status == SearchAlertStatus.ACTIVE` olan alarmları taradığı için, kullanıcılar sildiklerini sandıkları alarmlar yüzünden sürekli spam push bildirimleri almaya devam eder; kullanıcı deneyimi ve veritabanı kirliliği oluşur.

#### 2. Çözüm / Refactoring Reçetesi
1. `search_alerts.py:delete_alert` içinde enum'a uygun olarak `SearchAlertStatus.DELETED` kullanılmalı veya kayıt fiziksel olarak silinmelidir:
   ```python
   alert.status = SearchAlertStatus.DELETED
   # veya:
   await db.delete(alert)
   await db.commit()
   ```

#### ✅ Çözüm Damgası
* **Commit:** `0f5477c9` + followup `fccdd252`
* **Tarih:** 2026-10-29
* **Uygulanan Değişiklikler:**
  - `backend/app/routers/search_alerts.py:103` → `alert.status = 'passive'` → `alert.status = SearchAlertStatus.DELETED`
  - `backend/alembic/versions/zzzzz0_searchalert_enum_fix.py` (yeni): PostgreSQL `searchalertstatus` enum tipine `'paused'` ve `'deleted'` değerleri eklendi (`autocommit_block + IF NOT EXISTS` — idempotent); eski `'passive'` kayıtlar `'deleted'`e taşındı
* **Migration:** `sudo teqlif-restart` ile node1 (prod) ve node5 (staging) `ExecStartPre` üzerinden `alembic upgrade head` çalıştırıldı ✅

---

### SRE-106 · 🔴 P0 (Kritik) · HTTP Handler İçinde 10.000 Alıcı İçin Senkron ORM Obje Tahsisi ve 200 Sıralı FCM HTTP Çağrısı (60-120s Gateway Timeout / DoS)

* **Etkilenen Dosya:** `backend/app/routers/leads.py`
* **İlgili Satırlar:** [leads.py:336-382](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/leads.py#L336-L382)
* **Tetiklenme Noktası:** PRO satıcının kitleye bildirim göndermesi (`POST /api/leads/send-blast`).

#### 1. Sorunun Tanımı ve Arıza Modu
1. `leads.py:send_blast` fonksiyonunda hedef kitle belirlendikten sonra (maksimum 10.000 kullanıcı):
   ```python
   db.add_all([
       Notification(
           user_id=uid,
           type="lead_blast",
           title=notif_title,
           body=notif_body,
           related_id=body.listing_id,
       )
       for uid in recipient_ids
   ])
   await db.commit()
   ```
   10.000 adet tam SQLAlchemy `Notification` ORM modeli aynı anda Python heap belleğinde tahsis edilmekte ve devasa bir transaction içinde `commit()` edilmektedir. Bu işlem SQLAlchemy ORM change-tracking nedeniyle yüzlerce megabyte RAM tüketir ve Postgres'te uzun süreli tablo kilidi tutar.
2. Hemen ardından, HTTP istek döngüsü içinde Firebase FCM gönderimi başlatılmaktadır:
   ```python
   chunk_size = 50
   sent = 0
   for i in range(0, len(fcm_tokens), chunk_size):
       chunk = fcm_tokens[i : i + chunk_size]
       await asyncio.gather(*[_send_one(t, campaign.id) for t in chunk])
       sent += len(chunk)
   ```
   10.000 token / 50 = 200 iterasyon. Her iterasyonda Google Firebase API'sine HTTP çağrıları yapılmaktadır. Ortalama ağ gecikmesiyle bu döngü **60 ila 120 saniye** sürer!
3. Nginx varsayılan `proxy_read_timeout` değeri 60 saniyedir; istemci 504 Gateway Timeout alır ve işlem başarısız zanneder. Bu esnada Uvicorn worker thread'i 2 dakika boyunca bu döngüde bloke kalır ve diğer HTTP isteklerini işleyemez (Self-DoS).
4. Üstelik `_send_one` Firebase'in çoklu alıcı (`send_each_for_multicast`) API'si yerine tekil `send_push` kullanmaktadır.

#### 2. Çözüm / Refactoring Reçetesi
1. **İşi ARQ Kuyruğuna Delege Et:** `send_blast` endpoint'i bakiye kontrolü ve düşümünü yaptıktan sonra doğrudan `202 Accepted` ile dönmeli; in-app bildirim oluşturma ve push gönderimi ARQ `critical` veya `notifications` kuyruğuna aktarılmalıdır.
2. **Toplu Veritabanı Yazımı:** 10.000 ORM objesi yerine PostgreSQL `INSERT INTO notifications (...) VALUES (...), (...)` chunked raw SQL veya `session.execute(insert(Notification), mappings)` kullanılmalıdır.
3. **Firebase Multicast:** FCM bildirimleri 500'lük gruplar halinde `firebase_admin.messaging.send_each_for_multicast` ile gönderilmelidir:
   ```python
   await arq_redis.enqueue_job(
       "process_lead_blast_task",
       campaign_id=campaign.id,
       recipient_ids=recipient_ids,
       fcm_tokens=fcm_tokens,
       title=notif_title,
       body=notif_body,
       listing_id=body.listing_id,
       stream_id=body.stream_id,
   )
   return {"campaign_id": campaign.id, "status": "processing", "recipient_count": actual_count}
   ```

> **✅ Çözüldü** — Commit `1f13485a` + followup `954a4e2d` · 2026-10-29
> `leads.py`: 10.000 ORM objesi + 200-iter FCM döngüsü kaldırıldı → ARQ `process_lead_blast_task` kuyruğuna devredildi; HTTP 202 anında döner. Pool yoksa 503 (bakiyeye dokunulmaz). Geriye dönük `sent`/`spent`/`sent_count` alanları korundu.
> `worker.py`: `process_lead_blast_task` eklendi — `WHERE sent_count = 0 RETURNING id` atomik idempotency guard + bulk INSERT (1.000'lik chunk) + `send_multicast` (500-token batch); `WorkerSettings.functions`'a kayıtlı.

---

### SRE-108 · 🟠 P1 (Yüksek) · Anlık Çağrı Meşguliyetinin (`user_busy`) Statik 1 Saatlik İlişki Önbelleğine Gömülmesi ve 3. Kişilerin 1 Saat Kilitlenmesi

* **Etkilenen Dosyalar:** `backend/app/services/relationship_service.py`, `backend/app/services/call_presence.py`
* **İlgili Satırlar:** [relationship_service.py:271-280](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/relationship_service.py#L271-L280), [call_presence.py:25-60](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/call_presence.py#L25-L60)
* **Tetiklenme Noktası:** Kullanıcı B bir görüşmedeyken, Kullanıcı C'nin Kullanıcı B'nin profilini veya mesajlaşma ekranını açması.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `RelationshipStateService.recompute_and_cache` fonksiyonu iki kullanıcı arasındaki ilişkiyi hesaplarken anlık arama durumunu (`is_busy`) da içine dahil eder:
   ```python
   # Call presence override: hedef aramadaysa can_call → False + user_busy
   if state.can_call_ab and await _is_busy(b):
       state.can_call_ab = False
       state.reason_ab = _REASON_USER_BUSY
   await RelationshipStateService.cache(state)  # TTL: 3600 sn (1 saat)
   ```
2. Kullanıcı B, Kullanıcı A ile 30 saniyelik kısa bir görüşme yaparken; üçüncü bir kişi olan Kullanıcı C, B'nin profilini veya mesajlaşma sayfasını açarsa:
   `recompute_and_cache(C, B)` tetiklenir ve Redis'e `rel:C:B` anahtarı **1 saat (3600 sn)** TTL ile `can_call = False, reason = "user_busy"` olarak yazılır.
3. Kullanıcı B ile A görüşmeyi 10 saniye sonra kapattığında, `call_presence.clear_presence(B)` fonksiyonu yalnızca o aramada bulunan `peers` listesini (yani sadece A'yı) invalidate eder:
   ```python
   for peer_id in peers:
       await RelationshipStateService.invalidate(uid, peer_id)
   ```
   Kullanıcı C bu `peers` listesinde DEĞİLDİR!
4. Sonuç olarak: B artık boşta olmasına rağmen, C'nin Redis'teki önbelleği 1 saat boyunca "user_busy" olarak donar! C kullanıcısı B'yi aramak istediğinde veya arama butonuna baktığında 1 saat boyunca "Kullanıcı meşgul" hatası alır ve arama yapamaz (Cache Poisoning).

#### 2. Çözüm / Refactoring Reçetesi
1. **Dinamik Durum Statik Önbelleğe Yazılmamalı:** `rel:A:B` anahtarı sadece izinleri (takip, engelleme, mesajlaşma izni) önbelleklemelidir.
2. `is_busy` kontrolü `recompute_and_cache` içinden ve Redis'e yazılan `PairRelationshipState` veri yapısından çıkarılmalıdır.
3. `can_call` için anlık meşguliyet kontrolü yalnızca arama başlatma anında (`calls.py:start_call`) ve `GetThreadStatusQuery` yanıtı oluşturulurken canlı olarak sorgulanmalıdır.

---

### SRE-109 · 🟠 P1 (Yüksek) · Reklam Tıklama Lua Scriptinde Negatif Bütçe Guard'ı Olmaması ve `ad_campaigns:active` Set İhmali

* **Etkilenen Dosya:** `backend/app/services/ad_service.py`
* **İlgili Satırlar:** [ad_service.py:36-43](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ad_service.py#L36-L43), [ad_service.py:143-196](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ad_service.py#L143-L196), [ad_service.py:199-226](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ad_service.py#L199-L226)
* **Tetiklenme Noktası:** Reklam kampanyası bütçesinin son tıklamaları sırasında eşzamanlı tıklamalar veya kampanyanın duraklatılması.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `ad_service.py` içindeki atomik bütçe düşme Lua scripti:
   ```lua
   local current = tonumber(redis.call('GET', KEYS[1]))
   if not current then return nil end
   local bid = tonumber(ARGV[1])
   local new_val = math.floor(current - bid)
   redis.call('SET', KEYS[1], tostring(new_val))
   return tostring(new_val)
   ```
   Script `if not current` kontrolü yapmakta ancak `if current <= 0` kontrolü YAPMAMAKTADIR.
2. Bütçesi 5 TEQlik kalan bir kampanyaya 10 TEQlik CPC ile eşzamanlı 5 tıklama gelirse; ilk tıklama bütçeyi -5 yapar, ikincisi -15, üçüncüsü -25 yapar. PostgreSQL'de `status='completed'` update'i gerçekleşene kadar gelen tüm tıklamalar kabul edilir (`return True`) ve bütçe aşımı yaşanır.
3. İkinci açık: `pause_campaign` fonksiyonu `load_active_campaigns_to_redis` tarafından doldurulan `ad_campaigns:active` Redis set'inden duraklatılan kampanya ID'sini silmemektedir (`srem` çağrılmamıştır).
4. `FeedQueries._get_sponsored_listings` bu seti okuduğu için, duraklatılmış kampanyanın ilanları feed'de kullanıcılara sponsorlu olarak gösterilmeye devam eder. Tıklandığında ise bütçe anahtarı silinmiş olduğu için `record_ad_click` başarısız olur ve raporlama tutarsızlaşır.

#### 2. Çözüm / Refactoring Reçetesi
1. **Lua Script Bütçe Guard'ı:**
   ```lua
   local current = tonumber(redis.call('GET', KEYS[1]))
   if not current or current <= 0 then return nil end
   local bid = tonumber(ARGV[1])
   local new_val = math.floor(current - bid)
   redis.call('SET', KEYS[1], tostring(new_val))
   return tostring(new_val)
   ```
2. **Aktif Set Senkronizasyonu:** `pause_campaign` ve bütçe bittiğinde `record_ad_click` içinde `pipe.srem("ad_campaigns:active", str(campaign_id))` eklenmelidir.

---

### SRE-110 · 🟠 P1 (Yüksek) · Arama Stemmer'ında Tek Tırnak Temizlenmemesi (`to_tsquery` Syntax Error 500) ve Sınırsız Offset DoS

* **Etkilenen Dosyalar:** `backend/app/services/ml/turkish_nlp.py`, `backend/app/routers/search.py`, `backend/app/use_cases/search/queries/search_listings_query.py`
* **İlgili Satırlar:** [turkish_nlp.py:51](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/turkish_nlp.py#L51), [search.py:25-67](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/search.py#L25-L67), [search_listings_query.py:161-170](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/search/queries/search_listings_query.py#L161-L170)
* **Tetiklenme Noktası:** Kullanıcının kesme işaretli kelimeler ("ahmet'in", "apple'dan") araması veya bota ait büyük offset istekleri.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `turkish_nlp.py:build_stemmed_tsquery` fonksiyonunda özel karakterler temizlenirken regex filtresi:
   ```python
   safe = re.sub(r"[&|!():<>@*\\]", " ", q)
   ```
   olarak tanımlanmıştır. Tek tırnak (`'`) ve çift tırnak (`"`) karakterleri regex listesinde YOKTUR.
2. Kullanıcı "iphone'un şarjı" şeklinde arama yaptığında; kelimeler `["iphone'un", "şarjı"]` olarak ayrılır, stemmer `iphone'un` üretir ve sonuç:
   `"iphone'un:* & şarjı:*"` olarak döner.
3. Bu ifade `to_tsquery('turkish', :tsq_prefix)` içine parametre olarak gönderildiğinde, PostgreSQL `tsquery` ayrıştırıcısı tek tırnağı token kapanışı veya sözdizimi hatası olarak değerlendirir ve:
   `asyncpg.exceptions.QueryCanceledError / SyntaxError: syntax error in tsquery: "iphone'un:*"`
   fırlatarak aramayı HTTP 500 ile çökertir.
4. Ayrıca `search.py` router'ındaki tüm arama endpoint'lerinde (`/listings`, `/users`, `/all`) `offset: int = 0` parametresine herhangi bir doğrulama tavanı (`le=...`) konulmamıştır. Bir saldırgan `offset=500000` göndererek veritabanını yüz binlerce satırı atlamak için full indeks taramasına ve disk I/O krizine zorlayabilir.

#### 2. Çözüm / Refactoring Reçetesi
1. `build_stemmed_tsquery` içine tek ve çift tırnak temizliği eklenmelidir:
   ```python
   safe = re.sub(r"['\"&|!():<>@*\\]", " ", q)
   ```
2. `search.py` endpoint'lerindeki `offset` parametresine `Query(default=0, ge=0, le=1000)` tavanı getirilmelidir.

---

### SRE-111 · 🔴 P0 (Kritik) · `minio_public_base` ile Silme Yönlendirme Hatası ve Edge MinIO Terabaytlarca Medya Yetim Sızıntısı

* **Etkilenen Dosya:** `backend/app/services/storage_service.py`
* **İlgili Satırlar:** [storage_service.py:44-67](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L44-L67), [storage_service.py:115-127](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L115-L127), [storage_service.py:226-237](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L226-L237)
* **Tetiklenme Noktası:** İlan, profil veya hikaye medyası silindiğinde (`delete_object` veya `delete_object_dm`).

#### 1. Sorunun Tanımı ve Arıza Modu
1. `storage_service.py` içinde dosya yüklenirken `orchestrator.allocate_node(ServiceType.STORAGE)` çağrılır ve dosya o an en uygun olan edge sunucusuna (örn: Node3 veya Node4 MinIO) yüklenir.
2. `settings.minio_public_base` yapılandırıldığında (örn: `https://uploads.teqlif.com`), `_build_public_url` fonksiyonu `https://uploads.teqlif.com/teqlif/{key}` şeklinde tek tip CDN URL'i üretir.
3. Ancak nesne silinmek istendiğinde `delete_object(url)` fonksiyonu `_get_client_from_public_url(url)` çağırır:
   ```python
   parsed = urllib.parse.urlparse(public_url)
   domain = parsed.hostname  # "uploads.teqlif.com"
   ...
   metrics = await orchestrator.get_edge_metrics()
   for m in metrics:
       nid = m.get("node_id", "")
       expected_nid = domain.replace("minio", "live")
       if nid == expected_nid or nid == domain:
           return _get_client_for_internal_url(m["minio_url"])

   # Fallback if node offline / deleted
   if settings.edge_minio_urls:
       return _get_client_for_internal_url(settings.edge_minio_urls[0])
   ```
4. `domain` her zaman `uploads.teqlif.com` olduğundan ve metriklerdeki `node_id` değerleri `node1`, `node3`, `live1...` olduğundan bu döngü ASLA eşleşme bulamaz!
5. Kod daima fallback satırına düşer ve `settings.edge_minio_urls[0]`'ı (yani daima Node1'i) döner!
6. Sonuç: Dosya gerçekte Node3 veya Node4'te depolanmış olmasına rağmen, silme emri Node1'e gönderilir. Node1'de dosya bulunamadığı için hata yutulur; fakat asıl dosyanın bulunduğu edge sunucusundaki nesne **asla silinmez**!
7. Sistem çalıştıkça edge MinIO sunucularında yüz binlerce silinmiş sanılan video ve görsel yetim kalarak diski tüketir.

#### 2. Çözüm / Refactoring Reçetesi
1. Medya key yapısına node tanımlayıcısı eklenmeli (`{node_id}/{key}`) veya silme işlemi sırasında nesne bulunamazsa tüm bilinen `edge_minio_urls` listesinde paralel olarak silinmelidir:
   ```python
   async def delete_object(url_or_key: str) -> None:
       key = url_to_key(url_or_key)
       # Tüm edge minio sunucularında paralel silme garantisi
       tasks = [
           asyncio.to_thread(_get_client_for_internal_url(url).remove_object, settings.minio_bucket, key)
           for url in settings.edge_minio_urls
       ]
       await asyncio.gather(*tasks, return_exceptions=True)
   ```

#### ✅ Çözüm Damgası
* **Commit:** `43296288`
* **Tarih:** 2026-10-29
* **Uygulanan Değişiklikler:**
  - `_get_client_from_public_url` kaldırıldı — CDN domain'i node_id ile eşleştiremediği için temelden bozuktu; tüm delete sessizce başarısız oluyordu
  - `_get_all_storage_clients()` eklendi — orchestrator metrics → `edge_minio_urls` → `minio_endpoint` öncelikli fallback zinciri
  - `delete_object` ve `delete_object_dm` fanout'a çevrildi — tüm storage node'larında `asyncio.gather` ile paralel silme, `NoSuchKey` görmezden geliniyor
* **Followup Commit:** `013a3819` — `url_to_key` / `dm_url_to_key` idempotent hale getirildi; ham key verildiğinde ilk klasör segmenti kesiliyordu → 13/15 silme noktasında NoSuchKey ile sessizce başarısız oluyordu

---

### SRE-112 · 🔴 P0 (Kritik) · UoW Context Bloğu Dışında Kapatılmış Session ile DB Sorgusu Çalıştırma (`IllegalStateChangeError`)

* **Etkilenen Dosya:** `backend/app/use_cases/messages/commands/delete_conversation_command.py`
* **İlgili Satırlar:** [delete_conversation_command.py:37-105](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/messages/commands/delete_conversation_command.py#L37-L105)
* **Tetiklenme Noktası:** Karşılıklı iki kullanıcının da konuşmayı silmesi (hard-delete tetiklenmesi).

#### 1. Sorunun Tanımı ve Arıza Modu
1. `DeleteConversationCommand.execute` içinde iki taraf da konuşmayı sildiğinde `async with self.uow:` bloğunda mesajlar ve thread silinir:
   ```python
   async with self.uow:
       ...
       await self.uow.session.delete(thread)
       session = self.uow.session  # commit sonrası recompute için referansı sakla

   # Context manager bloğu bitti — session commit edildi ve KAPATILDI!
   if rel_state is None and session is not None:
       rel_state = await RelationshipStateService.recompute_and_cache(
           user_a_id, user_b_id, session
       )
   ```
2. `async with self.uow:` bloğu kapandığında SQLAlchemy UnitOfWork transaction'ı sonlandırır ve veritabanı bağlantısını havuza iade eder.
3. Blok dışında kalan `RelationshipStateService.recompute_and_cache(..., session)` fonksiyonu ise kapanmış bu `session` üzerinden `select(Follow)...` ve `select(MessageThread)...` sorgularını yürütmeye çalışır.
4. SQLAlchemy / asyncpg anında:
   `sqlalchemy.exc.IllegalStateChangeError: The transaction is inactive / connection is closed`
   fırlatır ve işlem HTTP 500 ile çöker. İstemci "Internal Server Error" alır.

#### 2. Çözüm / Refactoring Reçetesi
1. `recompute_and_cache` çağrısı ya henüz session açıkken `async with self.uow:` bloğunun içinde yürütülmeli ya da blok sonrasında taze bir bağımsız `AsyncSessionLocal` oturumu açılmalıdır:
   ```python
   async with self.uow:
       ...
       await self.uow.session.delete(thread)
       # Henüz oturum açıkken recompute et:
       rel_state = await RelationshipStateService.recompute_and_cache(
           user_a_id, user_b_id, self.uow.session
       )
   ```

#### ✅ Çözüm Damgası
* **Commit:** `4ca62de5`
* **Tarih:** 2026-10-29
* **Uygulanan Değişiklikler:**
  - `session` referans takibi kaldırıldı; `hard_deleted` flag eklendi
  - `async with self.uow:` kapandıktan sonra `AsyncSessionLocal()` ile taze bağımsız session açılıyor
  - `_purge_media` URL'leri doğrudan geçecek şekilde sadeleştirildi (url_to_key/dm_url_to_key artık idempotent)

---

### SRE-113 · 🟠 P1 (Yüksek) · Herkesten Silinen Mesajlarda MinIO DM Dosyasının Silinmemesi ve KVKK/Gizlilik İhlali

* **Etkilenen Dosya:** `backend/app/use_cases/messages/commands/delete_message_command.py`
* **İlgili Satırlar:** [delete_message_command.py:38-53](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/messages/commands/delete_message_command.py#L38-L53)
* **Tetiklenme Noktası:** Kullanıcının gönderdiği bir fotoğraf, video veya ses kaydı mesajını "Herkesten Sil" (`DELETE /api/messages/{id}?scope=everyone`) yapması.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `DeleteMessageCommand` içinde `scope == "everyone"` seçildiğinde:
   ```python
   other_user_id = msg.receiver_id
   await self.uow.session.delete(msg)
   broadcast_delete = True
   ```
   Veritabanındaki `direct_messages` satırı silinir ve her iki tarafa WebSocket üzerinden `message_deleted` olayı yayınlanır.
2. Ancak mesaj bir medya mesajıysa (`msg.media_url` veya `msg.thumbnail_url` doluysa), MinIO `teqlif-dm` private bucket'ındaki dosyanın silinmesi için HİÇBİR çağrı (`delete_object_dm`) yapılmamaktadır!
3. Kullanıcı mesajı herkesten sildiğini zannederken, özel fotoğraf veya ses dosyası MinIO sunucularında kalıcı olarak saklanmaya devam eder. Bu durum hem KVKK/GDPR "unutulma hakkı" ve gizlilik ihlalidir hem de depolama sızıntısı yaratır.

#### 2. Çözüm / Refactoring Reçetesi
1. Mesaj DB'den silinmeden önce medya URL'leri alınmalı ve commit sonrasında asenkron olarak MinIO'dan temizlenmelidir:
   ```python
   media_to_delete = [u for u in (msg.media_url, msg.thumbnail_url) if u]
   await self.uow.session.delete(msg)
   ...
   if media_to_delete:
       from app.services import storage_service as storage
       for url in media_to_delete:
           asyncio.create_task(storage.delete_object_dm(url))
   ```

---

### SRE-114 · 🟠 P1 (Yüksek) · IPv6 Kullanıcılarında `mask_ip`'nin None Dönmesi ve Shill Bidding Korumasının %100 By-pass Olması

* **Etkilenen Dosyalar:** `backend/app/core/ip_utils.py`, `backend/app/services/fraud_detection_service.py`
* **İlgili Satırlar:** [ip_utils.py:4-12](file:///Users/tucibeyin/Desktop/teqlif/backend/app/core/ip_utils.py#L4-L12), [fraud_detection_service.py:97-99](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/fraud_detection_service.py#L97-L99)
* **Tetiklenme Noktası:** Mobil operatörler üzerinden IPv6 adresiyle müzayedeye katılan kullanıcılar.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `ip_utils.py:mask_ip` fonksiyonu:
   ```python
   def mask_ip(ip: str | None) -> str | None:
       if not ip: return None
       parts = ip.split(".")
       if len(parts) == 4:
           return f"{parts[0]}.{parts[1]}.{parts[2]}.0"
       return None  # IPv6 saklanmıyor
   ```
   IPv6 adresleri için doğrudan `None` dönmektedir.
2. `FraudDetectionService.evaluate_bid` ise ilk satırında:
   ```python
   if not bidder_ip or not host_ip or bidder_ip != host_ip:
       return FraudDecision(action="PASS", score=0, reason="no_ip_match")
   ```
   şartına sahiptir.
3. Türkiye'deki mobil operatörler (Turkcell, Vodafone, Türk Telekom) 4G/5G bağlantılarında cihazlara öncelikli olarak IPv6 tahsis eder. Yayıncı veya sahte teklifçi mobil bağlantı kullandığında `bidder_ip` veya `host_ip` None olur; dolayısıyla shill bidding fraud kontrolü **tamamen devre dışı kalır**!
4. Kötü niyetli bir yayıncı aynı Wi-Fi/hücresel ağdan başka bir telefonla kendi müzayedesine sahte fiyat artırma teklifleri verdiğinde sistem bunu hiçbir zaman yakalayamaz.

#### 2. Çözüm / Refactoring Reçetesi
1. `ip_utils.py` içinde `ipaddress` kütüphanesi kullanılarak IPv6 adresleri için `/64` alt ağ maskelemesi uygulanmalıdır:
   ```python
   import ipaddress
   def mask_ip(ip: str | None) -> str | None:
       if not ip: return None
       try:
           addr = ipaddress.ip_address(ip)
           if addr.version == 4:
               return str(ipaddress.ip_network(f"{ip}/24", strict=False).network_address)
           else:
               return str(ipaddress.ip_network(f"{ip}/64", strict=False).network_address)
       except ValueError:
           return None
   ```

---

### SRE-115 · 🟡 P2 (Orta) · Her İzleyici Girişinde Tüm Odaya `system_join` WS Yayını ile Chat Soket DoS'u

* **Etkilenen Dosya:** `backend/app/routers/chat.py`
* **İlgili Satırlar:** [chat.py:418-424](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/chat.py#L418-L424)
* **Tetiklenme Noktası:** Popüler bir canlı yayına izleyicilerin sürekli bağlanıp ayrılması.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `chat.py` WebSocket bağlantı akışında:
   ```python
   if not is_host and room_name:
       await svc.add_viewer(stream_id, room_name, username)
       await publish_chat(stream_id, {"type": WS.SYSTEM_JOIN, "username": username})
   ```
   Her yeni izleyici bağlandığında o yayındaki TÜM izleyicilere `system_join` paketi yayımlanmaktadır.
2. 2.000 izleyicili bir yayında dakikada 600 kişi girip çıktığında:
   600 × 2.000 = **dakikada 1.200.000 WebSocket mesajı** (saniyede 20.000 paket)!
3. Bu durum istemci tarafında (Flutter mobil uygulaması) sohbet akışını bloke eder, UI render takılmalarına ve pil tüketimine yol açar; sunucu tarafında ise gereksiz Redis Pub/Sub ve CPU yükü yaratır.

#### 2. Çözüm / Refactoring Reçetesi
1. `system_join` yayını yalnızca izleyici sayısı 50'nin altında olan küçük yayınlarda gönderilmeli veya yalnızca VIP/Whale rozetli kullanıcılar katıldığında duyurulmalıdır:
   ```python
   viewer_count = await svc.get_viewer_count(stream_id)
   if viewer_count < 50:
       await publish_chat(stream_id, {"type": WS.SYSTEM_JOIN, "username": username})
   ```

---

### SRE-116 · 🟡 P2 (Orta) · DB, Redis, PgBouncer ve API Metriklerinin Scrape Dışında Kalması (Kör İzleme)

* **Etkilenen Dosya:** `deploy/scale/V2.1/nodeMonitor/config/teqlif/prometheus.yml`
* **İlgili Satırlar:** [prometheus.yml:15-50](file:///Users/tucibeyin/Desktop/teqlif/deploy/scale/V2.1/nodeMonitor/config/teqlif/prometheus.yml#L15-L50)
* **Tetiklenme Noktası:** Veritabanı havuz doygunluğu, Redis bellek taşması veya API 5xx hata fırtınaları.

#### 1. Sorunun Tanımı ve Arıza Modu
1. `nodeMonitor` üzerindeki `prometheus.yml` yapılandırması yalnızca `node1`..`node6` üzerindeki `node_exporter` (OS düzeyinde CPU, RAM, Disk) hedeflerini dinlemektedir.
2. Sistem için hayati önem taşıyan:
   - PostgreSQL veritabanı metrikleri (`postgres_exporter`: bağlantı sayısı, lock'lar, WAL boyutu),
   - PgBouncer havuz metrikleri (`pgbouncer_exporter`: bekleyen istemciler, havuz doygunluğu),
   - Redis metrikleri (`redis_exporter`: maxmemory kullanımı, evictions, bağlı istemciler),
   - FastAPI uygulama metrikleri (`/metrics`: HTTP 5xx hata oranları, p99 yanıt süreleri),
   hiçbir Prometheus job'unda yer almamaktadır.
3. Sonuç: PgBouncer havuzu kilitlendiğinde veya API 500 hataları tavan yaptığında Prometheus hiçbir uyarı vermez; operasyon ekibi sistem çöktüğünde bile sunucu CPU'su %90'ı geçmediği sürece kör kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. `prometheus.yml` içine `postgres`, `pgbouncer`, `redis` ve `fastapi` scrape job'ları eklenmelidir:
   ```yaml
   - job_name: 'postgres'
     static_configs:
       - targets: ['10.10.0.1:9187']
   - job_name: 'redis'
     static_configs:
       - targets: ['10.10.0.1:9121']
   - job_name: 'fastapi'
     static_configs:
       - targets: ['10.10.0.1:8000']
   ```
2. `alert_rules.yml` içine `PgBouncerPoolExhausted`, `RedisMemoryHigh`, `Http5xxRateHigh` kuralları tanımlanmalıdır.

---

### SRE-117 · 🔴 P0 (Kritik) · Consumable Alımlarda `originalTransactionId` Kullanılması Nedeniyle Sonraki Alımların Kilitlenmesi (`IAP_ALREADY_PROCESSED`)

* **Etkilenen Dosyalar:**
  * [`apple_verifier.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/store/apple_verifier.py#L88-L105) (Satır 97–105)
  * [`verify_purchase_command.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/wallet/commands/verify_purchase_command.py#L80-L96) (Satır 81–96)
* **İlgili Fonksiyonlar:** `AppleVerifier.verify`, `VerifyPurchaseCommand.execute`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Apple JWS Kimlik Hatası:** Apple App Store Server API v2 dokümantasyonuna göre; her bir consumable (tüketilebilir para/kredi paketi) satın alımında `transactionId` tekil ve benzersizdir. Ancak `originalTransactionId` o kullanıcının cihazındaki veya abonelik zincirindeki ilk işlemin kimliğidir.
2. `apple_verifier.py:98` satırında:
   ```python
   return PurchaseResult(
       transaction_id=claims["originalTransactionId"],  # <-- HATA: Consumable'da da originalTransactionId atanıyor!
       product_id=product_id,
       ...
   )
   ```
3. `VerifyPurchaseCommand.execute` (satır 82-96) ise replay koruması için şu kontrolü yapar:
   ```python
   existing = await self._session.execute(
       text("SELECT id FROM teqlik_transactions WHERE store_platform = :platform AND store_transaction_id = :tx_id LIMIT 1"),
       {"platform": platform, "tx_id": result.transaction_id},
   )
   if existing.fetchone() is not None:
       raise ConflictException(code="IAP_ALREADY_PROCESSED")
   ```
4. **Mali Yıkım:** Bir kullanıcı ilk kez `teqlik_pack_100` aldığında işlem kaydedilir. Bir hafta sonra tekrar `teqlik_pack_100` veya başka bir paket aldığında, Apple `originalTransactionId` olarak ilk işlemin ID'sini döndürür. Backend bu işlemi "replay" sayarak `ConflictException("IAP_ALREADY_PROCESSED")` fırlatır! Apple kullanıcının kredi kartından parayı çeker, ancak teqlif kullanıcının kredilerini yüklemez ve kullanıcı sonsuza dek kilitlenir!
5. **Hız Limiti (Velocity) Sızıntısı:** `_check_velocity` içinde `pipe.expire(key, 86400)` her işlemde çağrıldığı için sliding window yerine süreyi her alımda 24 saat öteleyen bir bug vardır; kullanıcı 3 gün arayla alım yapsa bile bakiye sıfırlanmaz.

#### 2. Çözüm / Refactoring Reçetesi
1. `apple_verifier.py` içinde ürün tipine göre tekil `transactionId` kullanılmalıdır:
   ```python
   # Consumable ürünlerde daima tekil transactionId, aboneliklerde originalTransactionId:
   tx_id = (
       claims["originalTransactionId"]
       if product_id in VALID_SUBSCRIPTION_IDS
       else claims.get("transactionId", claims["originalTransactionId"])
   )
   return PurchaseResult(
       transaction_id=str(tx_id),
       product_id=product_id,
       ...
       subscription_id=str(claims.get("originalTransactionId")) if product_id in VALID_SUBSCRIPTION_IDS else None,
   )
   ```
2. `_check_velocity` içinde `expire` yalnızca anahtar yeni oluşturulduğunda (`current is None`) set edilmeli veya Redis sliding log (zset) kullanılmalıdır.

> **✅ Çözüldü** — Commit `f9b8a018` · 2026-10-29 | Followup `63a7c451` · 2026-10-29
> `apple_verifier.py`: Tüm ürün türleri için `transaction_id = transactionId` (tekil); abonelik zinciri `subscription_id = originalTransactionId` üzerinden korunur. Re-subscribe ve plan upgrade artık `IAP_ALREADY_PROCESSED` almaz.
> `verify_purchase_command.py`: `_check_velocity` atomik Lua script ile yeniden yazıldı; TTL=-1 immortal key ve TOCTOU paralel istek race kapatıldı. `_PRODUCT_TRY_PRICES`'a abonelik fiyatları eklendi.

---

### SRE-118 · 🔴 P0 (Kritik) · Concat Görevinde Yanlış MinIO Node'u, Yetim Part Dosyaları ve Bozuk MP4 Transcode Açığı

* **Etkilenen Dosya:** [`tasks/stream_concat_task.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_concat_task.py#L90-L163) (Satır 96–163)
* **Zamanlama:** `worker.py` satır 4346: `cron(stream_concat_task, minute=set(range(0, 60, 2)))`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Edge Node Körlüğü:** `stream_concat_task.py:96` satırında `minio = _get_presign_client()` çağrılır. Bu fonksiyon yalnızca Node1 MinIO adresine bağlanır. Oysa V2.1 mimarisinde canlı yayın kayıtları Node3 veya Node4 (edge streaming nodes) üzerindeki MinIO'larda depolanmaktadır. Kayıt part'ları Node3/Node4'te ise `minio.fget_object` `NoSuchKey` veya `S3Error` verir ve birleştirme asla tamamlanamaz.
2. **Yetim Medya ve Disk İki Katına Çıkması:** Satır 147-151'de part'lar `UPDATE stream_recordings SET status = 'merged_and_purged'` olarak güncellenir ancak MinIO'daki fiziksel part dosyaları (`minio.remove_object`) SİLİNMEZ! Üzerine bir de `concat.mp4` yüklenir; sunucu depolama tüketimi iki katına çıkar ve diskler dolar.
3. **Bozuk MP4 Çıktısı (Codec / Resolution Mismatch):** `ffmpeg -f concat -c copy` parametresi, ancak tüm video parçaları birebir aynı codec, profil, bitrate ve çözünürlükte ise çalışır. Canlı yayın sırasında mobil ağ zayıfladığında WebRTC otomatik olarak çözünürlüğü (1080p -> 720p -> 480p) dinamik değiştirir. `copy` ile birleştirilen bu değişken çözünürlüklü part'lar bozuk, senkronu kaymış veya 2. parçada donan (corrupt) MP4 dosyaları üretir.

#### 2. Çözüm / Refactoring Reçetesi
1. Part kayıtlarının hangi MinIO node'unda olduğu `minio_key` veya node metadata'sından tespit edilip ilgili node'un MinIO istemcisi kullanılmalıdır.
2. Başarılı concat sonrasında fiziksel part dosyaları MinIO'dan silinmelidir:
   ```python
   for p in parts:
       if p["minio_key"]:
           try:
               minio.remove_object(settings.minio_bucket, p["minio_key"])
           except Exception as exc:
               logger.warning("Part silinemedi: %s", exc)
   ```
3. FFmpeg çağrısında `-c copy` yerine hızlı scale normalize filtresi eklenmeli veya fail durumunda re-encode fallback'i uygulanmalıdır.

> **✅ Çözüldü** — Commit `b75776f7` + Followup `a563864b` · 2026-10-29 | Followup-2 `e39b819f` · 2026-10-29
> `_get_presign_client()` → `_get_client_for_internal_url(settings.minio_endpoint)` (127.0.0.1:9000); encoder mc cp hedefi ile aynı.
> `_ffprobe_streams()` ile her part parametresi kontrol edilir. Birebir aynıysa `-c copy`; fark varsa `-filter_complex concat` + libx264 veryfast + first-part resolution (dikey yayını korur; sessiz part'ta `anullsrc` ile boş audio).
> Aday sorgusu: `JOIN live_streams WHERE status='ended' + NOT EXISTS (pending parts)` — 3+ part yayınlarda erken concat ve orphan part riski kapatıldı.
> `upload_file()` → `minio.fput_object()` doğrudan — orchestrator bypass (agent restart güveni).
> DB commit sonrası part dosyaları MinIO'dan best-effort silinir.
> Followup-2: `anullsrc=d=3600` → `d=probe["duration"]` (1 saatlik donma/CPU tuzağı kapatıldı). `_ffprobe_streams` `-show_format` + audio `sample_rate`/`channels` eklendi; `all_same` kontrolüne dahil edildi (44.1kHz mono + 48kHz stereo geçişinde `-c copy` bozulması engellendi).

---

### SRE-119 · 🔴 P0 (Kritik) · `_delayed_close_stream` Fallback'inde Yanlış Node Sorgulanması Nedeniyle Aktif Yayınların Kapatılması

* **Etkilenen Dosya:** [`routers/webhooks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/webhooks.py#L213-L235) (Satır 213–235)
* **İlgili Fonksiyon:** `_delayed_close_stream`

#### 1. Sorunun Tanımı ve Arıza Modu
1. LiveKit'ten `room_finished` veya host disconnect webhook'u geldiğinde, 60 saniyelik grace period sonunda `_delayed_close_stream` fonksiyonu odanın hâlâ aktif olup olmadığını kontrol eder.
2. Satır 216-217'de şu kod çalışır:
   ```python
   from app.services.edge_orchestrator import orchestrator, ServiceType
   node = await orchestrator.allocate_node(ServiceType.MEDIA)
   api_url = node["livekit_url"]
   ```
3. **Kritik Yanlış Yönlendirme:** `orchestrator.allocate_node` o an rastgele veya round-robin bir node seçer. Eğer yayın `node4` üzerinde devam ediyorsa ve `allocate_node` `node3`'ü seçerse; `node3` üzerindeki LiveKit'e sorulur.
4. `node3`'te o oda bulunamaz (`res.rooms` içinde yoktur). Fonksiyon odanın kapandığına hükmeder ve `force_close_stream(db, room_name)` çağırarak **Node4'te canlı yayında konuşmakta olan yayıncının yayınını veritabanında öldürür!**
5. İzleyicilerin bağlantısı kopar, yayın "bitti" olarak işaretlenir.

#### 2. Çözüm / Refactoring Reçetesi
1. Rastgele `allocate_node` çağrısı derhal kaldırılmalıdır.
2. Odanın hangi node'da açıldığı veritabanındaki `LiveStream` kaydından (`stream.livekit_url` veya `stream.node_id`) okunmalıdır:
   ```python
   async with AsyncSessionLocal() as db:
       stream = await db.scalar(select(LiveStream).where(LiveStream.room_name == room_name))
       if not stream or not stream.is_live:
           return
       api_url = stream.livekit_url or settings.livekit_url
   ```
3. Oda durumu yalnızca yayının bizzat barındırıldığı yetkili LiveKit node'undan sorgulanmalıdır.

> **✅ Çözüldü** — Commit `d58be2d3` · 2026-10-29 | Followup `e39b819f` · 2026-10-29 | Followup-2 `9a5756ea` · 2026-10-29
> `_delayed_close_stream` fallback'teki `orchestrator.allocate_node(ServiceType.MEDIA)` (rastgele tek node) kaldırıldı.
> Followup: `lk_list_all_rooms()` → DB-first + yetkili node hedefli `ListRoomsRequest(names=[room])` yaklaşımı (`webhooks.py` + `worker.py:delayed_close_stream_task`).
> Tek node HTTP timeout veya agent restart / edge:metrics TTL boşluğu: `stream.livekit_url` doğrudan kullanılır, Redis bağımlılığı yok.
> `except Exception` fail-open kapatıldı: yetkili node hatası = fail-safe `return` (aktif yayın kapatılmaz). DB hatası da `return`.
> Followup-2: `settings.livekit_url` (mevcut değil) → `settings.edge_livekit_urls[0]`; `auth_url` boşsa fail-safe `return` (AttributeError kapatıldı).

---

### SRE-120 · 🟠 P1 (Yüksek) · Mobil Hata Loglarında IP Sahtelemesi/Global Drop ve `entry.details` Log Injection (CWE-117)

* **Etkilenen Dosya:** [`routers/client_log.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/client_log.py#L53-L97) (Satır 53–97)
* **İlgili Fonksiyonlar:** `_rate_check`, `client_log`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Global Log Drop (IP Maskelemesi):** `_rate_check` fonksiyonunda `ip = request.client.host` doğrudan kullanılır. Nginx veya Cloudflare ters proxy'si arkasında çalışıldığında, `request.client.host` daima yerel proxy IP'si (örn. `127.0.0.1` veya Docker bridge) olur.
2. Bu durumda tüm dünyadaki on binlerce mobil uygulama tek bir IP olarak sayılır. Dakikada 20 log geldikten sonra, dünya genelindeki TÜM mobil istemcilerin hata ve crash raporları sessizce drop edilir; operasyon ekibi mobil çökmelerden tamamen habersiz kalır.
3. **Log Injection (CWE-117) & Disk DoS:** Satır 94-95'te:
   ```python
   if entry.details:
       logger.warning("[CLIENT_LOG] details | tag=%s | %s", _sanitize(entry.tag), entry.details)
   ```
   `entry.details` bir `dict[str, Any]` nesnesidir ve hiçbir `_sanitize` işlemine tabi tutulmadan doğrudan Python `logging` ile systemd journalctl'e yazılır.
4. Kötü niyetli bir kullanıcı `details` içerisine `\n2026-10-26 21:00:00 [CRITICAL] Admin session started` gibi sahte log satırları enjekte edebilir (CRLF log forging) veya 10 MB'lık derin iç içe geçmiş JSON göndererek log dosyalarını ve diski doldurabilir.

#### 2. Çözüm / Refactoring Reçetesi
1. İstemci IP'si `core/ip_utils.py` üzerinden `CF-Connecting-IP` / `X-Forwarded-For` başlıkları doğrulanarak çözülmelidir.
2. `entry.details` JSON formatına çevrilip `_sanitize` filtresinden geçirilmeli ve maksimum 2.000 karakterle sınırlandırılmalıdır:
   ```python
   if entry.details:
       details_str = json.dumps(entry.details, ensure_ascii=False, default=str)[:2000]
       logger.warning("[CLIENT_LOG] details | tag=%s | %s", _sanitize(entry.tag), _sanitize(details_str, max_len=2000))
   ```

---

### SRE-121 · 🟠 P1 (Yüksek) · Favoriden Çıkarılırken İlgisiz Beğeninin (`ListingLike`) Sessizce Silinmesi ve Cache Desync

* **Etkilenen Dosya:** [`routers/favorites.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/favorites.py#L75-L120) (Satır 75–120)
* **İlgili Fonksiyonlar:** `add_favorite`, `remove_favorite`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **İlişkisiz Beğeninin Ezilmesi:** `remove_favorite` (`DELETE /api/favorites/{listing_id}`) fonksiyonunda şu satırlar yer alır:
   ```python
   if fav:
       await db.delete(fav)
   if like_obj:
       await db.delete(like_obj)  # <-- HATA: Kullanıcı beğeniyi değil sadece favoriyi kaldırmak istedi!
   await db.commit()
   ```
   Kullanıcı bir ilanı beğenmiş (`ListingLike`) ancak daha sonra favori listesinden çıkarmak istediğinde, kullanıcının haberi olmaksızın o ilana verdiği beğeni de silinir. İlanın `likes_count` değeri düşer ve beğeni durumu ezilir.
2. **Double-Click Yarış Durumu (Race Condition):** `add_favorite` fonksiyonunda `existing_fav` ve `existing_like` `SELECT` ile kontrol edilir. Kullanıcı mobilde butona çift tıkladığında iki istek eşzamanlı geçer; ikisi de `existing_fav is None` görür ve `db.add()` yapar. PostgreSQL `unique_user_listing_favorite` kısıtında `IntegrityError` patlar ve kullanıcıya HTTP 500 döner.
3. **Redis Cache Desync:** Silme ve ekleme işlemleri `LikeService` üzerinden geçmediği için `listing:liked_by:{id}` Redis Set'i invalid edilmez; PostgreSQL ile Redis beğeni listeleri arasında tutarsızlık oluşur.

#### 2. Çözüm / Refactoring Reçetesi
1. Favori ve beğeni domain modelleri birbirinden ayrılmalıdır; `remove_favorite` ASLA `ListingLike` nesnesini silmemelidir.
2. Ekleme işlemi `ON CONFLICT DO NOTHING` veya `IntegrityError` yakalayan idempotent bir yapıya kavuşturulmalıdır.
3. Beğeni ile ilgili tüm durum değişiklikleri `LikeService.toggle_listing_like` üzerinden yürütülerek Redis set'leri ile tam senkron tutulmalıdır.

---

### SRE-122 · 🟠 P1 (Yüksek) · Story Yükleme Sırasında Senkron FFmpeg Transcoding ile Uvicorn Event Loop Açlığı

* **Etkilenen Dosya:** [`services/story_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/story_service.py#L48-L97) (Satır 48–97, 325–330)
* **İlgili Fonksiyonlar:** `_compress_video`, `upload_story`

#### 1. Sorunun Tanımı ve Arıza Modu
1. Mobil istemciden 20 MB'a kadar bir video hikayesi yüklendiğinde, `POST /api/stories` HTTP istek thread'i doğrudan `_compress_video` metodunu çağırır.
2. `_compress_video` fonksiyonu Uvicorn'un çalıştığı uygulama sunucusunda (Node1) `ffmpeg -vf scale=-2:720 -c:v libx264 -crf 28 ...` subprocess'i başlatır ve `await asyncio.wait_for(proc.communicate(), timeout=120)` ile 120 saniyeye kadar süreci bekletir.
3. **CPU Açlığı ve DoS:** Video sıkıştırma yoğun CPU çekirdeği tüketir. Eşzamanlı 5 kullanıcı video yüklediğinde Node1'in tüm CPU çekirdekleri %100'e vurur. Uvicorn event loop'u I/O ve soket işlemlerini zamanında işleyemez (event loop starvation).
4. Canlı yayın sohbeti, DM mesajları ve teklif verme gibi gerçek zamanlı HTTP/WS istekleri yanıtsız kalarak 504 Gateway Timeout'a düşer.

#### 2. Çözüm / Refactoring Reçetesi
1. HTTP isteği videoyu MinIO'ya ham olarak kaydetmeli, DB'ye `status = 'processing'` olarak yazmalı ve derhal HTTP 202 Accepted dönmelidir.
2. FFmpeg sıkıştırma ve thumbnail çıkarma işlemi ARQ worker havuzuna (`video_tasks.py`) delege edilmeli ve Uvicorn süreçleri CPU yükünden izole edilmelidir.

---

### SRE-123 · 🟠 P1 (Yüksek) · PgBouncer Transaction Pooling Altında `VACUUM ANALYZE` Nedeniyle Task Çökmesi ve Kilitsiz Silme

* **Etkilenen Dosya:** [`backend/app/worker.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L310-L344) (Satır 310–344)
* **İlgili Görevler:** `cleanup_old_notifications_task`, `cleanup_old_analytics_task`

#### 1. Sorunun Tanımı ve Arıza Modu
1. `cleanup_old_notifications_task` ve `cleanup_old_analytics_task` her gün / her hafta çalışarak eski kayıtları siler.
2. Silme işleminin ardından şu kod çalıştırılır:
   ```python
   async with engine.connect() as conn:
       await conn.execution_options(isolation_level="AUTOCOMMIT")
       await conn.execute(text("VACUUM ANALYZE notifications"))
   ```
3. **PgBouncer Çökmesi:** `settings.use_pgbouncer = True` olduğunda sistem PgBouncer üzerinden (port 6432) transaction pooling modunda çalışır. PostgreSQL ve PgBouncer kurallarına göre `VACUUM` komutları transaction pooling havuzunda yürütülemez; asyncpg `VACUUM cannot run inside a transaction block` hatası fırlatır ve her gece bu ARQ görevleri hata vererek çöker.
4. **Milyonluk Tekil Silme Kilitlenmesi:** `DELETE FROM notifications WHERE created_at < NOW() - INTERVAL '30 days'` tek bir devasa SQL ifadesiyle çalıştırılır. Milyonlarca satır tek transaction'da silinirken Postgres WAL şişer, `notifications` tablosu üzerinde `RowExclusiveLock` dakikalarca tutulur ve canlı kullanıcıların bildirimleri kilitlenir.

#### 2. Çözüm / Refactoring Reçetesi
1. `VACUUM ANALYZE` uygulama kodundan tamamen kaldırılmalıdır; bu işlem PostgreSQL'in yerel `autovacuum` daemon'ına bırakılmalı veya bağımsız bir cron scriptiyle doğrudan 5432 portuna bağlanarak çalıştırılmalıdır.
2. Silme işlemi 5.000'lik chunk'lar halinde sınırlandırılmalıdır:
   ```python
   while True:
       res = await db.execute(text("""
           DELETE FROM notifications
           WHERE id IN (
               SELECT id FROM notifications
               WHERE created_at < NOW() - INTERVAL '30 days'
               LIMIT 5000
           )
       """))
       await db.commit()
       if res.rowcount == 0:
           break
   ```

---

### SRE-124 · 🟠 P1 (Yüksek) · Limitsiz `SELECT * FROM follows` Bellek Patlaması (OOM) ve Devasa Redis Pipeline Kilitlenmesi

* **Etkilenen Dosya:** [`services/influence_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/influence_service.py#L33-L53) (Satır 33–53)
* **İlgili Fonksiyon:** `compute_influence_scores`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Unbounded Query & OOM:** Sosyal etki skorlarını hesaplayan `compute_influence_scores` fonksiyonu, `SELECT follower_id, followed_id FROM follows` sorgusunu hiçbir limit veya filtre olmadan çalıştırır ve `fetchall()` ile tüm tabloyu Python sürecinin RAM belleğine yükler.
2. Platform büyüdüğünde (örneğin 200.000 kullanıcı ve 10 milyon takip ilişkisi), bu veri ve üzerine kurulan `networkx.DiGraph` nesnesi 10+ GB RAM tüketerek ARQ worker'ın Linux OOM Killer tarafından öldürülmesine neden olur.
3. Ayrıca `status = 'accepted'` filtresi olmadığı için reddedilen veya askıda bekleyen takip talepleri de hesaplamaya katılarak bot manipülasyonuna açık hale gelir.
4. **Redis Multi-Bulk Tıkanması:** `scores` sözlüğündeki 200.000 kullanıcı tek bir `redis.pipeline()` içine doldurulur ve tek seferde `await pipe.execute()` edilir. Redis socket buffer'ı kilitlenir ve Redis sunucusu diğer tüm canlı istekleri timeout'a düşürür.

#### 2. Çözüm / Refactoring Reçetesi
1. Yalnızca onaylı takipler çekilmeli (`WHERE status = 'accepted'`) ve bellek içi tam graf yerine sparse matrix veya disk destekli SciPy sparse solver kullanılmalıdır.
2. Redis pipeline yazımı 1.000'lik gruplar (chunks) halinde bölünmelidir:
   ```python
   chunk_size = 1000
   items = list(scores.items())
   for i in range(0, len(items), chunk_size):
       pipe = redis.pipeline()
       for uid, score in items[i:i + chunk_size]:
           pipe.setex(f"influence_rank:{uid}", _REDIS_TTL, str(score))
       await pipe.execute()
   ```

---

### SRE-125 · 🟡 P2 (Orta) · Her Feed İsteğinde `SELECT DISTINCT category FROM listings` Full Table Scan ve İndekssiz Sort

* **Etkilenen Dosya:** [`services/recommendation_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/recommendation_service.py#L315-L321) (Satır 315–321, 390–394)
* **İlgili Fonksiyonlar:** `get_personalized_feed`, `_ids_from_categories`

#### 1. Sorunun Tanımı ve Arıza Modu
1. **Full Table Scan:** Her kullanıcı feed yenilediğinde (`GET /api/feed`), keşif havuzu için şu sorgu PostgreSQL'e gönderilir:
   ```sql
   SELECT DISTINCT category FROM listings WHERE status = 'active' AND category IS NOT NULL LIMIT 50;
   ```
   `listings` tablosunda 500.000 ilan varken, `DISTINCT` sorgusu veritabanında büyük bir Sequential Scan veya HashAggregate maliyeti yaratır. Kategoriler statik olmasına rağmen her HTTP isteğinde veritabanına gidilir.
2. **Fonksiyonel Sıralama (Sort Spill):** `_ids_from_categories` içinde rastgele seçim için `ORDER BY (hashtext(l.id::text || :salt) & 2147483647)` kullanılır. Bu ifade hiçbir B-Tree indeksini kullanamaz; Postgres filtrelenen on binlerce ilanı `work_mem`'e çeker, hash hesaplar ve CPU üzerinde disk temp file kullanarak full sort yapar.
3. Yüksek eşzamanlılıkta PostgreSQL CPU kullanımı %100'e vurur.

#### 2. Çözüm / Refactoring Reçetesi
1. Aktif kategoriler doğrudan `Category` tablosundan veya 24 saatlik Redis önbelleğinden okunmalıdır.
2. Rastgele ilan çekimi için pahalı `ORDER BY hashtext()` yerine, Redis set'lerinden `SRANDMEMBER` ile ID örneklemesi yapılmalı veya `TABLESAMPLE SYSTEM` kullanılmalıdır.

---

### SRE-126 · 🟡 P2 (Orta) · Şikayet Endpoint'inde Pydantic Şeması ve Karakter Sınırı Olmaması (Disk DoS ve TOCTOU)

* **Etkilenen Dosya:** [`routers/reports.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/reports.py#L16-L41) (Satır 16–41)
* **İlgili Fonksiyon:** `report_listing`

#### 1. Sorunun Tanımı ve Arıza Modu
1. `report_listing` endpoint'i `payload: dict` parametresi alır; hiçbir Pydantic şema doğrulaması yoktur.
2. `reason = (payload.get("reason") or "").strip()` ifadesinde hiçbir uzunluk sınırı (`max_length`) bulunmaz. Kötü niyetli bir kullanıcı 5-10 MB'lık devasa metin yükleriyle `POST /api/reports` çağrısı yaparak `reports` tablosunda kontrolsüz disk büyümesi (Storage DoS) yaratabilir.
3. Çift şikayeti engellemek için yapılan `existing = await db.scalar(select(Report)...)` kontrolü kilitsizdir. Eşzamanlı iki istek gönderildiğinde ikisi de kontrolü geçer ve `db.add()` yapar. Veritabanında unique kısıt varsa HTTP 500 IntegrityError döner; kısıt yoksa mükerrer kayıtlar birikir.

#### 2. Çözüm / Refactoring Reçetesi
1. Katı bir Pydantic modeli tanımlanmalıdır:
   ```python
   class ReportCreateSchema(BaseModel):
       listing_id: int
       reason: str = Field(min_length=3, max_length=1000)
   ```
2. Şikayet kaydı `ON CONFLICT DO NOTHING` ile eklenmeli veya `IntegrityError` yakalanarak temiz bir `ConflictException` (409) dönülmelidir.

---

### SRE-127 · 🔴 P0 (Kritik) · `calculate_user_budgets` Fonksiyonunda On Binlerce Sıralı UPDATE ve Açık Transaction
* **Etkilenen Dosya:** `backend/app/services/analytics_processor.py`
* **İlgili Satırlar:** 80–97
* **İlgili Fonksiyon:** `calculate_user_budgets`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
# Bulk update PostgreSQL
updated = 0
async with AsyncSessionLocal() as db:
    for user_id_raw, p90 in rows:
        try:
            uid = int(user_id_raw)
            budget = float(p90)
            await db.execute(
                text("UPDATE users SET max_budget = :budget WHERE id = :uid"),
                {"budget": budget, "uid": uid},
            )
            updated += 1
        except Exception as row_exc:
            logger.warning("[BudgetCalc] user_id=%s güncellenemedi: %s", user_id_raw, row_exc)
    await db.commit()
```
1. ClickHouse'dan son 7 günün analitiğine göre 50.000 veya 100.000 kullanıcının `p90_budget` verisi döner.
2. `async with AsyncSessionLocal() as db:` bloğu içinde, her kullanıcı için ayrı bir `UPDATE users SET max_budget = ...` SQL sorgusu ağ üzerinden sıralı (sequential) olarak gönderilir.
3. 50.000 kullanıcılık bir güncelleme, 50.000 ayrı network round-trip demektir. Bu işlem 15–40 dakika sürer.
4. Bu süre boyunca:
   - Tek bir PostgreSQL transaction'ı açık kalır; `users` tablosunda güncellenen 50.000 satır üzerinde exclusive row lock tutulur.
   - PgBouncer transaction pooling modunda bu connection kilitlenir; diğer worker'lar connection starvation yaşar.
   - PostgreSQL autovacuum ve WAL (Write-Ahead Logging) şişer, checkpoint I/O patlaması yaşanır.
   - Bu esnada bir kullanıcı profil güncellerse veya bakiye yüklerse kilitlenme (deadlock) oluşur.
   - En kritiği: 49.999. satırda geçici bir ağ kesintisi veya worker timeout yaşanırsa, transaction rollback olur ve 40 dakikalık işlem çöpe gider.

#### 2. Çözüm / Refactoring Reçetesi
1. İşlem tek tek `UPDATE` sorgularıyla değil, 500'lük chunk'lar halinde `VALUES (...)` ile set-based tek bir `UPDATE ... FROM (VALUES ...)` ifadesiyle veya `execute_values` mantığıyla çalıştırılmalıdır.
2. Her chunk bağımsız kısa bir transaction'da commit edilmelidir:
```python
CHUNK_SIZE = 500
for i in range(0, len(rows), CHUNK_SIZE):
    chunk = rows[i:i + CHUNK_SIZE]
    async with AsyncSessionLocal() as db:
        values_str = ", ".join(f"({int(uid)}, {float(p90):.2f})" for uid, p90 in chunk)
        await db.execute(text(f"""
            UPDATE users AS u
            SET max_budget = v.budget
            FROM (VALUES {values_str}) AS v(id, budget)
            WHERE u.id = v.id
        """))
        await db.commit()
```

> **✅ Çözüldü** — Commit `894b71ca` · 2026-10-29 | Followup `9a5756ea` · 2026-10-29
> 50.000 sıralı tekil UPDATE (tek uzun transaction, 15-40dk row lock) → 500'lük chunk'larda `UPDATE users AS u SET max_budget = v.budget FROM (VALUES ...) AS v(id, budget) WHERE u.id = v.id` set-based sorgusuna dönüştürüldü.
> Her chunk bağımsız kısa transaction; tek chunk hatası diğerlerini durdurmaz.
> NaN/Inf/tip dönüşüm hataları chunk başında filtrelenerek Postgres'e geçersiz değer ulaşması engellendi.
> PgBouncer connection starvation, deadlock ve WAL şişmesi riski kapatıldı.
> Followup: `_MAX_BUDGET_CAP=9_999_999_999.99` (NUMERIC(12,2)) + `_MAX_USER_ID=2_147_483_647` (32-bit INT) sınırları; `min(round(budget, 2), cap)` ile tek poison-pill değer chunk'ı düşüremez. `res.rowcount` ile gerçek güncellenen satır sayısı loglanır.

---

### SRE-128 · 🔴 P0 (Kritik) · Doğrulanmış Hesaplarda Tavan Sınır (Hard Ceiling) Olmaması ve Müzayede Sabotajı (Troll Bid Bypass)
* **Etkilenen Dosya:** `backend/app/services/bid_validation_service.py`
* **İlgili Satırlar:** 31–60
* **İlgili Fonksiyon:** `validate_troll_bid`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
bid_threshold  = _HIGH_BID_THRESHOLD_TL if user.is_verified else _HIGH_BID_THRESHOLD_UNVERIFIED
bid_multiplier = _HIGH_BID_MULTIPLIER if user.is_verified else _HIGH_BID_MULTIPLIER_UNVERIFIED

is_high_bid = (
    data_amount > bid_threshold
    or (
        current_bid >= _MULTIPLIER_MIN_BASE_TL
        and data_amount > current_bid * bid_multiplier
    )
)

if is_high_bid and (not user.phone or not user.phone_verified):
    ...
    raise ForbiddenException(code=_verify_code)
```
1. Fonksiyonun amacı aşırı yüksek ve mantıksız teklifleri (troll bids) engellemektir.
2. Ancak mantık şu şekildedir: `if is_high_bid and (not user.phone or not user.phone_verified): raise ForbiddenException`.
3. Eğer kullanıcının telefon doğrulaması varsa (`user.phone and user.phone_verified == True`), bu `if` koşulu `False` döner ve fonksiyon **hiçbir hata fırlatmadan sessizce çıkar**.
4. Sistemde doğrulanmış hesaplar için hiçbir **mutlak tavan sınır (hard ceiling)**, cüzdan teminatı veya maksimum katlama sınırı yoktur!
5. SMS doğrulaması yapmış herhangi bir kullanıcı, 100 TL'lik bir canlı yayın müzayedesine `1.000.000.000 TL` (1 milyar TL) teklif girebilir. Müzayede sistemi bu teklifi kabul eder, müzayede anında bu fiyattan kapanır ve yayıncı ürünü satamaz çünkü alıcının böyle bir bakiyesi yoktur.
6. Canlı yayın müzayedesi tek bir hamlede tamamen kilitlenir ve sabote edilir.

#### 2. Çözüm / Refactoring Reçetesi
1. Doğrulanmış hesaplar için de mutlak bir tavan ve maksimum katlama kontrolü uygulanmalıdır.
2. Mevcut teklifin 10 katından fazlası veya cüzdan bakiyesinin / kart ön provizyonunun katbekat üzerindeki teklifler doğrulanmış olsa dahi engellenmelidir:
```python
# Mutlak tavan kontrolü (Doğrulanmış dahi olsa)
ABSOLUTE_MAX_BID_TL = 500_000.0  # Özel teminatsız girilebilecek azami sınır
MAX_MULTIPLIER_HARD = 15.0      # Mevcut teklifin 15 katından fazlası direkt troll sayılır

if data_amount > ABSOLUTE_MAX_BID_TL:
    raise BadRequestException(code="BID_EXCEEDS_MAX_PLATFORM_LIMIT")

if current_bid >= _MULTIPLIER_MIN_BASE_TL and data_amount > current_bid * MAX_MULTIPLIER_HARD:
    raise BadRequestException(code="BID_MULTIPLIER_EXCEEDED")
```

> **✅ Çözüldü** — Commit `c2f5bd6e` · 2026-10-29 | Followup `2a4c47c1` · 2026-10-29
> `validate_troll_bid` iki katmanlı yapıya dönüştürüldü.
> Katman 1 (herkese, telefon doğrulaması bypass etmez): `_ABSOLUTE_MAX_BID_TL=500_000` + `math.isfinite` → `BID_EXCEEDS_MAX_PLATFORM_LIMIT`; `effective_base = max(current_bid, 500)` × 15 → `BID_MULTIPLIER_EXCEEDED` (100 TL müzayedelerde bypass kapatıldı). Her iki kontrol `_log_fraud_attempt` ile kayıt altına alınır.
> Katman 2 (değişmedi): telefon doğrulaması olmayanlar için mevcut soft ceiling.
> Önceki durum: doğrulanmış hesap → hard ceiling yok → 1 milyar TL teklif kabul ediliyordu.
> Followup: `locales/{tr,en,de,ru,ar}.json` — `BID_EXCEEDS_MAX_PLATFORM_LIMIT` + `BID_MULTIPLIER_EXCEEDED` mesajları eklendi (Flutter ErrorMapper backend mesajını doğrudan gösterir).

---

### SRE-129 · 🔴 P0 (Kritik) · Node1 Kurulum Scriptinde `postgresql-17-pgvector` Paketinin Eksik Olması ve Vektör Extension Çökmesi
* **Etkilenen Dosyalar:** `deploy/scale/V2.1/scripts/bootstrap_node1.sh`, `backend/app/database.py`
* **İlgili Satırlar:** `bootstrap_node1.sh:109-113`, `database.py:39-47`
* **İlgili Fonksiyon:** `install_postgresql` & `init_extensions`

#### 1. Sorunun Tanımı ve Arıza Modu
```bash
# deploy/scale/V2.1/scripts/bootstrap_node1.sh:
install_postgresql() {
    log_step "PostgreSQL ${PG_VERSION}"
    apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
    log_ok "PostgreSQL ${PG_VERSION} kuruldu"
}
```
1. `bootstrap_node1.sh` PostgreSQL 17 sunucusunu ve client'ını kurar, ancak `postgresql-17-pgvector` paketini kurmaz.
2. Uygulama ayağa kalktığında `database.py` içindeki `init_extensions()` fonksiyonu çalışır:
```python
async def init_extensions() -> None:
    try:
        async with engine.begin() as conn:
            await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    except Exception:
        pass
```
3. Paket kurulu olmadığı için PostgreSQL `vector.control` dosyasını bulamaz ve hata verir.
4. `database.py` bu hatayı `except Exception: pass` ile sessizce yutar!
5. Sonuç: Veritabanında `vector` tipi hiçbir zaman oluşmaz. Alembic migration'ı `preference_embedding: Mapped[Optional[Any]] = mapped_column(Vector(384))` tablosunu oluşturmaya çalıştığında veya kullanıcı profil/öneri sorgularında `UndefinedObject: type "vector" does not exist` hatası patlar ve uygulama çöker.

#### 2. Çözüm / Refactoring Reçetesi
1. `bootstrap_node1.sh` içine pgvector paketi eklenmelidir:
```bash
apt-get install -y -qq "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" "postgresql-${PG_VERSION}-pgvector"
```
2. `database.py` içindeki `init_extensions()` sessiz `pass` yerine hatayı loglamalı veya startup'ta exception fırlatarak eksik paketin hemen fark edilmesini sağlamalıdır.

> **✅ Çözüldü** — Commit `d652c1ba` · 2026-10-29
> `bootstrap_node1.sh:install_postgresql`: `postgresql-${PG_VERSION}-pgvector` eklendi (fresh node1 kurulumunda paket eksik kalıyordu).
> `database.py:init_extensions`: `except Exception: pass` → `CRITICAL` log + `pg_extension` doğrulama sorgusu. Extension oluşturulamaz veya aktif değilse paket eksikliğini açıkça loglar; sessiz hata yutma kapatıldı.
> Mevcut prod DB'de extension zaten aktif (`vector 0.8.6` — `teqlif` DB'de doğrulandı).

---

### SRE-130 · 🔴 P0 (Kritik) · Staging Redis Konfigürasyonunun `/etc/redis` Dizinine Yazılması ve `apply_secrets` Tarafından Atlanması
* **Etkilenen Dosya:** `deploy/scale/V2.1/scripts/bootstrap_node5.sh`
* **İlgili Satırlar:** 61–63, 101–114
* **İlgili Fonksiyon:** `install_redis_staging` & `apply_secrets`

#### 1. Sorunun Tanımı ve Arıza Modu
```bash
# bootstrap_node5.sh:
if [ -n "${SECRETS_FILE:-}" ]; then
    apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard
fi
...
cat > /etc/redis/redis-staging.conf <<'EOF'
bind 127.0.0.1
port 6379
requirepass <staging_redis_pass>
daemonize no
...
EOF
```
1. Node5 staging sunucusunda `apply_secrets` fonksiyonu sadece `/project/teqlif/config` ve `/etc/wireguard` dizinlerindeki şablon değişkenlerini değiştirir.
2. Ancak staging Redis konfigürasyonu `/etc/redis/redis-staging.conf` içine yazılmaktadır!
3. Bu nedenle `requirepass <staging_redis_pass>` satırındaki placeholder hiçbir zaman gerçek şifre ile değiştirilmez. Redis sunucusu parola olarak harfi harfine `"<staging_redis_pass>"` string'ini bekler.
4. Öte yandan `/project/teqlif/config/staging.env` dosyasındaki `<staging_redis_pass>` başarıyla gerçek secret string ile değiştirilmiştir.
5. Sonuç: Staging ortamında FastAPI veya Celery worker başladığında Redis'e gerçek şifreyle bağlanmaya çalışır, Redis ise `WRONGPASS invalid username-password pair` hatası döner. Tüm Staging API ve worker'ları Redis'e bağlanamadığı için 500 hatası verir.

#### 2. Çözüm / Refactoring Reçetesi
1. Redis staging konfigürasyon dosyası `/project/teqlif/config/redis/redis-staging.conf` yoluna taşınmalı (Node1 mimarisiyle uyumlu olarak) veya `apply_secrets` çağrısına `/etc/redis` dizini eklenmelidir:
```bash
if [ -n "${SECRETS_FILE:-}" ]; then
    apply_secrets "${SECRETS_FILE}" /project/teqlif/config /etc/wireguard /etc/redis
fi
```

#### ✅ Çözüm Damgası
* **Commit:** `6dbc6104` · 2026-10-29 — `apply_secrets` `/etc/redis` eklendi; pgvector staging
* **Followup commit:** `359f4286` · 2026-10-29 — İzin + sed kaçış düzeltmeleri:
  * `_common.sh`: `setup_teqlif_directories` chown listesine `/project/teqlif/config` eklendi; `apply_secrets` sed `& \ |` kaçışı + post-secrets `700/600` normalizasyon bloğu
  * `bootstrap_node5.sh`: Redis conf `/etc/redis` → `/project/teqlif/config/redis/redis-staging.conf` (Debian `2750 redis:redis` çakışması giderildi)
  * `bootstrap_node3.sh` + `bootstrap_node4.sh`: `setup_livekit` sonrası `logs/livekit` `chown tucibeyin`
* **Durum:** Tüm node'lara (node1–6 + nodeMonitor) deploy edildi.

---

### SRE-131 · 🔴 P0 (Kritik) · `capture_hype_highlight` İçinde Rastgele Node ile WHEP 404 Hatası ve MinIO Yerine Yerel Diske Kayıt
* **Etkilenen Dosya:** `backend/app/tasks/video_tasks.py`
* **İlgili Satırlar:** 24, 95–103, 143–148
* **İlgili Fonksiyon:** `capture_hype_highlight`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
node = await orchestrator.allocate_node(ServiceType.MEDIA)
lk_http = node["livekit_url"] if node else (settings.edge_livekit_urls[0] if settings.edge_livekit_urls else "")
whep_url = f"{lk_http}/rooms/{room_name}/whep"
token = _make_livekit_recorder_token(room_name, room_id)
...
cmd = ["ffmpeg", "-y", "-headers", f"Authorization: Bearer {token}\r\n", "-i", whep_url, "-t", str(_CAPTURE_SECONDS), "-c", "copy", str(output)]
...
await _insert_highlight_record(room_id, host_id, str(output))
```
1. LiveKit odaları belirli bir edge media sunucusunda (örneğin Node4) oluşturulur.
2. Ancak `capture_hype_highlight` fonksiyonu odanın hangi node'da olduğunu veritabanından veya Redis'ten kontrol etmez; `orchestrator.allocate_node(ServiceType.MEDIA)` çağırarak rastgele veya least-loaded bir media node seçer!
3. Eğer oda Node4'te canlı yayındayken `allocate_node` Node3'ü dönerse, FFmpeg `http://10.10.0.3:7880/rooms/{room_name}/whep` adresine bağlanır. Node3'te böyle bir oda olmadığı için LiveKit HTTP 404 döner, FFmpeg `rc=1` ile patlar ve hype anının klibi çekilemez (%50+ başarısızlık oranı).
4. İkinci arıza modu: Video başarıyla çekilse dahi `_highlight_path` çıktısı yerel diske (`static/highlights/highlight_{room_id}.mp4`) kaydedilir. MinIO/S3 nesne depolamasına yüklenmez. Çoklu sunucu mimarisinde istemciler API'ye Node1 üzerinden bağlandığında dosya Node2 worker'ının yerel diskinde kalır ve 404 Not Found döner.

#### 2. Çözüm / Refactoring Reçetesi
1. Canlı yayının hangi LiveKit node'unda barındığı `LiveStream.livekit_url` veya Redis `stream:{id}:node` üzerinden deterministik olarak okunmalıdır.
2. Çekilen MP4 dosyası derhal `storage_service.upload_file` ile MinIO `highlights` bucket'ına yüklenmeli, veritabanına CDN URL'i kaydedilmeli ve yerel geçici dosya temizlenmelidir.

#### ✅ Çözüm Damgası
* **Commit:** `9de8f281` · 2026-10-29 (node seçimi — DB-first)
* **Commit:** `03f570f7` · 2026-10-30 (Seçenek A — gerçek implementasyon)
* **Commit:** `2d2b7319` · 2026-10-30 (followup — DUPLICATE_IDENTITY + log sızıntısı + stop_after zamanlama + node1 bootstrap)
* **Değişiklik:**
  * `livekit_subscriber.py` — `--stop-after N` ve `--identity` parametreleri eklendi; `_make_token` identity desteği; `_stop_after_open` `open_evt.wait()` sonrası sayacı başlatır ve `all_tasks`'a eklenir
  * `video_tasks.py` — FFmpeg WHEP tamamen kaldırıldı; `livekit_subscriber.py` subprocess (`/opt/teqlif-agent/venv/bin/python`) + FFmpeg MKV→MP4 pipeline; benzersiz `--identity hl-{room_id}-{hex}` ile DUPLICATE_IDENTITY önlendi; `.log` yetim dosya temizliği eklendi; `capture_hype_highlight` ARQ task
  * `chat.py` — `asyncio.create_task()` → `get_pool().enqueue_job(_queue_name="video", _job_id="highlight:{stream_id}")`
  * `worker.py` — `WorkerSettingsVideo.functions`'a `capture_hype_highlight` eklendi
  * `setup_recorder.sh` — node1 kapsama eklendi; node1'de `livekit==1.1.20 av>=17.0.0 numpy>=2.0` kuruldu
* **Durum:** Tüm node'lara (node1–6 + nodeMonitor) deploy edildi; tüm servisler sağlıklı.

---

### SRE-132 · 🟠 P1 (Yüksek) · Global `fraud_log` Redis ZSET'ine Her Olayda JSON Yazılması ve Her Seferinde `zremrangebyscore` Kilitlenmesi
* **Etkilenen Dosya:** `backend/app/services/fraud_detection_service.py`
* **İlgili Satırlar:** 64–72
* **İlgili Fonksiyon:** `_log_fraud_attempt`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
redis = await get_redis()
score = time.time()
value = json.dumps(payload)
await redis.zadd("fraud_log", {value: score})
cutoff = score - 30 * 24 * 3600
await redis.zremrangebyscore("fraud_log", "-inf", cutoff)
```
1. Platform genelinde şüpheli teklif, çoklu IP, bot aktivitesi gibi tüm dolandırıcılık girişimleri tek bir global Redis ZSET'inde (`"fraud_log"`) toplanır.
2. ZSET elemanları hafif kimlikler değil, onlarca alan içeren devasa JSON metinleridir (`json.dumps(payload)`).
3. Her bir log yazımında (yüksek teklif fırtınalarında saniyede onlarca kez), `zremrangebyscore("fraud_log", "-inf", cutoff)` çalıştırılır.
4. $O(\log(N) + M)$ karmaşıklığına sahip bu işlem, ZSET yüz binlerce elemana ulaştığında tek iş parçacıklı (single-threaded) Redis event loop'unu onlarca milisaniye dondurur (stop-the-world).
5. Ayrıca bu anahtarın hiçbir zaman TTL'i (`EXPIRE`) yoktur. Trafik azalsa bile bellekten temizlenmez; bot saldırısı anında yüz binlerce JSON girdisi ile Redis belleğini şişirir (OOM).

#### 2. Çözüm / Refactoring Reçetesi
1. Dolandırıcılık logları kalıcı analiz verisidir; Redis ZSET'inde tutulmamalı, doğrudan ClickHouse `track_user_event` tablosuna veya yapılandırılmış loglara (ELK/Loki) aktarılmalıdır.
2. Redis'te tutulması gerekiyorsa, her yazmada tüm ZSET'i taramak yerine günlük TTL'e sahip Redis Stream (`XADD` + `MAXLEN ~ 10000`) kullanılmalıdır.

---

### SRE-133 · 🟠 P1 (Yüksek) · `User.fcm_token` Tekil Sütun Tasarımı ile Çoklu Cihaz Desteğinin Olmaması ve Toplu Bildirim Kesintisi
* **Etkilenen Dosyalar:** `backend/app/models/user.py`, `backend/app/services/device_service.py`, `backend/app/services/notification_service.py`
* **İlgili Satırlar:** `user.py:22`, `device_service.py:18-20`, `notification_service.py:141`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
# models/user.py:22
fcm_token: Mapped[str | None] = mapped_column(String(500), nullable=True)

# services/device_service.py:18-20
user = await uow.users.get_by_fcm_token(event.token)
if user:
    user.fcm_token = None
```
1. `User` tablosunda `fcm_token` tek bir `VARCHAR(500)` sütunudur.
2. Bir kullanıcı hem iPhone hem iPad cihazından veya kişisel ve iş telefonundan `teqlif` uygulamasına giriş yaptığında, son giriş yapılan cihaz diğer cihazın token'ının üzerine yazar.
3. Kullanıcı artık birincil cihazından müzayede teklif aşıldı (outbid), canlı yayın başlangıcı veya DM bildirimlerini alamaz.
4. Daha da vahimi: `device_service.py` içinde Firebase `NotRegistered` veya geçersiz token geri bildirimi aldığında, `user.fcm_token = None` yaparak kullanıcının tüm push bildirimlerini tamamen kapatır! Eski bir cihazdaki token eskidi diye kullanıcının yeni aktif cihazı da susturulur.

#### 2. Çözüm / Refactoring Reçetesi
1. Tekil sütun yerine `user_devices` (veya `user_fcm_tokens`) tablosu kurulmalıdır:
```python
class UserDevice(Base):
    __tablename__ = "user_devices"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    fcm_token: Mapped[str] = mapped_column(String(500), unique=True, index=True)
    platform: Mapped[str] = mapped_column(String(20)) # ios, android, web
    last_active_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```
2. Bildirimler `send_each_for_multicast` ile kullanıcının tüm aktif cihazlarına gönderilmeli; geçersiz olan token sadece kendi cihaz kaydını silmelidir.

---

### SRE-134 · 🟠 P1 (Yüksek) · `lk_list_all_rooms` ve `lk_broadcast_delete` İçinde Sıralı (Sequential) Döngü ile Blokaj
* **Etkilenen Dosya:** `backend/app/services/livekit_service.py`
* **İlgili Satırlar:** 36–50, 64–76, 96–110
* **İlgili Fonksiyonlar:** `lk_list_all_rooms`, `lk_list_all_rooms_with_participants`, `lk_broadcast_delete`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
nodes = await orchestrator.all_media_nodes()
_timeout = aiohttp.ClientTimeout(total=4.0)
for node in nodes:
    url = node.get("livekit_url", "")
    ...
    async with aiohttp.ClientSession(timeout=_timeout) as session:
        svc = RoomService(session, url, ...)
        res = await svc.list_rooms(...)
```
1. Fonksiyonlar, kümedeki tüm medya node'larını (`node3`, `node4`, `node7` vb.) tek tek sıralı bir `for node in nodes:` döngüsüyle sorgular.
2. Her node için ayrı bir HTTP oturumu açılır ve 4.0 saniye beklenir.
3. Eğer 1 veya 2 node ağ kesintisi, kernel panic veya yüksek yük nedeniyle yanıt veremezse, döngü 8–16 saniye boyunca kilitlenir.
4. `lk_broadcast_delete` fonksiyonunda ise hiçbir explicit timeout tanımlanmamıştır; gRPC/HTTP varsayılan 30 saniyelik timeout devreye girer. Tek bir yanıt vermeyen sunucu yüzünden oda silme işlemi 60 saniyeden fazla sürer.
5. Bu fonksiyonlar canlı yayın kapanışında ve arka plan görevlerinde çağrıldığı için tüm worker iş parçacıklarını askıya alır.

#### 2. Çözüm / Refactoring Reçetesi
1. Tüm node istekleri `asyncio.gather(*tasks, return_exceptions=True)` ile eşzamanlı (paralel) çalıştırılmalı ve toplam işlem süresine katı bir tavan timeout konmalıdır:
```python
async def _query_node(node):
    url = node.get("livekit_url", "")
    if not url: return set()
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=2.5)) as session:
        svc = RoomService(session, url, settings.livekit_api_key, settings.livekit_api_secret)
        res = await svc.list_rooms(ListRoomsRequest())
        return {r.name for r in res.rooms}

results = await asyncio.gather(*[_query_node(n) for n in nodes], return_exceptions=True)
for r in results:
    if isinstance(r, set):
        all_rooms.update(r)
```

---

### SRE-135 · 🟠 P1 (Yüksek) · `_read_streaming` Bellek Çiftlemesi ve HTTP Handler İçinde Senkron Pillow/FFmpeg Süreç Blokajı
* **Etkilenen Dosyalar:** `backend/app/routers/messages.py`, `backend/app/utils/media_processor.py`
* **İlgili Satırlar:** `messages.py:131-143, 165`, `media_processor.py:103-121, 196-238`
* **İlgili Fonksiyonlar:** `_read_streaming`, `make_thumbnail`, `VideoProcessor.process`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
# messages.py:131-143
async def _read_streaming(file: UploadFile, max_bytes: int) -> bytes:
    chunks: list[bytes] = []
    while True:
        chunk = await file.read(65536)
        ...
        chunks.append(chunk)
    return b"".join(chunks)
```
1. `_read_streaming` fonksiyonu dosyayı belleğe almadığını iddia etmesine rağmen, tüm parçaları bir Python listesine toplar ve `b"".join(chunks)` ile tek bir byte dizisinde birleştirir. 50 MB'lık bir dosya transfer sırasında RAM'de 100–120 MB yer kaplar.
2. Ardından `upload_media_message` endpoint'i `process_media` çağırır:
   - Görsellerde `make_thumbnail` fonksiyonu çağrılır; Pillow kütüphanesi 48 megapiksellik yüksek çözünürlüklü fotoğrafları doğrudan Uvicorn'un ana asenkron döngüsünde (main event loop) senkron olarak açar, küçültür ve sıkıştırır (CPU %100, 1-2 saniye event loop donması).
   - Videolarda `VideoProcessor` geçici dosyaya yazar, ardından sırayla `ffprobe` (30s timeout) ve `ffmpeg` (20s timeout) çalıştırarak thumbnail çıkarır.
3. Eşzamanlı 5 kullanıcı video gönderdiğinde, Node1 üzerinde 5 ayrı FFmpeg süreci başlar, CPU %100'e vurur, Uvicorn diğer HTTP ve WebSocket isteklerine yanıt veremez (504 Gateway Timeout).

#### 2. Çözüm / Refactoring Reçetesi
1. 50 MB'lık dosyalar bellekte biriktirilmemeli; doğrudan `NamedTemporaryFile` içerisine stream edilmelidir (`shutil.copyfileobj`).
2. CPU-yoğun görsel işleme (`make_thumbnail`) `asyncio.to_thread` ile thread pool'a alınmalı; video süre tespiti ve thumbnail çıkarma işlemleri ise HTTP request-response döngüsünden çıkarılıp arka plan worker kuyruğuna delege edilmelidir.

---

### SRE-136 · 🟠 P1 (Yüksek) · `upsert_rating` Eşzamanlı İsteklerinde IntegrityError (HTTP 500) Yarışı ve Erken Session Commit Tutarsızlığı
* **Etkilenen Dosyalar:** `backend/app/use_cases/ratings/commands/upsert_rating.py`, `backend/app/models/rating.py`
* **İlgili Satırlar:** `upsert_rating.py:60-111`, `rating.py:9`
* **İlgili Fonksiyon:** `UpsertRatingCommand.execute`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
# rating.py:9
__table_args__ = (UniqueConstraint("rater_id", "rated_id"),)

# upsert_rating.py:60-111
existing = await self.uow.session.scalar(
    select(Rating).where(Rating.rater_id == rater_id, Rating.rated_id == rated_id)
)
if existing:
    ...
    await self.uow.session.commit()
else:
    self.uow.session.add(Rating(rater_id=rater_id, rated_id=rated_id, score=score, comment=comment))
    await self.uow.session.commit()
```
1. `ratings` tablosunda `(rater_id, rated_id)` üzerinde `UniqueConstraint` tanımlıdır.
2. Bir kullanıcı mobil cihazda butona çift tıkladığında veya ağ gecikmesi nedeniyle çift istek gittiğinde, iki coroutine aynı anda `existing` kontrolü yapar.
3. İkisi de `existing is None` sonucunu alır ve ikisi de `self.uow.session.add(Rating(...))` çalıştırıp commit etmeye çalışır.
4. İlk istek başarıyla yazılırken, ikinci istek `UniqueViolation: Key (rater_id, rated_id)=(...) already exists` hatasıyla patlar ve istemciye HTTP 500 Internal Server Error döner.
5. İkinci kusur: Komut sınıfı `async with self.uow:` context manager kullanmak yerine oturum üzerinde elle `await self.uow.session.commit()` çağırmaktadır. Ardından satır 85'te `self.uow.session.scalar(...)` ile tekrar sorgu atmaktadır; bu durum SQLAlchemy 2.0 oturum durumunu kirletir ve sonraki işlemlerde `InvalidRequestError` üretir.

#### 2. Çözüm / Refactoring Reçetesi
1. Kilitsiz `select` ve `insert` mantığı yerine, PostgreSQL'in yerel `ON CONFLICT (rater_id, rated_id) DO UPDATE` sözdizimi (`postgresql.insert().on_conflict_do_update`) kullanılmalıdır.
2. Oturum commit işlemi komut içinden çıkarılmalı, Unit of Work context sınırlarına devredilmelidir:
```python
from sqlalchemy.dialects.postgresql import insert as pg_insert

stmt = pg_insert(Rating).values(
    rater_id=rater_id, rated_id=rated_id, score=score, comment=comment
).on_conflict_do_update(
    index_elements=["rater_id", "rated_id"],
    set_={"score": score, "comment": comment, "updated_at": func.now()}
)
await self.uow.session.execute(stmt)
```

---

### SRE-137 · 🟡 P2 (Orta) · `accept_follow_request` İçinde Koşulsuz `_redis.decr` Nedeniyle Mesaj İstek Sayacının Negatife Düşmesi
* **Etkilenen Dosya:** `backend/app/routers/follows.py`
* **İlgili Satırlar:** 213–228
* **İlgili Fonksiyon:** `accept_follow_request`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
user_a, user_b = min(follower_id, current_user.id), max(follower_id, current_user.id)
await db.execute(
    sa_update(MessageThread)
    .where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
        MessageThread.status == "pending",
    )
    .values(status="accepted")
)
await db.commit()

from app.utils.redis_client import get_redis
_redis = await get_redis()
await _redis.decr(f"msg:unread:request:{current_user.id}")
```
1. Bir takip isteği kabul edildiğinde kod, aralarındaki bekleyen mesaj isteğini de (`MessageThread.status == 'pending'`) kabul edilmiş duruma getirmeye çalışır.
2. Ancak kullanıcıların %95'i mesaj atmadan sadece profil üzerinden takip isteği gönderir; yani aralarında hiçbir `MessageThread` kaydı yoktur (`rowcount == 0`).
3. Kod, herhangi bir satırın güncellenip güncellenmediğini kontrol etmeksizin **koşulsuz olarak** `await _redis.decr(f"msg:unread:request:{current_user.id}")` çağırır!
4. Kullanıcının okunmamış mesaj isteği sayısı `0` iken, kabul ettiği her takip isteğinde sayaç `-1, -2, -3` şeklinde negatif sayılara düşer. Mobil uygulamadaki mesaj istekleri sekmesinde ve uygulama ikonu rozetinde hatalı badge sayıları gösterilir.

#### 2. Çözüm / Refactoring Reçetesi
1. Sayaç azaltma işlemi, sadece veritabanında gerçekten bir mesaj isteği güncellendiyse (`result.rowcount > 0`) ve sayaç sıfırdan büyükse yapılmalıdır:
```python
res = await db.execute(
    sa_update(MessageThread)
    .where(
        MessageThread.user_a_id == user_a,
        MessageThread.user_b_id == user_b,
        MessageThread.status == "pending",
    )
    .values(status="accepted")
)
await db.commit()

if res.rowcount > 0:
    _redis = await get_redis()
    # Lua script veya atomik taban kontrollü azaltma
    await _redis.eval("""
        local cur = redis.call('get', KEYS[1])
        if cur and tonumber(cur) > 0 then
            return redis.call('decr', KEYS[1])
        else
            redis.call('set', KEYS[1], 0)
            return 0
        end
    """, 1, f"msg:unread:request:{current_user.id}")
```

---

### SRE-138 · 🟡 P2 (Orta) · `mark_read` Endpoint'inde Tüm Nesnelerin Belleğe Çekilip Python Döngüsüyle Tek Tek Güncellenmesi
* **Etkilenen Dosya:** `backend/app/routers/ratings.py`
* **İlgili Satırlar:** 81–93
* **İlgili Fonksiyon:** `mark_read`

#### 1. Sorunun Tanımı ve Arıza Modu
```python
@router.patch("/me/mark-read")
async def mark_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ratings = await db.scalars(
        select(Rating).where(Rating.rated_id == current_user.id, Rating.is_read == False)
    )
    for r in ratings:
        r.is_read = True
    await db.commit()
    return {"ok": True}
```
1. Kullanıcı kendisine gelen değerlendirmeleri "okundu" olarak işaretlemek istediğinde endpoint çağrılır.
2. Popüler bir satıcı veya yayıncı için okunmamış yüzlerce değerlendirme tek bir `SELECT` sorgusuyla ORM nesneleri halinde Python belleğine yüklenir.
3. Python içinde `for r in ratings: r.is_read = True` döngüsü çalıştırılır.
4. `await db.commit()` çağrıldığında SQLAlchemy Unit of Work, takip ettiği tüm nesnelerin durumunu tek tek veritabanına yazar; yani tek bir toplu SQL yerine veritabanına **yüzlerce ayrı UPDATE sorgusu** fırlatılır.
5. Bu durum gereksiz veritabanı I/O'su, connection kilitlenmesi ve bellek tüketimi yaratır. Ayrıca kullanıcının Redis üzerindeki okunmamış sayaç önbelleği (`rating:unread:{user_id}`) temizlenmez (Cache Desync).

#### 2. Çözüm / Refactoring Reçetesi
1. İşlem nesneleri belleğe çekmeden tek bir küme tabanlı SQL `UPDATE` sorgusuyla yapılmalı ve Redis önbelleği sıfırlanmalıdır:
```python
@router.patch("/me/mark-read")
async def mark_read(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await db.execute(
        update(Rating)
        .where(Rating.rated_id == current_user.id, Rating.is_read == False)
        .values(is_read=True)
    )
    await db.commit()
    
    _redis = await get_redis()
    await _redis.set(f"ratings:unread:{current_user.id}", 0)
    return {"ok": True}
```

---

### SRE-139 · 🔴 P0 (Kritik) · Concat Sonucu Kayıtta `available_at` Eksikliği Nedeniyle Bildirim ve Yaşam Döngüsü Felci
* **Etkilenen Dosya:** `backend/app/tasks/stream_concat_task.py`
* **İlgili Satırlar:** 153–158
* **Zamanlama:** `worker.py:cron(stream_concat_task, minute=set(range(0, 60, 2)))` ve `stream_recording_tasks.py:notify_new_recordings_task`

#### 1. Sorunun Tanımı ve Arıza Modu
Canlı yayın parçaları (`part_1.mp4`, `part_2.mp4` vb.) FFmpeg ile başarıyla birleştirildiğinde, sonuç kaydı `stream_recordings` tablosuna şu SQL ile eklenir:
```python
await session.execute(text("""
    INSERT INTO stream_recordings
        (stream_id, host_id, minio_key, status, is_concat_result, created_at, updated_at)
    VALUES
        (:stream_id, :host_id, :minio_key, 'available', TRUE, NOW(), NOW())
"""), {"stream_id": stream_id, "host_id": host_id, "minio_key": concat_key})
```
1. **`available_at` Kolonunun NULL Kalması:** Sorgu içerisinde `available_at` kolonu yazılmadığı için veritabanında `NULL` olarak kalır.
2. **Bildirim Zincirinin Tamamen Kopması:** `stream_recording_tasks.py:50-58` içindeki `notify_new_recordings_task`:
```sql
SELECT sr.id, sr.stream_id, ls.host_id, u.user_type
FROM stream_recordings sr
JOIN live_streams ls ON ls.id = sr.stream_id
JOIN users u         ON u.id  = ls.host_id
WHERE sr.status = 'available'
  AND sr.host_notified_at IS NULL
  AND sr.available_at > NOW() - INTERVAL '6 hours'
```
filtresini koşturur. `sr.available_at` `NULL` olduğu için SQL üç değerli mantığında (Three-Valued Logic) `NULL > NOW() - INTERVAL '6 hours'` ifadesi `NULL` (yani `FALSE`) döner! Sonuç olarak:
   - Yayıncıya (host) "Yayınınız hazır, izleyebilirsiniz" push bildirimi **asla gitmez**.
3. **`expires_at` Belirlenemez ve Süreç Kilitlenir:** Kaydın son kullanma süresi (`expires_at`), yalnızca `notify_new_recordings_task` başarılı olduğunda set edilmektedir (`NOW() + 24 hours` veya `NOW() + 14 days`). Bildirim görevi kaydı atladığı için kaydın `expires_at` alanı sonsuza kadar `NULL` kalır!
4. **Kayıt Asla Expire ve Archive Edilemez:** `expire_recordings_task` (`WHERE status = 'available' AND expires_at < NOW()`) kaydı asla yakalayamaz; `archive_recordings_task` de kaydı arşivleyemez.
5. **Yedekleme ve Özet Hatası:** `get_recording_summary.py` API'si `expires_at` alanını `None` döner ve mobil istemcide UI kilitlenmeleri oluşur.

#### 2. Çözüm / Refactoring Reçetesi
1. `backend/app/tasks/stream_concat_task.py:153-158` içine `available_at` kolonunu ekle:
```python
await session.execute(text("""
    INSERT INTO stream_recordings
        (stream_id, host_id, minio_key, status, is_concat_result, available_at, created_at, updated_at)
    VALUES
        (:stream_id, :host_id, :minio_key, 'available', TRUE, NOW(), NOW(), NOW())
"""), {"stream_id": stream_id, "host_id": host_id, "minio_key": concat_key})
```
2. `stream_recording_tasks.py:57` satırında güvenli fallback uygula:
```sql
AND COALESCE(sr.available_at, sr.created_at) > NOW() - INTERVAL '6 hours'
```

#### ✅ Çözüm Damgası
* **Commit:** `e8315cad` · 2026-10-30
* **Değişiklik:**
  * `stream_concat_task.py:362` — INSERT kolon listesine `available_at`, VALUES listesine `NOW()` eklendi
  * `stream_recording_tasks.py:57` — `COALESCE(sr.available_at, sr.created_at)` savunmacı fallback eklendi (mevcut NULL kayıtlar ve gelecek regresyonlar için)
* **Durum:** Tüm node'lara (node1–6 + nodeMonitor) deploy edildi; node1 servisleri sağlıklı.

#### ✅ Followup Çözüm Damgası (SRE-139 — transferred_at + recording_started_at)
* **Commit:** `96268dda` · 2026-10-30
* **Değişiklik:**
  * `stream_concat_task.py` — Parts SELECT'e `recording_started_at, duration_secs` eklendi; `with tmpdir:` kapanmadan önce `_ffprobe_streams(out_path)` ile `concat_duration_secs` ve `os.path.getsize(out_path)` ile `concat_size_bytes` yakalandı; INSERT'e `transferred_at = NOW()`, `recording_started_at = :rec_started_at`, `duration_secs`, `encoded_size_bytes` eklendi — concat kayıtlarında `transferred_at` NULL kalması engellendi (node2 onayı + arşivleme kilidi)
  * `stream_recording_tasks.py:134,142` — `archive_recordings_task` her iki sorgusunda `AND transferred_at` → `AND COALESCE(transferred_at, available_at, created_at)` (SQL 3VL fallback)
  * `deploy/scale/V2.1/node2/resources/scripts/minio_backup.sh:75` — `AND transferred_at IS NOT NULL` → `AND COALESCE(transferred_at, available_at) IS NOT NULL`

---

### SRE-140 · 🔴 P0 (Kritik) · `_get_t` İçinde Senkron `create_engine` ile Havuz Sızıntısı ve 3s Uvicorn Event Loop Donması
* **Etkilenen Dosya:** `backend/app/utils/i18n.py`
* **İlgili Satırlar:** 37–78
* **İlgili Fonksiyon:** `_get_t(lang)`

#### 1. Sorunun Tanımı ve Arıza Modu
`_get_t(lang)` fonksiyonu `_msg()`, `email.py`, `notification_service.py`, `auth.py`, `calls.py` gibi neredeyse tüm kritik backend rotalarında doğrudan çağrılmaktadır:
```python
def _get_t(lang: str) -> dict:
    now = time.time()
    if lang in _MEMORY_CACHE and (now - _CACHE_TIME.get(lang, 0.0)) < _CACHE_TTL:
        return _MEMORY_CACHE[lang]
    ...
    # 2. Redis'te yoksa Veritabanından (translations tablosu) senkron okumayı dene
    try:
        from sqlalchemy import create_engine, text
        from app.config import settings
        sync_db_url = settings.database_url.replace("+asyncpg", "").replace("+aiosqlite", "")
        engine = create_engine(sync_db_url, pool_pre_ping=True, connect_args={"connect_timeout": 3})
        with engine.connect() as conn:
            res = conn.execute(text("SELECT key, value FROM translations WHERE lang = :lang"), {"lang": lang})
    ...
```
1. **Asenkron Event Loop İçinde Senkron Blokaj (Event Loop Starvation):** `_get_t` senkron bir fonksiyondur ve doğrudan asenkron FastAPI endpoint'lerinin içinde koşturulur. 5 dakikalık TTL dolduğunda veya Redis soğukken `create_engine(...)` + `engine.connect()` çağrısı Uvicorn'un tek iş parçacıklı asyncio döngüsünü 3 saniyeye kadar kilitler (`connect_timeout: 3`). O 3 saniye boyunca o Uvicorn worker'ına bağlı tüm WebSocket ping-pong'ları, teklif (bid) istekleri ve API çağrıları tamamen donar.
2. **Kritik Bağlantı Havuzu Sızıntısı (Connection Pool & FD Leak):** Kod `engine = create_engine(...)` ile her çağrıda yeni bir SQLAlchemy `Engine` ve havuz örneği oluşturur ancak blok sonunda **asla `engine.dispose()` çağırmaz!** Her cache miss döngüsünde 5 bağlantılık yeni bir pool arka planda soket ve worker thread sızdırır. İşletim sistemi zamanla `Too many open files` (EMFILE) hatası verir.
3. **Mükerrer Redis İstemcisi Tahsisi:** Satır 40 ve 70'te `sync_redis.Redis.from_url` ile her çağrıda sıfırdan TCP soketi açılıp kapatılır.

#### 2. Çözüm / Refactoring Reçetesi
1. `_get_t` fonksiyonunun içine ASLA dinamik `create_engine` konulmamalıdır. Bellek önbelleği (`_MEMORY_CACHE`) uygulama başlarken `preload_i18n_cache()` tarafından doldurulmalı ve bir arka plan ARQ görevi veya Redis Pub/Sub ile güncellenmelidir.
2. Zorunlu fallback durumunda DB okuması asenkron havuz üzerinden yapılmalı veya statik global bir sync engine ile `asyncio.to_thread` üzerinden izole edilmelidir:
```python
# app/utils/i18n.py
_STATIC_SYNC_ENGINE = None

def _get_static_sync_engine():
    global _STATIC_SYNC_ENGINE
    if _STATIC_SYNC_ENGINE is None:
        from sqlalchemy import create_engine
        from app.config import settings
        sync_db_url = settings.database_url.replace("+asyncpg", "").replace("+aiosqlite", "")
        _STATIC_SYNC_ENGINE = create_engine(
            sync_db_url, pool_size=2, max_overflow=3, pool_pre_ping=True, pool_recycle=300
        )
    return _STATIC_SYNC_ENGINE
```
Ve `_get_t` içinde fallback sadece bellekten `tr` sözlüğüne dönmeli, event loop içinde asla senkron veritabanı TCP el sıkışması yapılmamalıdır.

#### ✅ Çözüm Damgası
* **Commit:** `2fc044d6` · 2026-10-30
* **Değişiklik:**
  * `i18n.py` — `_get_t` içindeki `create_engine(...)` + `engine.connect()` + `sync_redis.Redis.from_url(...)` tamamen kaldırıldı; fonksiyon artık I/O yapmıyor; stale-while-revalidate: TTL dolduğunda stale veri döner (3s event loop blokajı ve FD/pool sızıntısı giderildi). `_get_static_sync_engine()` singleton eklendi (event loop dışı bağlamlar için). Duplicate `_SUPPORTED` ve unused `Any` import temizlendi.
  * `main.py` — `_i18n_refresh_loop()` arka plan görevi eklendi (her 4 dk, lifespan'da düzgün cancel+gather ile kapatılıyor); FastAPI worker süreci belleği restart gerektirmeden canlı tutulacak.
  * `worker.py` — `refresh_i18n_cache_task` eklendi; `WorkerSettings.functions` ve `cron_jobs`'a her 4 dakikada bir girdi olarak eklendi.
* **Durum:** Tüm node'lara deploy edildi; servisler sağlıklı.

---

### SRE-141 · 🔴 P0 (Kritik) · Doğrulanmamış Telefonun Erken DB Commit'i ile Numara Rehin Alma (Phone DoS) ve Statü Kaybı
* **Etkilenen Dosya:** `backend/app/routers/auth.py`
* **İlgili Satırlar:** 1267–1284
* **İlgili Fonksiyon:** `request_phone_verification`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı telefon doğrulaması istediğinde kod şu şekilde çalışır:
```python
# Başka bir kullanıcıda kayıtlıysa reddet
existing = await db.scalar(
    select(User).where(User.phone == data.phone, User.id != current_user.id)
)
if existing:
    raise BadRequestException(...)

# Telefonu kaydet (henüz doğrulanmamış)
current_user.phone = data.phone
current_user.phone_verified = False
await db.commit()
await invalidate_user_session_cache(current_user.id)

# Token üret ve Redis'e kaydet
...
```
1. **Telefon Numarası Rehin Alma Saldırısı (Phone DoS Exploit):**
   - Kötü niyetli bir saldırgan yeni bir sahte hesap açar ve hedef bir mağaza/yayıncının gerçek telefon numarasını (`+90555xxxxxxx`) girerek `POST /api/auth/phone/verify-request` çağrısı yapar.
   - Kod, e-posta veya SMS onayı gelmeden **doğrudan bu numarayı saldırganın `User.phone` kolonuna commit eder**.
   - Gerçek telefon sahibi platforma gelip kendi numarasını doğrulamak istediğinde: `existing = await db.scalar(select(User).where(User.phone == data.phone, ...))` kontrolüne takılır ve `apiErrPhoneUsed` ("Bu telefon numarası başka bir hesapta kayıtlı") hatası alır. Gerçek sahip numarasını platforma asla ekleyemez!
2. **Kendi Kendini Sabote Etme / Doğrulanmış Statü Kaybı (Downgrade):**
   - Halihazırda onaylı bir telefon numarasına sahip olan (`phone_verified = True`) güvenilir bir satıcı numara değiştirmek istediğinde yanlış bir hane yazarsa veya e-posta gönderimi başarısız olursa, kullanıcının mevcut doğrulanmış statüsü derhal `phone_verified = False` yapılarak silinir.
   - Kullanıcı yeni numarayı onaylayana kadar tüm teklif verme (`bid_validation_service`) ve canlı yayın açma haklarından mahrum kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. Doğrulanmamış yeni telefon numarası **asla** `users` tablosuna yazılmamalıdır. Yeni telefon numarası yalnızca Redis'teki doğrulama token'ı içinde saklanmalıdır:
```python
# auth.py: request_phone_verification
# current_user.phone ve current_user.phone_verified DEĞİŞTİRİLMEZ!

token = secrets.token_urlsafe(32)
await redis.setex(f"phone_verify_req:{current_user.id}", VERIFY_CODE_TTL, "1")
await redis.setex(
    f"phone_verify:{token}",
    _PHONE_VERIFY_TOKEN_TTL,
    json.dumps({"user_id": current_user.id, "new_phone": data.phone}),
)
```
2. Yalnızca `confirm_phone_verification` endpoint'inde token onaylandığında:
```python
# auth.py: confirm_phone_verification
user.phone = data["new_phone"]
user.phone_verified = True
await db.commit()
await invalidate_user_session_cache(user.id)
```

#### ✅ Çözüm Damgası
* **Commit:** `9e1c3cb3` · 2026-10-30
* **Değişiklik:**
  * `auth.py: request_phone_verification` — `current_user.phone = data.phone` + `phone_verified = False` + `db.commit()` DB write satırları kaldırıldı; telefon artık yalnızca onay sonrası DB'ye yazılıyor. Duplicate check `User.phone_verified == True` filtresine daraltıldı — doğrulanmamış claim'ler gerçek sahibin talebini engelleyemiyor.
  * `auth.py: confirm_phone_verification (action=yes)` — race condition koruması eklendi (`verified_by_other` kontrolü); `sa_update` ile doğrulanmamış sahipsiz talepler temizlendi (unique constraint koruması); `user.phone = phone` + `phone_verified = True` yalnızca e-posta onayı sonrası yazılıyor.
  * `auth.py: confirm_phone_verification (action=no)` — DB write kaldırıldı (telefon hiç yazılmamıştı); sadece token siliniyor.
* **Durum:** Tüm node'lara deploy edildi; servisler sağlıklı.

---

### SRE-142 · 🟠 P1 (Yüksek) · İlan Videosu Yüklemede Senkron FFmpeg/FFprobe ile 504 Timeout ve CPU %100 Açlığı
* **Etkilenen Dosya:** `backend/app/routers/upload.py`
* **İlgili Satırlar:** 92–129, 31–44, 46–89
* **İlgili Fonksiyon:** `upload_listing_video`, `_read_streaming`, `_process_listing_video`

#### 1. Sorunun Tanımı ve Arıza Modu
İlan videosu yükleme endpoint'inde:
```python
@router.post("/listing-video")
async def upload_listing_video(...):
    data = await _read_streaming(file, LISTING_VIDEO_MAX_BYTES)
    ...
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = os.path.join(tmp_dir, f"src_{uuid.uuid4().hex}.mp4")
        with open(tmp_path, "wb") as f:
            f.write(data)

        duration = await _get_video_duration(tmp_path)
        video_local, thumb_local = await _process_listing_video(tmp_path, tmp_dir)
        video_url = await storage.upload_file_async(video_key, video_local, "video/mp4")
        ...
```
1. **HTTP Handler İçinde 60 Saniyelik FFmpeg İşlemi:** 60 MB'lık bir videonun diske yazılması, FFprobe ile süresinin okunması, FFmpeg ile remuxing + AAC ses encode edilmesi (`-movflags +faststart`) ve ardından thumbnail çıkarılması 30–60 saniye sürmektedir.
2. **Nginx 504 Gateway Timeout ve Ağ Kopması:** Mobil istemcinin HTTP bağlantısı 60 saniye boyunca askıda tutulur. Mobil ağ dalgalanmasında veya Nginx ingress `proxy_read_timeout` (varsayılan 60s) dolduğunda istemci 504 hatası alır.
3. **Node1'de CPU Starvation:** Node1 aynı zamanda PostgreSQL ve ana FastAPI worker'larına ev sahipliği yapar. 5 satıcının aynı anda video yüklemesi durumunda 5 eşzamanlı FFmpeg süreci CPU'nun tüm çekirdeklerini %100 doygunluğa ulaştırarak veritabanı sorgularının ve canlı tekliflerin donmasına sebep olur.
4. **Yetim Medya Nesneleri:** İstemci 504 alıp koptuğunda MinIO'ya yüklenmiş olan video nesnesi hiçbir ilanla ilişkilendirilemez ve depolamada çöp olarak kalır.

#### 2. Çözüm / Refactoring Reçetesi
1. Video yükleme işlemi HTTP thread'inden ayrılmalıdır:
   - İstemci videoyu doğrudan MinIO presigned URL ile yüklemeli veya backend videoyu doğrudan diske alıp anında `{"status": "processing", "upload_id": "..."}` dönmelidir.
2. Transcoding ve thumbnail üretimi ARQ worker kuyruğuna (`process_listing_video_task`) devredilmelidir:
```python
# upload.py
upload_id = uuid.uuid4().hex
await task_queue.enqueue("process_listing_video_task", user_id=current_user.id, upload_id=upload_id, file_path=tmp_path)
return {"upload_id": upload_id, "status": "processing"}
```

#### ✅ Çözüm Damgası
* **Commit:** `d9dd903f`
* **Tarih:** 2026-10-30
* **Değişen Dosyalar:** `backend/app/routers/upload.py`, `backend/app/tasks/video_tasks.py`, `backend/app/worker.py`
* **Özet:** `upload_listing_video` içindeki `_process_listing_video` (FFmpeg remux+AAC+thumbnail, 60s) ve `_get_video_duration` (ffprobe) HTTP handler'dan tamamen çıkarıldı. Ham video doğrudan `listings/video/{uuid}.mp4` key'iyle MinIO'ya `upload_bytes_async` ile yükleniyor, ardından `process_listing_video_task` ARQ video kuyruğuna (`_queue_name="video"`) enqueue ediliyor ve `{video_url, thumb_url: null}` hemen dönüyor. `process_listing_video_task` MinIO'dan indirip `nice -n 10 ffmpeg -c:v copy -c:a aac -movflags +faststart -t 60` ile işleyip aynı key'e yeniden yüklüyor; thumbnail üretiyor ve `listings.thumbnail_url` best-effort güncelleniyor. `WorkerSettingsVideo.functions` listesine eklendi (max_jobs=2 CPU starvation koruması mevcut).

---

### SRE-143 · 🟠 P1 (Yüksek) · Admin Dashboard'da 16 Sıralı Aggregate SQL ve 7 Günlük Döngü ile Postgres CPU Doygunluğu
* **Etkilenen Dosya:** `backend/app/routers/admin_data.py`
* **İlgili Satırlar:** 54–99
* **İlgili Fonksiyon:** `get_dashboard`

#### 1. Sorunun Tanımı ve Arıza Modu
Yönetici paneli ana sayfası yüklendiğinde `/api/admin/dashboard` endpoint'i çalışır:
```python
total_users = (await db.execute(select(func.count(User.id)))).scalar() or 0
active_users = (await db.execute(select(func.count(User.id)).where(User.status == UserStatus.ACTIVE))).scalar() or 0
banned_users = (await db.execute(select(func.count(User.id)).where(User.status == UserStatus.PASSIVE))).scalar() or 0
today_users = (await db.execute(select(func.count(User.id)).where(User.created_at >= today, User.created_at < tomorrow))).scalar() or 0
active_listings = (await db.execute(select(func.count(Listing.id)).where(...))).scalar() or 0
active_streams = (await db.execute(select(func.count(LiveStream.id)).where(...))).scalar() or 0
pending_reports = (await db.execute(select(func.count(Report.id)))).scalar() or 0
total_teqlik = (await db.execute(select(func.coalesce(func.sum(User.teqlik_balance), 0)))).scalar() or 0
today_teqlik_spent = (await db.execute(select(func.coalesce(func.sum(TeqlikTransaction.amount), 0)).where(...))).scalar() or 0

# Son 7 gün günlük kayıt döngüsü
growth = []
for i in range(6, -1, -1):
    day = today - timedelta(days=i)
    day_end = day + timedelta(days=1)
    count = (await db.execute(select(func.count(User.id)).where(User.created_at >= day, User.created_at < day_end))).scalar() or 0
    growth.append({"date": str(day), "count": count})
```
1. **16 Ayrı Sıralı (Sequential) Network I/O ve DB Lock:** Tek bir HTTP isteğinde veritabanına art arda 16 ayrı SQL sorgusu gönderilir.
2. **Milyonluk Tabloda Full-Table Scan Toplamı:** `select(func.sum(User.teqlik_balance))` sorgusu tüm `users` tablosunu sequential scan ile tarar.
3. **7 İterasyonlu For Döngüsü:** Son 7 günün grafiği için tek bir `GROUP BY date_trunc('day', created_at)` yazmak yerine döngü içinde 7 ayrı `COUNT` sorgusu çalıştırılır.
4. **Sıfır Önbellekleme:** Dashboard otomatik yenilenen sekmelerde açık kaldığında PostgreSQL CPU'su %100'e vurur ve PgBouncer bağlantı havuzu tükenir.

#### 2. Çözüm / Refactoring Reçetesi
1. Dashboard verileri 60 saniye TTL ile Redis'te önbelleklenmelidir:
```python
redis = await get_redis()
cached = await redis.get("admin:dashboard:metrics")
if cached:
    return json.loads(cached)
```
2. 7 günlük büyüme tek sorguda birleştirilmelidir:
```sql
SELECT date_trunc('day', created_at)::date AS d, count(id)
FROM users
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY 1 ORDER BY 1;
```

#### ✅ Çözüm Damgası
- **Commit:** `0387d0cf` — `fix(sre-143,sre-144): admin dashboard 16 sıralı sorgu paralele alındı, analytics zaman sınırlandırıldı`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/admin_data.py`
- **Yapılan:**
  - `get_dashboard` `db: AsyncSession` bağımlılığı kaldırıldı; 6 ayrı `_user_stats / _listing_count / _stream_count / _report_count / _teqlik_spent / _growth` coroutine'i `asyncio.gather` ile paralel çalıştırılıyor
  - 7-gün döngüsü yerine tek `GROUP BY created_at::date` sorgusu; sıfır kayıtlı günler Python'da dolduruldu
  - Sonuç 60 s Redis TTL ile `admin:dashboard:metrics` anahtarına yazıldı

---

### SRE-144 · 🟠 P1 (Yüksek) · Analytics Summary Endpoint'inde ClickHouse Yerine PostgreSQL'de `COUNT(DISTINCT)` Kirlenmesi
* **Etkilenen Dosya:** `backend/app/routers/admin_data.py`
* **İlgili Satırlar:** 681–716
* **İlgili Fonksiyon:** `get_admin_analytics_summary`

#### 1. Sorunun Tanımı ve Arıza Modu
Yönetici paneli analitik özet sekmesinde:
```python
total_events_res = await db.execute(select(func.count(AnalyticsEvent.id)))
unique_sessions_res = await db.execute(select(func.count(func.distinct(AnalyticsEvent.session_id))))
device_groups_res = await db.execute(
    select(AnalyticsEvent.device_type, func.count(AnalyticsEvent.id))
    .group_by(AnalyticsEvent.device_type)
)
recent_res = await db.execute(select(AnalyticsEvent).order_by(desc(AnalyticsEvent.created_at)).limit(500))
```
1. **ClickHouse Varken PostgreSQL'e Ağır OLAP Yükü:** Platformda yüksek hacimli analitikler için Node5 üzerinde ClickHouse kuruludur. Ancak bu endpoint doğrudan PostgreSQL'deki `analytics_events` tablosunu sorgulamaktadır.
2. **İndekssiz `COUNT(DISTINCT session_id)` Felaketi:** Milyonlarca satırlık `analytics_events` tablosunda `distinct(session_id)` hesaplamak için PostgreSQL tüm oturum UUID'lerini RAM'de sıralar/hash'ler. Bellek yetersizliğinde disk temp dosyalarına taşar (Spill to disk).
3. **PostgreSQL Buffer Cache Kirlenmesi (Cache Eviction):** Bu devasa full table scan, PostgreSQL'in paylaşılan tampon belleğini (`shared_buffers`) tamamen doldurur; aktif kullanıcı oturumları ve sıcak ilan kayıtları RAM'den diske atılır. Sistem genelinde disk I/O patlaması yaşanır.

#### 2. Çözüm / Refactoring Reçetesi
1. Analitik sorguları doğrudan ClickHouse OLAP veritabanına yönlendirilmelidir:
```sql
-- ClickHouse üzerinde milisaniyeler içinde çalışır:
SELECT 
    count() AS total_events,
    uniqExact(session_id) AS unique_sessions,
    device_type,
    count() AS device_count
FROM user_events
GROUP BY device_type;
```
2. Rapor sonuçları 5 dakikalık Redis önbelleği ile korunmalıdır (`analytics:admin:summary`).

#### ✅ Çözüm Damgası
- **Commit:** `0387d0cf` — `fix(sre-143,sre-144): admin dashboard 16 sıralı sorgu paralele alındı, analytics zaman sınırlandırıldı`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/admin_data.py`
- **Mimari Not:** ClickHouse `user_events` tablosunda `session_id`, `device_type`, `url` kolonları bulunmuyor (yalnızca öneri sinyali: `user_id, item_id, event_type, …`). Şema migrasyonu yapmadan ClickHouse'a taşımak mümkün değildi; PostgreSQL'de zaman sınırı + Redis önbelleği ile hedef P95 süre sağlandı.
- **Yapılan:**
  - `total_events` + `unique_sessions` tek `SELECT … count(DISTINCT session_id) … WHERE created_at >= :cutoff` sorgusuna birleştirildi
  - `device_type GROUP BY` ve ana sayım sorgusuna 30 günlük `cutoff` eklendi; `ix_analytics_events_type_created` indeksini kullanıyor
  - ORM `LIMIT 500 → 100` düşürüldü
  - Sonuçlar 5 dk Redis TTL ile `analytics:admin:summary` anahtarına yazıldı
  - `from app.models.analytics import AnalyticsEvent` dosya gövdesinden modül üstüne taşındı

---

### SRE-145 · 🟡 P2 (Orta) · `/audience-size` Endpoint'inde 10.000 ID'lik `ANY(:ids)` Parametresi ve Önbelleksiz Cross-DB Yükü
* **Etkilenen Dosya:** `backend/app/routers/leads.py`
* **İlgili Satırlar:** 89–96
* **İlgili Fonksiyon:** `get_audience_size`

#### 1. Sorunun Tanımı ve Arıza Modu
Satıcı toplu mesaj gönderme modalini açtığında veya filtre değiştirdiğinde:
```python
target_user_ids = target_user_ids[:10000]

# PostgreSQL'den gerçek FCM token sayısı — takipçiler hariç
if target_user_ids:
    token_count = await db.scalar(sql_text("""
        SELECT COUNT(*) FROM users
        WHERE id = ANY(:ids)
          AND fcm_token IS NOT NULL AND fcm_token != ''
          AND id NOT IN (
              SELECT follower_id FROM follows WHERE followed_id = :me
          )
    """), {"ids": target_user_ids, "me": current_user.id})
```
1. **10.000 Elemanlı Array Serialization:** ClickHouse'dan çekilen 10.000 adet kullanıcı ID'si Python listesi olarak PostgreSQL'e `:ids` parametresiyle iletilir. asyncpg 10.000 elemanlı diziyi network üzerinden binary/text olarak paketler.
2. **Pahalı Subquery ve Anti-Join:** `NOT IN (SELECT follower_id FROM follows WHERE followed_id = :me)` alt sorgusu, `id = ANY(:ids)` filtresiyle birleştiğinde PostgreSQL optimizörü tarafından pahalı bir Anti-Join planına zorlanır.
3. **Önbelleksiz İnteraktif UI Yükü:** Satıcı filtre kutusunu her tıkladığında veya ilan ekleyip çıkardığında bu cross-database sorgu zinciri sıfırdan koşturulur.

#### 2. Çözüm / Refactoring Reçetesi
1. Hesaplanan kitle büyüklüğü satıcı ID'si ve ilan listesinin hash'ine göre 120 saniye Redis'te önbelleklenmelidir:
```python
cache_key = f"leads:audience:{current_user.id}:{hashlib.md5(ids_str.encode()).hexdigest()}"
cached_size = await redis.get(cache_key)
if cached_size is not None:
    return int(cached_size)
```
2. SQL sorgusu `NOT IN` yerine `NOT EXISTS` veya `LEFT JOIN ... WHERE f.follower_id IS NULL` yapısına dönüştürülmelidir.

---

### SRE-146 · 🟡 P2 (Orta) · Cüzdan Bakiyesinin 15 Dakikalık Redis Session Cache'inden, İşlemlerin DB'den Çekilmesi Tutarsızlığı
* **Etkilenen Dosya:** `backend/app/routers/wallet.py` & `backend/app/utils/auth.py`
* **İlgili Satırlar:** `wallet.py:197–215`, `auth.py:96–152`
* **İlgili Fonksiyon:** `get_balance`

#### 1. Sorunun Tanımı ve Arıza Modu
Kullanıcı cüzdanını açtığında:
```python
@router.get("/balance")
async def get_balance(
    limit: int = 5,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    ...
    result = await db.execute(
        select(TeqlikTransaction)
        .where(TeqlikTransaction.user_id == current_user.id)
        .order_by(desc(TeqlikTransaction.created_at))
        .limit(limit)
    )
    txns = result.scalars().all()
    return {
        "balance": current_user.teqlik_balance,
        "transactions": [_txn_dict(t) for t in txns],
    }
```
1. **İki Farklı Veri Kaynağı Arasında Desenkronizasyon:**
   - `transactions` listesi doğrudan PostgreSQL veritabanından anlık taze olarak çekilir.
   - Ancak `balance` alanı `current_user.teqlik_balance` üzerinden, yani `auth.py` içindeki 15 dakika (`_USER_SESSION_TTL = 900`) TTL'e sahip `session:user:{id}` Redis oturum önbelleğinden okunur!
2. **Kullanıcı Deneyiminde Bakiye Kaybı İllüzyonu:**
   - Bir kullanıcıya harici bir transfer (`transfer_teqlik`), airdrop veya mağaza iadesi yapıldığında, alıcının oturum önbelleği her senaryoda temizlenmez.
   - Kullanıcı cüzdanını açar; işlemler dökümünde en üstte az önce gerçekleşen "+500 Teqlik" işlemini görür, fakat ekranın tepesindeki ana bakiye 15 dakika boyunca eski miktarını (örneğin 0 Teqlik) göstermeye devam eder!
   - Kullanıcı transferin kaybolduğunu veya hesabının kilitlendiğini düşünerek panik içinde mükerrer destek talepleri açar.

#### 2. Çözüm / Refactoring Reçetesi
1. Cüzdan bakiyesini dönerken statik session nesnesine güvenilmemeli, doğrudan taze DB bakiye sorgusu atılmalıdır:
```python
fresh_balance = await db.scalar(
    select(User.teqlik_balance).where(User.id == current_user.id)
)
return {
    "balance": fresh_balance if fresh_balance is not None else 0,
    "transactions": [_txn_dict(t) for t in txns],
}
```
2. Kullanıcının bakiyesini değiştiren tüm transfer ve cüzdan komutları alıcının `invalidate_user_session_cache(receiver_id)` metodunu koşulsuz çağırmalıdır.

---

### SRE-147 · 🔴 P0 (Kritik) · Refresh Token Kaydında token_version Denetimi Olmaması Nedeniyle Şifre Sıfırlama Sonrası Oturumun Düşmemesi (Session Hijack Persistence Exploit)

- **Dosya / Modül:** [`backend/app/routers/auth.py:990-1019`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L990-L1019) ve [`backend/app/routers/auth.py:183-186`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L183-L186)
- **Kategori:** Kimlik Doğrulama & Güvenlik / Yetki Yükseltme / Session Hijacking (OWASP A07)
- **Hedef:** `refresh_token`, `login`, `register`, `reset_password` akışları

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/auth.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L183-L186) içinde kullanıcı oturum açtığında:
```python
    refresh = create_refresh_token()
    await redis.setex(f"refresh:{refresh}", REFRESH_TOKEN_TTL, str(user.id))
```
Ve [`backend/app/routers/auth.py:1005-1016`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L1005-L1016) yenileme fonksiyonunda:
```python
    user_id_str = await redis.getdel(f"refresh:{token}")
    ...
    result = await db.execute(select(User).where(User.id == int(user_id_str)))
    user = result.scalar_one_or_none()
    ...
    new_access = create_access_token(user.id, user.token_version)
    new_refresh = create_refresh_token()
    await redis.setex(f"refresh:{new_refresh}", REFRESH_TOKEN_TTL, str(user.id))
```
1. **Şifre Değiştirilse Bile Saldırganın Oturumunun Asla Düşmemesi:**
   - Bir kullanıcının hesabı ele geçirildiğinde veya şifresi sıfırlandığında (`reset-password`), veritabanında `User.token_version` 1 artırılır (`User.token_version + 1`).
   - Bu artış, mevcut JWT access token'ları geçersiz kılar çünkü `decode_token_version` fonksiyonu token'daki versiyonu DB ile karşılaştırır.
   - Ancak Redis'teki `refresh:{token}` anahtarında **yalnızca** `str(user.id)` saklanmaktadır; token'ın hangi `token_version` için üretildiği bilgisi tutulmaz!
   - Saldırgan elindeki çalınmış `refresh_token` ile `POST /api/auth/refresh` çağırdığında, sunucu veritabanındaki **yeni** `user.token_version` değerini okur ve saldırgana yeni versiyonla imzalanmış yepyeni geçerli bir `access_token` ve `refresh_token` teslim eder!
   - Kurban şifresini 10 kez de değiştirse, saldırgan her refresh çağrısında yeni yetki alarak hesapta kalmaya sonsuza dek devam eder (Permanent Session Hijacking).

#### 2. Çözüm / Refactoring Reçetesi
1. Refresh token Redis'e kaydedilirken hem `user_id` hem de üretildiği andaki `token_version` birlikte atomik olarak saklanmalıdır:
```python
# auth.py içinde refresh token oluştururken:
await redis.setex(f"refresh:{refresh}", REFRESH_TOKEN_TTL, f"{user.id}:{user.token_version}")
```
2. `refresh_token` endpoint'inde Redis'ten okunan versiyon ile kullanıcının güncel veritabanı `token_version` değeri karşılaştırılmalı; uyuşmazlık varsa oturum derhal sonlandırılmalıdır:
```python
raw_data = await redis.getdel(f"refresh:{token}")
if not raw_data:
    raise UnauthorizedException(...)
user_id_str, token_ver_str = raw_data.split(":", 1)
...
if user.token_version != int(token_ver_str):
    logger.warning("[AUTH] Token version mismatch on refresh | user=%s (token=%s db=%s)", user.id, token_ver_str, user.token_version)
    raise UnauthorizedException(code="TOKEN_REVOKED")
```
3. Ayrıca `User` başına aktif refresh token ID'lerini tutan bir Redis Set (`user:refresh_tokens:{user_id}`) tanımlanarak, şifre değişiminde veya hesap kapatmada tüm refresh token'lar topluca silinmelidir.

> ✅ **Çözüldü** — commit `27acfe56`, 2026-10-30

---

### SRE-148 · 🟠 P1 (Yüksek) · notify_new_recordings_task İçindeki 6 Saatlik Sınır Nedeniyle Geciken Kayıtların Askıda Kalması ve MinIO Sızıntısı

- **Dosya / Modül:** [`backend/app/tasks/stream_recording_tasks.py:51-58`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L51-L58) ve [`backend/app/tasks/stream_recording_tasks.py:95-103`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L95-L103)
- **Kategori:** SRE & Depolama / Yaşam Döngüsü Felci / Kaynak Sızıntısı (Resource Leak)
- **Hedef:** `notify_new_recordings_task` ve `expire_recordings_task` görevleri

#### 1. Zaaf ve Arıza Modeli

[`backend/app/tasks/stream_recording_tasks.py:51-58`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L51-L58) fonksiyonunda:
```sql
SELECT sr.id, sr.stream_id, ls.host_id, u.user_type
FROM stream_recordings sr
JOIN live_streams ls ON ls.id = sr.stream_id
JOIN users u         ON u.id  = ls.host_id
WHERE sr.status = 'available'
  AND sr.host_notified_at IS NULL
  AND sr.available_at > NOW() - INTERVAL '6 hours'
```
1. **6 Saatten Eski Kayıtların Yaşam Döngüsünden Düşmesi:**
   - ARQ worker sunucusunda bakım, aşırı video encoding kuyruğu veya ağ kesintisi nedeniyle bir kayıt `available` olduktan sonra 6 saat içinde bu görev tarafından taranamadıysa, `available_at > NOW() - INTERVAL '6 hours'` koşulu yüzünden bu kayıt artık **asla seçilemez**.
2. **Kayıtların Sonsuza Dek MinIO'da Kilitli Kalması (Unexpirable Zombie Recordings):**
   - Kayıt taranamadığı için `sr.expires_at = NOW() + INTERVAL '24 hours'` ataması (satır 99) hiçbir zaman yapılamaz; `expires_at` kolonu sonsuza dek `NULL` kalır!
   - [`stream_recording_tasks.py:24`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/stream_recording_tasks.py#L24) içindeki `expire_recordings_task` görevi ise `WHERE status = 'available' AND expires_at < NOW()` sorgusu atar. `expires_at` değeri `NULL` olduğu için SQL üç değerli mantığında (`NULL < NOW()` -> UNKNOWN) bu satır asla `expired` olamaz!
   - Sonuç olarak bu video kayıtları ne `expired` olabilir, ne de `archive_recordings_task` tarafından arşivlenebilir. MinIO nesne depolama diskinde GB'larca video kalıcı çöp olarak birikir ve kota aşımına yol açar.

#### 2. Çözüm / Refactoring Reçetesi
1. `AND sr.available_at > NOW() - INTERVAL '6 hours'` katı filtresi kaldırılmalı veya bildirim gönderilmese dahi `expires_at` değerini `NOW() + INTERVAL '24 hours'` olarak atayan bir fallback süreci eklenmelidir:
```sql
WHERE sr.status = 'available'
  AND (sr.host_notified_at IS NULL OR sr.expires_at IS NULL)
```
2. Bildirim gönderimi başarısız olsa veya kayıt 6 saati geçmiş olsa bile, `expires_at IS NULL` olan tüm `available` kayıtlara güvenli bir son kullanma tarihi set edilerek yaşam döngüsü zincirinin kilitlenmesi önlenmelidir.

#### ✅ Çözüm Damgası
- **Commit:** `0fc91a1c` — `fix(sre-148): notify_new_recordings_task 6 saatlik pencere filtresi kaldırıldı`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/tasks/stream_recording_tasks.py`
- **Yapılan:**
  - `AND COALESCE(sr.available_at, sr.created_at) > NOW() - INTERVAL '6 hours'` satırı SELECT sorgusundan kaldırıldı; tüm unnotified `available` kayıtlar artık işleniyor
  - Bildirim döngüsü sonuna fallback UPDATE eklendi: `status='available' AND expires_at IS NULL AND host_notified_at IS NOT NULL` olan kayıtlar 14 gün ile kapatılıyor (önceki run koruması)
  - `expire_recordings_task` ve `archive_recordings_task` değişmedi; düzeltilen `expires_at` atamasıyla zincir artık doğal akışta ilerleyecek

---

### SRE-149 · 🟠 P1 (Yüksek) · Canlı Sohbet WebSocket El Sıkışmasında Çift DB Oturumu ve Bilateral Block Sorgusunda mute_key TTL Sızıntısı

- **Dosya / Modül:** [`backend/app/routers/chat.py:311-389`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/chat.py#L311-L389)
- **Kategori:** Performans & Ölçeklenebilirlik / Veritabanı Darboğazı / C10K Sızıntısı
- **Hedef:** `chat_ws` WebSocket el sıkışma mantığı

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/chat.py:311-389`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/chat.py#L311-L389) incelendiğinde:
```python
    # 1. DB Session (User + LiveStream)
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(User).where(User.id == user_id))
        ...
        stream_result = await db.execute(select(LiveStream).where(LiveStream.id == stream_id))
        ...
    # 2. DB Session (Bilateral Block)
    if not is_host and host_id:
        async with AsyncSessionLocal() as _db:
            block = await _db.scalar(
                select(UserBlock).where(
                    (UserBlock.blocker_id == host_id) & (UserBlock.blocked_id == user_id)
                    | (UserBlock.blocker_id == user_id) & (UserBlock.blocked_id == host_id)
                ).limit(1)
            )
            if block:
                _redis = await get_redis()
                await _redis.sadd(mute_key(stream_id), str(user_id))  # TTL EKSİK!
```
1. **WebSocket Handshake Sırasında Çift DB Oturumu Tahsisi:**
   - 2.000 izleyici aynı anda bir canlı yayına girdiğinde, Uvicorn üzerinde her soket peş peşe 2 ayrı `AsyncSessionLocal()` bağlantısı açar (toplam 4.000 DB connection isteği).
   - PgBouncer ve PostgreSQL connection pool'u saniyeler içinde tükenir (`PoolTimeout`); API gateway kilitlenir ve kullanıcılar `1011 Server Error` ile düşer.
2. **Kalıcı Redis Bellek Sızıntısı:**
   - Satır 380'de engellenen kullanıcı için `_redis.sadd(mute_key(stream_id), str(user_id))` çağrılır, ancak anahtara TTL verilmez (`moderation_service.py` 24 saat verirken burada atlanmıştır). Oluşturulan set anahtarları Redis RAM'inde kalıcı olarak birikir.

#### 2. Çözüm / Refactoring Reçetesi
1. Kullanıcı doğrulaması veritabanından değil, Redis'teki taze oturumdan (`session:user:{id}`) okunmalıdır.
2. Canlı yayın durumu (`is_live`, `host_id`, `room_name`) Redis `stream:meta:{id}` anahtarından çekilerek ilk DB oturumu tamamen ortadan kaldırılmalıdır.
3. Auto-mute satırına `await _redis.expire(mute_key(stream_id), 86400)` TTL eklenmelidir.

#### ✅ Çözüm Damgası
- **Commit:** `c71461b0` — `fix(sre-149): chat_ws el sıkışması ikinci DB bağlantısı kaldırıldı, mute TTL eklendi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/chat.py`
- **Yapılan:**
  - Bilateral block sorgusu ayrı `AsyncSessionLocal()` yerine stream validation ile aynı session'a taşındı; 2000 eşzamanlı bağlantıda 4000→2000 DB connection isteği
  - `mute_key` Redis set'ine `expire(86400)` TTL eklendi; kalıcı bellek sızıntısı durduruldu
  - Redis `session:user:{id}` fast-path eklendi: sıcak oturumlar DB sorgusu yapmadan doğrulanıyor; cache miss → DB fallback
  - Mimari not: `stream:meta:{id}` Redis anahtarı kodta mevcut değildi; stream sorgusu tek DB oturumuna dahil edildi (ikinci bağlantı olmadan)

---

### SRE-150 · 🟠 P1 (Yüksek) · purchase_sale Endpoint'inde Idempotency Key Eksikliği Nedeniyle Mükerrer Sipariş ve Çift Stok Düşümü

- **Dosya / Modül:** [`backend/app/routers/direct_sale.py:95-105`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/direct_sale.py#L95-L105) ve [`backend/app/use_cases/direct_sales/commands/direct_sale_commands.py:370-405`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/direct_sales/commands/direct_sale_commands.py#L370-L405)
- **Kategori:** Mali Bütünlük / Ağ Dalgalanması / Idempotency Eksikliği
- **Hedef:** `purchase_sale` endpoint'i ve sipariş akışı

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/direct_sale.py:95-105`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/direct_sale.py#L95-L105) incelendiğinde:
```python
@router.post("/{sale_id}/purchase")
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def purchase_sale(
    request: Request,
    sale_id: int,
    data: DirectSalePurchaseIn,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
):
    return await cmd.purchase_sale(sale_id, data, current_user, uow)
```
1. **İdempotency Korumasının Bulunmaması:**
   - Açık artırmada teklif verirken (`auction.py:place_bid`) `_idem=Depends(idempotency_key("bid", ttl=30))` koruması uygulanmışken, doğrudan satış satın almasında bu koruma unutulmuştur.
2. **Hücresel Ağ Tekrarında Çift Sipariş ve Stok Hırsızlığı:**
   - Mobil istemci zayıf 4G/5G bağlantısında "Satın Al" butonuna bastığında veya HTTP yanıtı istemciye ulaşmadan timeout olduğunda, mobil kütüphaneler (Dio/Retrofit) isteği otomatik olarak yeniden dener (retry).
   - Sunucu her iki isteği de bağımsız kabul eder; Lua script stoku iki kez düşer ve veritabanında aynı kullanıcı için iki ayrı `DirectSaleOrder` oluşturulur. Kısıtlı stoklu popüler ürünlerde diğer alıcıların hakkı haksız yere tükenir ve satıcı mükerrer kargo karmaşası yaşar.

#### 2. Çözüm / Refactoring Reçetesi
1. `purchase_sale` endpoint'ine `idempotency_key` bağımlılığı ve `store_idempotency_result` eklenmelidir:
```python
@router.post("/{sale_id}/purchase")
@limiter.limit("10/minute", key_func=get_user_id_or_ip)
async def purchase_sale(
    request: Request,
    sale_id: int,
    data: DirectSalePurchaseIn,
    uow: SqlAlchemyUnitOfWork = Depends(get_uow),
    current_user: User = Depends(get_current_user),
    _idem=Depends(idempotency_key("direct_sale_purchase", ttl=30)),
):
    result = await cmd.purchase_sale(sale_id, data, current_user, uow)
    await store_idempotency_result(request, result)
    return result
```

#### ✅ Çözüm Damgası
- **Commit:** `c236ef03` — `fix(sre-150): purchase_sale endpoint'ine idempotency_key koruması eklendi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/direct_sale.py`
- **Yapılan:** `_idem=Depends(idempotency_key("direct_sale_purchase", ttl=30))` parametresi ve `store_idempotency_result` çağrısı eklendi; `auction.py:place_bid` ile aynı desen

---

### SRE-151 · 🟡 P2 (Orta) · WebSocket El Sıkışmasında DM Filtresinin Unutulması ve Badge Sayısı Titremesi (Flickering)

- **Dosya / Modül:** [`backend/app/routers/notifications.py:155-163`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/notifications.py#L155-L163) ve [`backend/app/routers/notifications.py:45-58`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/notifications.py#L45-L58)
- **Kategori:** Durum Senkronizasyonu / UI Titremesi (Flickering) / Çift DB Oturumu
- **Hedef:** `notifications_ws` ve `unread_count` endpoint'leri

#### 1. Zaaf ve Arıza Modeli

1. **İki Ayrı Endpoint Arasında İş Mantığı Uyuşmazlığı:**
   - REST `/api/notifications/unread-count` endpoint'inde DM'ler sohbet menüsünde ayrı sayıldığı için `Notification.type != 'message'` filtresi ile sayım yapılır.
   - Ancak [`notifications.py:157`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/notifications.py#L157) satırındaki `notifications_ws` ilk bağlantı mesajında bu koşul unutulmuştur:
     `select(func.count()).where(Notification.user_id == user_id, Notification.is_read == False)`
   - Kullanıcı uygulamayı ilk açtığında WebSocket bağlantısı üzerinden DM'leri de içeren bir sayı (örneğin 6) gönderilir. 500 ms sonra uygulamanın attığı REST isteği DM'leri hariç tutarak 2 döner.
   - Mobil uygulamadaki bildirim kırmızı rozeti (badge) sürekli 6 ile 2 arasında zıplar (UI flicker).
2. **Gereksiz DB Oturumu Tahsisi:**
   - `notifications_ws` içinde önce kullanıcı doğrulaması için, ardından unread sayısını çekmek için 2 ayrı `AsyncSessionLocal()` bağlantısı açılır.

#### 2. Çözüm / Refactoring Reçetesi
1. `notifications_ws` içindeki sayım sorgusuna `Notification.type != "message"` filtresi eklenmelidir.
2. Kullanıcı kimlik doğrulama adımı veritabanı yerine Redis oturumundan yapılarak bağlantı havuzu yükü hafifletilmelidir.

---

### SRE-152 · 🟡 P2 (Orta) · /history Arama Geçmişi Sorgusunda OR Koşulu ve started_at İçin Bileşik İndeks Eksikliği

- **Dosya / Modül:** [`backend/app/routers/calls.py:1137-1157`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/calls.py#L1137-L1157) ve [`backend/app/models/call.py:11-17`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/call.py#L11-L17)
- **Kategori:** Veritabanı & İndeks Optimizasyonu / Disk Sort / Bitmap Scan Darboğazı
- **Hedef:** `get_call_history` endpoint'i ve `Call` tablosu indeksleri

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/calls.py:1137-1157`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/calls.py#L1137-L1157) içinde:
```python
base_where = or_(Call.caller_id == uid, Call.callee_id == uid)
...
result = await db.execute(
    select(Call)
    .where(filter_where)
    .order_by(Call.started_at.desc())
    .limit(per_page)
    .offset(offset)
)
```
1. **İndekssiz Sıralama ve BitmapOr Taraması:**
   - `Call` tablosunda `(caller_id, started_at DESC)` veya `(callee_id, started_at DESC)` şeklinde bileşik indeksler tanımlanmamıştır; sadece tekil sütun indeksleri vardır.
   - PostgreSQL, iki farklı sütun üzerindeki `OR` koşulu ile `ORDER BY started_at DESC` sıralamasını birleştirebilmek için B-Tree index scan yapamaz.
   - İlgili kullanıcının tüm aramalarını BitmapOr ile belleğe alır, disk üzerinde maliyetli bir `QuickSort` çalıştırır ve ardından LIMIT/OFFSET uygular. Çok sayıda arama kaydı biriktikçe sorgu süresi katlanarak artar.

#### 2. Çözüm / Refactoring Reçetesi
1. `calls` tablosuna bileşik indeksler eklenmelidir:
```python
Index("ix_calls_caller_started", "caller_id", "started_at"),
Index("ix_calls_callee_started", "callee_id", "started_at"),
```
2. Çok büyük tablolarda `OR` yerine `UNION ALL` yapısına dönüştürülerek her iki dalın kendi B-Tree indeksinden logaritmik hızda taranması sağlanmalıdır.

---

### SRE-153 · 🟡 P2 (Orta) · /signal Endpoint'inde Her İlan Tıklamasında Senkron NumPy Vektör Matematiği ile Uvicorn Event Loop Donması

- **Dosya / Modül:** [`backend/app/routers/feed.py:159-203`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/feed.py#L159-L203)
- **Kategori:** Performans & Concurrency / CPU-Bound Event Loop Blokajı / Latency Spikes
- **Hedef:** `record_feed_signal` endpoint'i

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/feed.py:159-203`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/feed.py#L159-L203) içinde bir kullanıcı feed akışında bir ilana tıkladığında mobil uygulama arkadan `/signal` POST isteği atar:
```python
    emb_row = await db.scalar(
        select(Listing.embedding).where(Listing.id == payload.listing_id)
    )
    ...
    new_vec = np.array(emb_row, dtype=np.float32)
    norm = np.linalg.norm(new_vec)
    if norm > 0:
        new_vec /= norm
    ...
    blended = (1 - alpha) * old_vec + alpha * new_vec
    bn = np.linalg.norm(blended)
```
1. **Asenkron Event Loop İçinde Senkron Ağır Matematik:**
   - Binlerce kullanıcı aynı anda akışı kaydırıp ilanlara tıkladığında, Uvicorn asenkron worker thread'i üzerinde her tıklamada senkron NumPy array tahsisi, `np.linalg.norm` ve vektör harmanlama işlemleri çalıştırılır.
   - Bu CPU-bound işlemler Python GIL'i ve Uvicorn tek event-loop'unu mikrosaniyelerce dondurur. Canlı yayın chat mesajları ve teklif paketleri kuyrukta bekler, latency spike'lar oluşur.

#### 2. Çözüm / Refactoring Reçetesi
1. İlan embedding'i her istekte PostgreSQL'den değil, Redis'te 24 saat önbelleklenmiş hazır vektörden okunmalıdır.
2. Vektör hesaplamaları `asyncio.to_thread` ile ayrı bir thread havuzuna veya arka plan sinyal kuyruğuna (ARQ/Redis Stream) aktarılmalıdır.

---

### SRE-154 · 🟡 P2 (Orta) · GET /nodes/{id} Tekil Düğüm Sorgusunda Tüm Canlı Düğümlerin O(N) redis.keys() ile Taranması

- **Dosya / Modül:** [`backend/app/routers/admin_nodes.py:24-30`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_nodes.py#L24-L30) ve [`backend/app/services/edge_orchestrator.py:31-45`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/edge_orchestrator.py#L31-L45)
- **Kategori:** Mimari Verimlilik / Redis Yükü / Gereksiz Küme Taraması
- **Hedef:** `get_node` admin endpoint'i

#### 1. Zaaf ve Arıza Modeli

[`backend/app/routers/admin_nodes.py:24-30`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_nodes.py#L24-L30) içinde:
```python
@router.get("/{node_id}", dependencies=[Depends(check_admin_access)])
async def get_node(node_id: str) -> Dict[str, Any]:
    for m in await orchestrator.get_all_metrics():
        if m.get("node_id") == node_id:
            return m
    raise HTTPException(status_code=404, detail=f"Node '{node_id}' aktif değil")
```
1. **Tekil Sorgu İçin Tüm Kümenin Taranması:**
   - Admin paneli tek bir node'un detayını istediğinde, doğrudan `edge:metrics:{node_id}` anahtarına gitmek yerine `get_all_metrics()` çağrılır.
   - `get_all_metrics()` fonksiyonu Redis üzerinde `await redis.keys("edge:metrics:*")` ve `mget(*keys)` çalıştırır. Kümedeki tüm sunucuların JSON metrikleri RAM'e çekilir, `json.loads` ile ayrıştırılır ve ardından Python döngüsüyle istenen `node_id` aranır.
   - Tek bir GET isteği için Redis tek thread'i bloklanır ve gereksiz ağ trafiği yaratılır.

#### 2. Çözüm / Refactoring Reçetesi
1. `get_node` doğrudan tekil Redis anahtarını okumalıdır:
```python
@router.get("/{node_id}", dependencies=[Depends(check_admin_access)])
async def get_node(node_id: str) -> Dict[str, Any]:
    redis = await get_redis()
    raw = await redis.get(f"edge:metrics:{node_id}")
    if not raw:
        raise HTTPException(status_code=404, detail=f"Node '{node_id}' aktif değil")
    return json.loads(raw)
```

---

### SRE-155 · 🔴 P0 (Kritik) · DM Arşiv Görevinde Yanlış Bucket Okuması ve `except Exception: pass` Nedeniyle MinIO'daki Tüm Geçmiş Yılların DM Arşivlerinin Kalıcı Olarak Silinmesi (Catastrophic Silent Archive Overwrite & Permanent Data Loss)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/tasks/dm_archive_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/dm_archive_tasks.py#L75-L108) (satırlar 75–108)
  * [`backend/app/services/storage_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L147-L170) (satırlar 147–170, 191–207)

`dm_archive_tasks.py` içindeki `archive_old_dm_task` görevi, 1 yıldan eski okunmuş doğrudan mesajları (DM) konuşma ve yıl bazında paketleyerek MinIO arşivine aktarır ve PostgreSQL'den siler:

```python
# dm_archive_tasks.py satır 75–96:
for (user_a, user_b, year), msgs in groups.items():
    object_key = f"{_DM_ARCHIVE_PREFIX}/{user_a}_{user_b}/{year}.json.gz"

    # Mevcut arşivi oku ve birleştir (aynı yıl birden fazla çalışma olursa)
    existing: list[dict] = []
    try:
        existing_bytes = await storage.get_object_bytes(object_key)
        if existing_bytes:
            existing = json.loads(gzip.decompress(existing_bytes))
    except Exception:
        pass

    existing_ids = {m["id"] for m in existing}
    new_msgs = [m for m in msgs if m["id"] not in existing_ids]
    merged = existing + new_msgs
    merged.sort(key=lambda m: m["created_at"])

    payload = gzip.compress(json.dumps(merged, ensure_ascii=False).encode())
    await storage.upload_bytes_dm(object_key, payload, content_type="application/gzip")

    deleted_ids.extend(m["id"] for m in new_msgs)
    archived_pairs.add((user_a, user_b))
```

1. **İki Farklı Bucket Uyuşmazlığı:**
   - Satır 81'de çağrılan `storage.get_object_bytes(object_key)` fonksiyonu ([`storage_service.py:154`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L154)), genel/public `"teqlif"` (`settings.minio_bucket`) kovasına bakmaktadır.
   - Ancak satır 93'te çağrılan `storage.upload_bytes_dm(...)` fonksiyonu ([`storage_service.py:197`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py#L197)), veriyi gizli/private `"teqlif-dm"` (`settings.minio_dm_bucket`) kovasına yazmaktadır!
   - `storage_service.py` içinde DM kovasından dosya indiren bir `get_object_bytes_dm` fonksiyonu dahi bulunmamaktadır.
2. **Sessizce Ezme ve Kalıcı Veri Kaybı:**
   - `storage.get_object_bytes` `"teqlif"` kovasında `dm-archive/...` dosyasını aradığında MinIO `NoSuchKey` hatası döner.
   - Satır 84–85'teki `except Exception: pass` bloğu bu hatayı sessizce yutar ve `existing = []` kalır.
   - `merged = existing + new_msgs` ifadesi sadece yeni mesajları kapsar.
   - Ardından `upload_bytes_dm(object_key, payload)` çağrıldığında, `"teqlif-dm"` kovasındaki o yıla ait önceki arşiv dosyası YALNIZCA yeni mesajlarla tamamen ezilir (overwrite).
   - Akabinde satır 105'teki `DELETE FROM direct_messages WHERE id = ANY(:ids)` çalıştığı için veritabanındaki mesajlar da silinir.
   - **Sonuç:** Kullanıcıların önceki haftalarda/aylarda arşivlenen binlerce eski DM mesajı MinIO'dan tamamen yok olur; PostgreSQL'den de önceden silindiği için GERİ DÖNDÜRÜLEMEZ KALICI VERİ KAYBI (CATASTROPHIC DATA LOSS) yaşanır.

#### 2. Çözüm / Refactoring Reçetesi
1. [`backend/app/services/storage_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/storage_service.py) içine `get_object_bytes_dm` fonksiyonunu ekleyin:
```python
async def get_object_bytes_dm(key: str) -> bytes | None:
    """Private DM bucket'tan nesneyi bytes olarak indirir. Yoksa None döner."""
    try:
        node = await orchestrator.allocate_node(ServiceType.STORAGE)
        client = _get_client_for_internal_url(node["minio_url"])

        def _get() -> bytes:
            resp = client.get_object(settings.minio_dm_bucket, key)
            try:
                return resp.read()
            finally:
                resp.close()
                resp.release_conn()

        return await asyncio.to_thread(_get)
    except S3Error as e:
        if e.code == "NoSuchKey":
            return None
        logger.error("[STORAGE_DM] get_object_bytes_dm hata: key=%s | %s", key, e)
        raise
    except Exception as exc:
        logger.error("[STORAGE_DM] get_object_bytes_dm beklenmeyen hata: %s", exc)
        raise
```

2. [`backend/app/tasks/dm_archive_tasks.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/tasks/dm_archive_tasks.py#L78-L88) içinde `get_object_bytes_dm` kullanın ve genel `Exception` yutmasını kaldırın:
```python
            existing: list[dict] = []
            existing_bytes = await storage.get_object_bytes_dm(object_key)
            if existing_bytes:
                try:
                    existing = json.loads(gzip.decompress(existing_bytes))
                except Exception as exc:
                    logger.error("[DM_ARCHIVE] Gzip decompress hatası: %s | %s", object_key, exc)
                    raise
```

> ✅ **Çözüldü** — commit `282d715b`, 2026-10-30

---

### SRE-156 · 🔴 P0 (Kritik) · `init_context` ve `get_conversations` Endpoint'lerinde Tekil `AsyncSession` Üzerinde `asyncio.gather` ile Eşzamanlı DB Sorgusu Çalıştırılması ve HTTP 500 Çökmesi (`IllegalStateChangeError`)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/auth.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L364-L378) (satırlar 364–378)
  * [`backend/app/use_cases/messages/queries/get_conversations_query.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/messages/queries/get_conversations_query.py#L103-L115) (satırlar 103–115)

FastAPI endpoint'lerinde SQLAlchemy `AsyncSession` dependency injection (`Depends(get_db)`) ile tek bir oturum olarak gelir. `auth.py` satır 364–378 ve `get_conversations_query.py` satır 103–115'te bu tekil oturum üzerinde paralel sorgular koşturulmaktadır:

```python
# auth.py satır 364–378:
notif_result, msg_result = await asyncio.gather(
    db.execute(
        select(func.count()).where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,  # noqa: E712
            Notification.type != "message",
        )
    ),
    db.execute(
        select(func.count()).where(
            DirectMessage.receiver_id == current_user.id,
            DirectMessage.is_read == False,  # noqa: E712
        )
    ),
)
```

```python
# get_conversations_query.py satır 103–115:
users_result, unread_result = await asyncio.gather(
    self.uow.session.execute(select(User).where(User.id.in_(other_ids))),
    self.uow.session.execute(
        select(DirectMessage.sender_id, func.count().label("cnt"))
        .where(
            DirectMessage.receiver_id == uid,
            DirectMessage.is_read == False,
            DirectMessage.is_shadowbanned == False,
        )
        .group_by(DirectMessage.sender_id)
    ),
)
```

1. **SQLAlchemy ve asyncpg Concurrency Kuralı İhlali:**
   - SQLAlchemy `AsyncSession` ve altındaki `asyncpg` bağlantısı kesinlikle reentrant veya eşzamanlı (concurrent) değildir.
   - Tek bir `AsyncSession` üzerinde `execute()` çalışırken başka bir `execute()` çağrıldığında bağlantı kilitlenir ve derhal şu istisna fırlatılır:
     `sqlalchemy.exc.IllegalStateChangeError: Method 'execute()' can't be called here; another operation is already in progress concurrently on this Session!`
   - `init_context`, mobil uygulamanın ilk açılışta çağırdığı 1 numaralı bootstrap endpoint'idir ("Used by the frontend to reduce page-load API calls from 4 to 1").
   - Ağ gecikmesi veya veritabanı yükü altında iki coroutine aynı anda event loop'a düştüğünde, kullanıcı uygulamayı açtığı anda HTTP 500 alır ve uygulama açılış ekranında kilitlenir.

#### 2. Çözüm / Refactoring Reçetesi
1. [`backend/app/routers/auth.py:init_context`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L364-L378) içindeki `asyncio.gather`'ı kaldırın ve sıralı `await` ile çalıştırın:
```python
    notif_count = await db.scalar(
        select(func.count()).where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,  # noqa: E712
            Notification.type != "message",
        )
    )
    msg_count = await db.scalar(
        select(func.count()).where(
            DirectMessage.receiver_id == current_user.id,
            DirectMessage.is_read == False,  # noqa: E712
        )
    )
```

2. [`backend/app/use_cases/messages/queries/get_conversations_query.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/messages/queries/get_conversations_query.py#L103-L115) içindeki `asyncio.gather`'ı kaldırın:
```python
        users_result = await self.uow.session.execute(select(User).where(User.id.in_(other_ids)))
        unread_result = await self.uow.session.execute(
            select(DirectMessage.sender_id, func.count().label("cnt"))
            .where(
                DirectMessage.receiver_id == uid,
                DirectMessage.is_read == False,
                DirectMessage.is_shadowbanned == False,
            )
            .group_by(DirectMessage.sender_id)
        )
```

> ✅ **Çözüldü** — commit `282d715b`, 2026-10-30

---

### SRE-157 · 🟠 P1 (Yüksek) · `cleanup_empty_message_threads_task` İçinde `has_archive` Kontrolü Olmaması Nedeniyle Arşivlenmiş Tüm Konuşma Başlıklarının ve Kullanıcı İzinlerinin Silinmesi

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/worker.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L650-L660) (satırlar 650–660)
  * [`backend/app/models/message_thread.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/message_thread.py#L29-L30) (satırlar 29–30)

`MessageThread` tablosu iki kullanıcı arasındaki mesajlaşma başlığını, arama izinlerini (`call_allowed`), silinme tarihlerini (`deleted_at_a`, `deleted_at_b`) ve arşiv durumunu (`has_archive: bool`) saklar.

`worker.py` satır 651–659'da haftalık temizlik görevi şu sorguyu çalıştırır:
```sql
DELETE FROM message_threads mt 
WHERE mt.status != 'pending' 
AND NOT EXISTS (
  SELECT 1 FROM direct_messages dm 
  WHERE (dm.sender_id = mt.user_a_id AND dm.receiver_id = mt.user_b_id) 
     OR (dm.sender_id = mt.user_b_id AND dm.receiver_id = mt.user_a_id)
) AND mt.created_at < NOW() - INTERVAL '30 days'
```

1. **Arşivli Konuşmaların Boş Sanılması:**
   - `dm_archive_tasks.py` Pazar 03:00 UTC'de çalışır, 1 yıldan eski okunmuş mesajları MinIO'ya taşır, `message_threads.has_archive = TRUE` yapar ve mesajları `direct_messages` tablosundan siler.
   - Pazar 05:00 UTC'de (2 saat sonra) `cleanup_empty_message_threads_task` çalışır.
   - Sorguda `AND mt.has_archive = FALSE` koşulu BULUNMAMAKTADIR!
   - Veritabanındaki `direct_messages` satırları arşive taşındığı için `NOT EXISTS` koşulu `TRUE` döner ve PostgreSQL `message_threads` kaydını bütünüyle siler!
2. **Kayıp Meta Veriler ve Yetim Arşivler:**
   - Konuşma silindiği için kullanıcının gelen kutusunda konuşma kaybolur.
   - `has_archive` bayrağı silindiği için kullanıcıların MinIO'daki 1 yıllık arşivlerine erişebileceği arayüz bağlantısı kopar.
   - Kullanıcıların `call_allowed` (sesli arama izni) ayarları ve konuşma silme zaman damgaları yok olur. Yeni bir mesaj atıldığında `has_archive = FALSE` ile yeni bir başlık açılır ve MinIO'daki arşiv sonsuza dek yetim kalır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/worker.py:651-659`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L651-L659) sorgusuna `AND mt.has_archive = FALSE` koşulunu ekleyin:
```python
            result = await db.execute(text(
                "DELETE FROM message_threads mt "
                "WHERE mt.status != 'pending' "
                "AND mt.has_archive = FALSE "
                "AND NOT EXISTS ("
                "  SELECT 1 FROM direct_messages dm "
                "  WHERE (dm.sender_id = mt.user_a_id AND dm.receiver_id = mt.user_b_id) "
                "     OR (dm.sender_id = mt.user_b_id AND dm.receiver_id = mt.user_a_id)"
                ") AND mt.created_at < NOW() - INTERVAL '30 days'"
            ))
            await db.commit()
```

#### ✅ Çözüm Damgası
- **Commit:** `e4aa689f` — `fix(sre-157): message_threads GC sorgusuna has_archive=FALSE filtresi eklendi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/worker.py`
- **Yapılan:** DELETE sorgusuna `AND mt.has_archive = FALSE` koşulu eklendi; arşivi olan thread'ler GC tarafından artık silinmiyor

---

### SRE-158 · 🟠 P1 (Yüksek) · `send_retargeting` Endpoint'inde Bakiye Düşümü Öncesinde 500 Kişiye Push Gönderilmesi Nedeniyle Karşılıksız Bildirim İstismarı (Free Retargeting Exploit)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/leads.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/leads.py#L591-L616) (satırlar 591–616)

`leads.py:send_retargeting` endpoint'i, ilanı inceleyen kullanıcılara push bildirimi göndermek için kullanılır:

```python
# leads.py satır 591–607:
    sent = 0
    for i in range(0, len(fcm_tokens), 50):
        chunk = fcm_tokens[i: i + 50]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)

    # TEQlik düş + kredi say
    if teqlik_cost > 0:
        deduct = await db.execute(
            sql_text(
                "UPDATE users SET teqlik_balance = teqlik_balance - :cost "
                "WHERE id = :uid AND teqlik_balance >= :cost RETURNING teqlik_balance"
            ),
            {"cost": teqlik_cost, "uid": current_user.id},
        )
        if deduct.fetchone() is None:
            raise InsufficientFundsException(code="INSUFFICIENT_FUNDS_RETARGET")
```

1. **Ters İşlem Sıralaması (Action Before Payment):**
   - Satır 591–596 arasında Firebase üzerinden 500 kişiye kadar anlık push bildirimleri gönderilir.
   - Ancak kullanıcının TEQlik bakiyesi satır 599–607 arasında düşülmeye çalışılır.
   - Eğer kullanıcı aynı anda cüzdanından para çekmişse, başka bir cihaza transfer yapmışsa veya eşzamanlı iki retargeting isteği göndermişse, bakiye düşümü `InsufficientFundsException` fırlatır; ancak 500 kullanıcıya bildirimler ÇOKTAN GÖNDERİLMİŞTİR!
   - Kullanıcı platformun push kotasını ve kaynaklarını sıfır bakiye ile bedava sömürmüş olur.
2. **Eksik Cooldown Koruması:**
   - `send-blast` endpoint'inde 24 saatlik `_last_lead_blast` cooldown kontrolü varken, `send_retargeting` endpoint'inde hiçbir cooldown bulunmamaktadır. Kötü niyetli bir PRO kullanıcı aynı kitleye art arda bildirim spam'i yapabilir.

#### 2. Çözüm / Refactoring Reçetesi
1. Bakiye kontrolünü ve atomik düşümünü push gönderiminden ÖNCEYE alın:
```python
    # 1. Önce TEQlik rezervasyonu / düşümü yap
    if teqlik_cost > 0:
        deduct = await db.execute(
            sql_text(
                "UPDATE users SET teqlik_balance = teqlik_balance - :cost "
                "WHERE id = :uid AND teqlik_balance >= :cost RETURNING teqlik_balance"
            ),
            {"cost": teqlik_cost, "uid": current_user.id},
        )
        if deduct.fetchone() is None:
            raise InsufficientFundsException(code="INSUFFICIENT_FUNDS_RETARGET")
        db.add(TeqlikTransaction(
            user_id=current_user.id,
            amount=-teqlik_cost,
            transaction_type="spend_retargeting",
            reference_id=body.listing_id,
            reference_type="listing",
        ))
        await db.commit()
        await invalidate_user_session_cache(current_user.id)

    # 2. Bakiye başarıyla düşüldükten sonra bildirimleri gönder
    sent = 0
    for i in range(0, len(fcm_tokens), 50):
        chunk = fcm_tokens[i: i + 50]
        await asyncio.gather(*[_send_one(t) for t in chunk])
        sent += len(chunk)
```
2. Endpoint'in başına 24 saatlik cooldown kontrolü ekleyin.

#### ✅ Çözüm Damgası
- **Commit:** `eb974dd9` — `fix(sre-158): retargeting bakiye düşümü push öncesine alındı, 24s cooldown eklendi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/leads.py`
- **Yapılan:**
  - Atomik `UPDATE teqlik_balance … RETURNING` bloğu push döngüsünden önceye taşındı; bakiye yetersizse `InsufficientFundsException` push gönderilmeden fırlatılıyor
  - `retarget:cd:{user_id}:{listing_id}` Redis anahtarı 86400s TTL ile eklendi; PRO kontrolünden hemen sonra kontrol edilip `CooldownException` fırlatıldı
  - Cooldown key bakiye commit'inden sonra yazılıyor (başarısız işlem cooldown tüketmiyor)
  - `return` dict'indeki yinelenen `"sent"` anahtarı temizlendi

---

### SRE-159 · 🟠 P1 (Yüksek) · `start_call` Başlatma Sırasında Yalnızca `callee_id` Üzerine Advisory Lock Alınması Nedeniyle Karşılıklı Eşzamanlı Aramalarda Çift Çağrı ve Canlı Çakışma (Mutual Call Split-Brain)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/calls.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/calls.py#L624-L645) (satırlar 624–645)

`calls.py:start_call` içinde iki arayanın aynı kişiyi aynı anda aramasını engellemek için PostgreSQL advisory transaction lock kullanılır:

```python
# calls.py satır 624–635:
await db.execute(text("SELECT pg_advisory_xact_lock(42, :cid)"), {"cid": callee_id})

# Check if callee is already in an active call
active_call = await db.scalar(
    select(Call).where(
        or_(Call.caller_id == callee_id, Call.callee_id == callee_id),
        Call.status.in_(["calling", "active"])
    )
)
if active_call:
    raise AppException(status_code=409, message="User is busy", code="USER_BUSY")
```

1. **Yalnızca Callee'nin Kilitlenmesi ve Asimetrik Yarış Durumu:**
   - Kilit yalnızca `(42, callee_id)` parametresiyle alınır; arayan (`current_user.id`) kilitlenmez.
   - Eğer Kullanıcı A (ID=10) ve Kullanıcı B (ID=20) aynı saniyede birbirini ararsa:
     * İstek 1 (10 -> 20): `pg_advisory_xact_lock(42, 20)` kilidini alır. DB'de 20 henüz meşgul değildir.
     * İstek 2 (20 -> 10): `pg_advisory_xact_lock(42, 10)` kilidini alır. DB'de 10 henüz meşgul değildir.
     * Her iki kilit farklı anahtarlarda olduğundan birbirini bloklamaz.
     * Her iki işlem de `active_call` kontrolünden geçer, yeni bir `Call` satırı ekler ve commit eder.
   - Sonuç: Veritabanında `Call(caller=10, callee=20, status='calling')` ve `Call(caller=20, callee=10, status='calling')` olmak üzere iki aktif arama kaydı ve LiveKit üzerinde iki ayrı oda (`call_10_20_...` ve `call_20_10_...`) oluşturulur.
   - Her iki kullanıcının ekranında da karşı tarafın çaldığı görünür; taraflardan biri açtığında diğer odaya bağlanır ve karşı tarafla asla buluşamaz (split-brain).

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/calls.py:624`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/calls.py#L624) satırındaki advisory lock'ı, iki kullanıcı arasındaki sıralı kanonik çift (`min(u1, u2), max(u1, u2)`) üzerinden alın:

```python
    # Serialize concurrent start_call between the pair in either direction.
    # Canonical ordering (min, max) guarantees that A->B and B->A fight for the exact same lock.
    u_min, u_max = min(current_user.id, callee_id), max(current_user.id, callee_id)
    await db.execute(
        text("SELECT pg_advisory_xact_lock(:u_min, :u_max)"),
        {"u_min": u_min, "u_max": u_max},
    )
```

#### ✅ Çözüm Damgası
- **Commit:** `92405f59` — `fix(sre-159): advisory lock kanonik çift sıralamasına (min,max) geçirildi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/calls.py`
- **Yapılan:** `pg_advisory_xact_lock(42, callee_id)` → `pg_advisory_xact_lock(min(caller,callee), max(caller,callee))` — A→B ve B→A istekleri artık aynı kilit üzerinde serialize ediliyor

---

### SRE-160 · 🟡 P2 (Orta) · `create_campaign` Endpoint'inde `total_budget` ve `cpc_bid` Üzerinde Tavan Kontrolü Olmaması Nedeniyle Bütçe Enflasyonu

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/ads.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/ads.py#L38-L42) (satırlar 38–42, 94–101)
  * [`backend/app/services/ad_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ad_service.py#L70-L75) (satırlar 70–75)

```python
# ads.py satır 38–42:
class CampaignCreate(BaseModel):
    listing_id: int
    total_budget: int = Field(gt=0)
    cpc_bid: int = Field(gt=0)
```

1. **Sabit Ücret vs. Sınırsız Bütçe Tutarsızlığı:**
   - Platform reklam modelinde satıcı, kampanya açarken bütçeyi peşin ödemez; PRO ise ayda 3 kez 0 TEQlik ile, standart ise 50 TEQlik sabit boost ücretiyle kampanya başlatır.
   - Ancak `CampaignCreate` modelinde `total_budget` ve `cpc_bid` için hiçbir üst tavan (`le`) tanımlanmamıştır.
   - Bir kullanıcı `total_budget=1_000_000_000` ve `cpc_bid=50_000` gönderdiğinde, sistem yalnızca 50 TEQlik (veya 0) alır ve kampanyayı `active` olarak kaydeder.
   - `ad_service.py:load_active_campaigns_to_redis()` bu kampanyayı Redis'e `ad_campaign_budget:X = 1000000000` ve `ad_campaign_cpc:X = 50000` olarak yazar.
   - Keşfet akışındaki açık artırma algoritması (`feed_queries.py`), en yüksek `cpc_bid` veren kampanyayı feed'in ilk sıralarına yerleştirdiği için, bu hayali bütçeli kampanya diğer tüm meşru satıcıların reklamlarını süpürerek platformun reklam algoritmasını kilitler.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/ads.py:38-42`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/ads.py#L38-L42) içindeki Pydantic şemasına makul üst tavan sınırları getirin:
```python
class CampaignCreate(BaseModel):
    listing_id: int
    total_budget: int = Field(gt=0, le=5000, description="Maksimum toplam kampanya bütçesi (TEQlik)")
    cpc_bid: int = Field(gt=0, le=100, description="Tıklama başına maksimum teklif (TEQlik)")
```

---

### SRE-161 · 🔴 P0 (Kritik) · `accept_bid` Sırasında Redis Üzerinde Atomik Kilitleme Olmaması Nedeniyle Eşzamanlı Tekliflerle Haksız İhale Gasbı (Unsynchronized Auction Acceptance & Race Condition)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/use_cases/auctions/commands/auction_commands.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/auctions/commands/auction_commands.py#L848-L880) (satırlar 848–880, 963–977)
  * [`backend/app/repositories/auction_redis_repo.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/repositories/auction_redis_repo.py#L89-L103) (satırlar 89–103)

```python
# auction_commands.py satır 848–864:
async def accept_bid(self, stream_id: int, user: User, proof_image_url: Optional[str] = None) -> dict:
    await self._require_host(stream_id, user)

    data = await self.redis_repo.get_state(stream_id)
    if not data or data.get("status") not in ("active", "paused"):
        raise BadRequestException(code="AUCTION_NOT_ACTIVE")

    winner_name = data.get("current_bidder_name", "")
    if not winner_name:
        raise BadRequestException(code="NO_BID_TO_ACCEPT")

    winner_id_str = data.get("current_bidder_id", "")
    final_price = float(data["current_bid"])
    # ... Saga adımları ve DB commit (50-200ms) ...
```

1. **Atomik Kilit Eksikliği ve Durum Tutarsızlığı:**
   - `accept_buy_it_now` metodunda (satır 605), Redis üzerinde `_BUY_IT_NOW_ACCEPT_SCRIPT` Lua script'i çalıştırılarak durum atomik olarak `buy_it_now_locked` yapılır ve başka hiçbir işlemin araya girmesine izin verilmez.
   - Buna karşın `accept_bid` metodunda, Redis'ten yalnızca `get_state()` ile anlık durum okunur; Redis'teki durum `'accepting'` veya `'locked'` yapılmaz, `'active'` olarak kalmaya devam eder!
2. **Yüksek Teklifin Ezilmesi ve İhale Gasbı (Race Condition):**
   - Yayıncı "Teklifi Kabul Et" butonuna bastığında, veritabanında `select(Listing).with_for_update()`, `Auction` kaydı ekleme ve `commit()` süreci (50–200 ms) devam ederken, Redis'teki durum hâlâ `'active'` durumdadır.
   - Bu sırada başka bir katılımcı daha yüksek bir teklif (örneğin 1.000 TL yerine 1.500 TL) verdiğinde, `place_bid` içindeki `_BID_SCRIPT` Lua script'i durumu `'active'` gördüğü için 1.500 TL'lik teklifi başarıyla kabul eder, DB'ye `Bid` kaydını atar ve WebSocket üzerinden herkese en yüksek teklif olarak duyurur.
   - Ancak arka planda tamamlanan `accept_bid`, eski 1.000 TL'lik teklif sahibini kazanan ilan eder ve `delete_auction()` çağırarak açık artırma state'ini Redis'ten siler!
   - 1.500 TL veren meşru alıcı açık artırmanın galibi olması gerekirken mağdur edilir, satıcı daha düşük fiyata satış yapmış olur ve sistemde derin bir mali/güvenilirlik açığı oluşur. Çift tıklama durumunda ise mükerrer `Auction` kayıtları üretilir.

#### 2. Çözüm / Refactoring Reçetesi
1. [`backend/app/repositories/auction_redis_repo.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/repositories/auction_redis_repo.py) içine atomik `_ACCEPT_BID_LOCK_SCRIPT` ekleyin:
```python
_ACCEPT_BID_LOCK_SCRIPT = """
local key = KEYS[1]
local status = redis.call('hget', key, 'status')
if status ~= 'active' and status ~= 'paused' then
    return {0, 'not_active'}
end
local current_bid = redis.call('hget', key, 'current_bid')
if not current_bid or current_bid == '' then
    return {0, 'no_bid'}
end
local bidder_id = redis.call('hget', key, 'current_bidder_id') or ''
local bidder_name = redis.call('hget', key, 'current_bidder_name') or ''
redis.call('hset', key, 'status', 'accepting')
return {1, current_bid, bidder_id, bidder_name}
"""
```
2. [`backend/app/use_cases/auctions/commands/auction_commands.py:848-865`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/auctions/commands/auction_commands.py#L848-L865) içinde `accept_bid` başlangıcında bu script'i çağırarak ihaleyi atomik kilitleyin:
```python
ok, msg, winner_id_str, winner_name = await self.redis_repo.lock_accept_bid(stream_id)
if ok == 0:
    if msg == "no_bid":
        raise BadRequestException(code="NO_BID_TO_ACCEPT")
    raise BadRequestException(code="AUCTION_NOT_ACTIVE")
final_price = float(msg)
```

---

### SRE-162 · 🔴 P0 (Kritik) · `purge_user` Endpoint'inde `token_version` Artırılmaması, Session Cache ve İlan/Yayınların Temizlenmemesi Nedeniyle Silinen Kullanıcının Oturumunun Sürmesi (Zombie Session & Orphaned Listings on Account Purge)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/admin_data.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_data.py#L453-L495) (satırlar 453–495)

```python
# admin_data.py satır 469–484:
    user.email        = f"purged_{user_id}@deleted.invalid"
    user.username     = f"deleted_{user_id}"
    user.full_name    = "Deleted Account"
    user.phone        = None
    user.phone_verified = False
    user.hashed_password = ""
    user.avatar_url   = None
    user.bio          = None
    user.website_url  = None
    user.fcm_token    = None
    user.status = UserStatus.DELETED
    user.email_verified = False

    await db.commit()
```

1. **Oturum İptali (Session Revocation) Unutulması:**
   - `delete_user` endpoint'inde (satır 420 ve 443) `user.token_version = (user.token_version or 0) + 1` ve `await invalidate_user_session_cache(user_id)` doğru biçimde çağrılırken, kalıcı anonimizasyon yapan `purge_user` endpoint'inde bu iki kritik satır tamamen unutulmuştur.
   - Redis üzerinde `session:user:{user_id}` anahtarı 15 dakikalık (`_USER_SESSION_TTL = 900`) süre boyunca silinen kullanıcının eski kimlik ve aktiflik durumunu (`UserStatus.ACTIVE`) önbellekte tutmaya devam eder.
   - Purge edilen kötü niyetli kullanıcı veya dolandırıcı, elindeki mevcut JWT token ile 15 dakika boyunca tüm kimlik doğrulamalı API'leri çağırmaya, mesaj göndermeye ve işlem yapmaya devam edebilir.
2. **Yetim İlan ve Canlı Yayınların Piyasada Kalması:**
   - `purge_user` işleminde kullanıcının aktif ilanları (`Listing.status`) pasife çekilmez ve varsa devam eden canlı yayını (`LiveStream.is_live`) sonlandırılmaz. Piyasada satıcısı anonimleştirilmiş/silinmiş ilanlar aktif kalır ve alıcılar muhatapsız ilanlara teklif vererek dolandırıcılık veya kilitlenme riskiyle karşılaşır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/admin_data.py:480-494`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_data.py#L480-L494) arasına token revokasyonu, ilan pasifleştirme ve session cache temizliği ekleyin:
```python
    user.status = UserStatus.DELETED
    user.token_version = (user.token_version or 0) + 1
    user.email_verified = False

    # İlanları pasife çek ve feed önbelleğinden temizle
    await db.execute(
        Listing.__table__.update()
        .where(Listing.user_id == user_id)
        .values(status='passive')
    )
    # Aktif canlı yayını varsa zorla sonlandır
    from app.use_cases.streams.commands.force_close_stream import force_close_stream
    active_stream = (await db.execute(
        select(LiveStream).where(LiveStream.host_id == user_id, LiveStream.is_live == True)
    )).scalar_one_or_none()
    if active_stream:
        await force_close_stream(db, active_stream.room_name)

    await db.commit()

    await invalidate_user_session_cache(user_id)
    try:
        redis = await get_redis()
        await redis.delete(
            f"session:user:{user_id}",
            f"interests:{user_id}",
            f"feed:{user_id}:0",
            f"shadowban:{user_id}",
        )
    except Exception:
        pass
```

---

### SRE-163 · 🟠 P1 (Yüksek) · `update_user_info` İçinde Yalnızca `PASSIVE` Durumunda `token_version` Artırılması Nedeniyle Banlanan Kullanıcının Oturumunun Sürmesi (Session Revocation Bypass on Admin Ban)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/admin_data.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_data.py#L187-L196) (satırlar 187–196)
  * [`backend/app/models/enums.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/enums.py#L11-L16) (satırlar 11–16)

```python
# admin_data.py satır 187–192:
    if data.status is not None:
        new_status = UserStatus(data.status)
        user.status = new_status
        if new_status == UserStatus.PASSIVE:
            user.token_version = (user.token_version or 0) + 1
    await db.commit()
```

1. **Eksik Enum Kontrolü ile Güvenlik Duvarı Bypassı:**
   - `UserStatus` enum'ı `ACTIVE`, `PASSIVE`, `BANNED`, `DELETED`, `INACTIVE` değerlerini içerir.
   - Yönetici backoffice üzerinden bir kullanıcıyı cezalandırıp doğrudan `banned` veya `deleted` durumuna getirdiğinde, `if new_status == UserStatus.PASSIVE:` koşulu `False` döner ve kullanıcının `token_version` değeri veritabanında artırılmaz!
   - `get_current_user` doğrulaması (`auth.py:189`) istemcinin JWT'sindeki versiyon ile DB'deki `user.token_version`'ı kıyaslar. Versiyon değişmediği için, banlanan kullanıcının mevcut JWT token'ı kriptografik ve mantıksal olarak geçerli kalır.
   - Redis session cache silinse dahi, `_fetch_and_cache_user` DB'den okurken token versiyonu eşleştiği için oturumu sonlandırmaz (`401 Oturum sonlandırıldı` yerine yalnızca status check'e bağımlı kalır; cache TTL veya ara katman gecikmelerinde API çağrıları sızar).

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/admin_data.py:190`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/admin_data.py#L190) içindeki tekil durumu genişleterek `ACTIVE` dışındaki tüm pasifleştirme ve yasaklama durumlarında `token_version`'ı artırın:
```python
    if data.status is not None:
        new_status = UserStatus(data.status)
        user.status = new_status
        if new_status in (UserStatus.PASSIVE, UserStatus.BANNED, UserStatus.DELETED):
            user.token_version = (user.token_version or 0) + 1
            user.fcm_token = None
```

#### ✅ Çözüm Damgası
- **Commit:** `2b549b49` — `fix(sre-163): admin ban/delete durumlarında token_version artırıldı, FCM temizlendi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/routers/admin_data.py`
- **Yapılan:** `if new_status == UserStatus.PASSIVE` → `if new_status in (PASSIVE, BANNED, DELETED)`; tüm pasifleştirme ve yasaklama durumlarında token_version artırılıyor ve fcm_token temizleniyor

---

### SRE-164 · 🟠 P1 (Yüksek) · `ProInsightsUseCase` İçinde `auctions` ve `bids` Tablolarının Çarpımsal Join Edilmesi Nedeniyle Şişirilmiş `bid_count` Raporlanması (Multiplied Cartesian Metric Skew in Stream Analytics)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/use_cases/analytics/pro_insights_use_case.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/analytics/pro_insights_use_case.py#L168-L180) (satırlar 168–180)

```sql
-- pro_insights_use_case.py satır 168–178:
SELECT ls.title, ls.viewer_count,
       ROUND(EXTRACT(EPOCH FROM (ls.ended_at - ls.started_at))/60) AS dur_min,
       COUNT(b.id) AS bid_count
FROM live_streams ls
LEFT JOIN auctions a ON a.stream_id = ls.id
LEFT JOIN bids b ON b.stream_id = a.stream_id
WHERE ls.host_id = :uid AND ls.is_live = false AND ls.ended_at IS NOT NULL
GROUP BY ls.id, ls.title, ls.viewer_count, ls.started_at, ls.ended_at
ORDER BY ls.viewer_count DESC, bid_count DESC
LIMIT 3
```

1. **Bire-Çok İlişkilerde Çarpımsal Join Yanılgısı (Cartesian Explosion):**
   - Bir canlı yayında birden fazla açık artırma (`auctions`) yapılabilir.
   - Teklifler tablosu (`bids`) doğrudan `stream_id` üzerinden yayına bağlıdır (`b.stream_id = a.stream_id`).
   - Bir yayında 4 açık artırma yapılmış ve toplam 25 teklif verilmişse; her `auction` satırı 25 `bid` satırıyla eşleşir. Join sonucu satır sayısı `4 × 25 = 100` olur.
   - Sorguda `COUNT(b.id)` kullanıldığı için, gerçekte 25 teklif almış yayın Pro satıcıya **100 teklif almış** gibi 4 kat şişirilmiş olarak gösterilir. Satıcı yanlış etkileşim verisiyle yanıltılır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/use_cases/analytics/pro_insights_use_case.py:171`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/analytics/pro_insights_use_case.py#L171) içindeki sayacı `COUNT(DISTINCT b.id)` olarak güncelleyin veya doğrudan `bids` tablosu üzerinden alt sorgu ile bağlayın:
```python
SELECT ls.title, ls.viewer_count,
       ROUND(EXTRACT(EPOCH FROM (ls.ended_at - ls.started_at))/60) AS dur_min,
       COUNT(DISTINCT b.id) AS bid_count
FROM live_streams ls
LEFT JOIN bids b ON b.stream_id = ls.id
WHERE ls.host_id = :uid AND ls.is_live = false AND ls.ended_at IS NOT NULL
GROUP BY ls.id, ls.title, ls.viewer_count, ls.started_at, ls.ended_at
ORDER BY ls.viewer_count DESC, bid_count DESC
LIMIT 3
```

#### ✅ Çözüm Damgası
- **Commit:** `d11dde92` — `fix(sre-164): pro_insights best_streams bid_count kartezyen çarpım giderildi`
- **Tarih:** 2026-10-30
- **Değişen Dosya:** `backend/app/use_cases/analytics/pro_insights_use_case.py`
- **Yapılan:** `LEFT JOIN auctions a` + `LEFT JOIN bids b ON b.stream_id = a.stream_id` → `LEFT JOIN bids b ON b.stream_id = ls.id`; `COUNT(b.id)` → `COUNT(DISTINCT b.id)`

---

### SRE-165 · 🟡 P2 (Orta) · `seed_interests` Endpoint'inde `NULL` Subcategory Nedeniyle PostgreSQL Unique Constraint İhlali ve Mükerrer Kategori Kaydı Şişmesi (Duplicate Category Insertion & Recommendation Bias via Nullable Subcategory)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/onboarding.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/onboarding.py#L50-L68) (satırlar 50–68)
  * [`backend/app/models/user_interest.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/models/user_interest.py#L11-L15) (satırlar 11–15)

```python
# onboarding.py satır 50–62:
    stmt = (
        pg_insert(UserInterest)
        .values([
            {
                "user_id": current_user.id,
                "category": cat,
                "score": _ONBOARDING_SCORE,
                "raw_signals": {"raw_total": _ONBOARDING_SCORE, "source": "onboarding"},
            }
            for cat in payload.categories
        ])
        .on_conflict_do_nothing(constraint="uq_user_interest")
    )
```

1. **SQL NULL Değerlerin Unique Kısıtını Bypass Etmesi:**
   - `UserInterest` modelinde `UniqueConstraint("user_id", "category", "subcategory", name="uq_user_interest")` kısıtı tanımlıdır.
   - `onboarding.py` içinde `subcategory` alanı belirtilmediği için SQL seviyesinde `NULL` olarak yazılır.
   - ANSI SQL ve PostgreSQL standartlarına göre (`NULLS NOT DISTINCT` belirtilmedikçe), iki `NULL` değeri birbirine eşit kabul edilmez (`NULL != NULL`).
   - Bu nedenle `on_conflict_do_nothing(constraint="uq_user_interest")` kısıtı tetiklenmez. Bir kullanıcı onboarding ekranından tekrar geçtiğinde veya endpoint mükerrer çağrıldığında, aynı kullanıcı ve aynı kategori için veritabanında onlarca mükerrer `UserInterest` kaydı oluşur.
   - Öneri algoritması (`recommendation_service.py`) ilgi alanlarını toplarken aynı kategoriyi defalarca sayarak kullanıcının ilgi puanını haksız yere şişirir ve kişiselleştirilmiş feed algoritmasını bozar.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/onboarding.py:53-61`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/onboarding.py#L53-L61) içine `subcategory=""` (boş string) veya `subcategory="all"` default değerini ekleyin ve `uq_user_interest` kısıtına `COALESCE` veya `NULLS NOT DISTINCT` desteği kazandırın:
```python
        pg_insert(UserInterest)
        .values([
            {
                "user_id": current_user.id,
                "category": cat,
                "subcategory": "",  # NULL yerine deterministik boş string
                "score": _ONBOARDING_SCORE,
                "raw_signals": {"raw_total": _ONBOARDING_SCORE, "source": "onboarding"},
            }
            for cat in payload.categories
        ])
        .on_conflict_do_nothing(constraint="uq_user_interest")
```

---

### SRE-166 · 🟡 P2 (Orta) · `train_bpr` İçinde Hard Negative Örneklemesinde 200 Milyonluk Kartezyen Döngü ve Negatif Ağırlıkların Matris Dışında Kalması (Cartesian Memory Exhaustion & Discarded Hard Negatives in BPR Training)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/services/ml/bpr_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/bpr_service.py#L180-L191) (satırlar 180–191, 205–211)

```python
# bpr_service.py satır 180–189:
    hard_neg_interactions: list[tuple[int, int, str, int]] = []
    for iid, (cat, subcat) in item_cat_subcat.items():
        for uid in user_pos_cats:
            if cat in user_pos_cats[uid]:
                key = f"{cat}|{subcat}"
                if key not in user_pos_subcats[uid]:
                    hard_neg_interactions.append((uid, iid, "_hard_neg", 1))
    if hard_neg_interactions:
        interactions = list(interactions) + hard_neg_interactions
        _WEIGHTS["_hard_neg"] = -0.05  # negatif ağırlık

# bpr_service.py satır 205–210:
    for user_id, item_id, event_type, cnt in interactions:
        w = _WEIGHTS.get(event_type, 0.0)
        if w > 0:  # <--- DİKKAT: -0.05 elenir!
            row_idx.append(user2idx[user_id])
            col_idx.append(item2idx[item_id])
            weights.append(w * float(cnt))
```

1. **O(N_items × N_users) Kartezyen Bellek Patlaması:**
   - 20.000 ilan ve 10.000 aktif kullanıcının bulunduğu bir senaryoda, iç içe `for` döngüsü tam **200.000.000 (200 Milyon)** kez döner.
   - Milyonlarca tuple `hard_neg_interactions` listesine `append` edilir ve Python heap belleğinde anında 8–16 GB RAM tüketerek Linux Kernel OOM Killer'ı (`SIGKILL 9`) tetikler.
2. **Negatif Ağırlıkların Sessizce Çöpe Atılması:**
   - Milyonlarca iterasyonla RAM şişirildikten sonra, CSR matrisi oluşturulurken satır 207'de `if w > 0:` kontrolü yapılır.
   - `_WEIGHTS["_hard_neg"] = -0.05` olduğu için, üretilen yüz binlerce hard negative kaydının **tamamı** elenir ve matrise tek bir tanesi bile eklenmez!
   - Süreç hem sunucuyu dakikalarca kilitleyip OOM riski yaratır, hem de üretilen devasa veri hiçbir işe yaramadan atılır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/services/ml/bpr_service.py:180-191`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/bpr_service.py#L180-L191) bloğunu kaldırın veya kullanıcı başına rastgele sınırlandırılmış (max 5 adet) hard negative örneklemesi uygulayarak BPR kayıp fonksiyonuna uygun pozitif/negatif çiftler halinde implicit kütüphanesine iletin.

---

### SRE-167 · 🔴 P0 (Kritik) · `apply_referral` İçinde Eksik `_get_t` Import'u Nedeniyle E-posta/Telefon Onayı ve Referans Kodu Kullanımında HTTP 500 Çökmesi ve Bakiye Güncellemesinde Redis Oturum Önbelleğinin Geçersiz Kılınmaması (Missing `_get_t` Import & Stale User Session Cache in Referral Reward Engine)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/services/referral_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/referral_service.py#L74-L180) (satırlar 74, 122–146, 156, 172)
  * [`backend/app/routers/auth.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/auth.py#L158-L162) (satırlar 158, 1389)
  * [`backend/app/routers/users.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/users.py#L94-L96) (satır 94)

```python
# referral_service.py satır 73–75:
    from app.services.firebase_service import send_push
    t = _get_t(lang)  # <--- HATA: _get_t bu modülde hiç import edilmemiştir!

# referral_service.py satır 153–164:
    if referrer.fcm_token:
        try:
            import asyncio
            t_ref = _get_t(referrer.locale or "tr")  # <--- HATA: NameError!
            asyncio.create_task(
                send_push(...)
            )
...
# referral_service.py satır 169–179:
    if current_user.fcm_token:
        try:
            import asyncio
            t_cur = _get_t(current_user.locale or "tr")  # <--- HATA: NameError!
            asyncio.create_task(
                send_push(...)
            )
```

1. **Eksik `_get_t` Nedeniyle Kayıt ve Doğrulama Felci:**
   - `referral_service.py` dosyasında `t = _get_t(lang)`, `_get_t(referrer.locale)` ve `_get_t(current_user.locale)` çağrıları yer almaktadır. Ancak modülün başında veya fonksiyon içinde `from app.utils.i18n import _get_t` import'u unutulmuştur.
   - Kullanıcı doğrudan `POST /api/users/referral/apply` endpoint'ine davet kodu gönderdiğinde veya yeni kaydolan bir kullanıcı e-posta doğrulamasını (`auth.py:158`) ya da SMS telefon doğrulamasını (`auth.py:1389`) tamamladığında, bekleyen referans kodunu işlemek üzere `await apply_referral(db, user, user.pending_referred_by)` çağrılır.
   - Python anında `NameError: name '_get_t' is not defined` hatası fırlatır ve istemciye HTTP 500 Internal Server Error döner.
   - Sonuç olarak, davet kodu ile kaydolan hiçbir kullanıcı e-posta ya da telefon doğrulama adımını başarıyla tamamlayamaz; doğrulama süreci tamamen kilitlenir.
2. **Doğrudan SQL Güncellemesi ve Redis Oturum Önbelleği Tutarsızlığı:**
   - Satır 123–143 arasında hem davet eden kullanıcıya (+50 TEQlik) hem de davet edilen yeni kullanıcıya (+50 TEQlik) doğrudan `UPDATE users SET teqlik_balance = teqlik_balance + :amt WHERE id = :uid` SQL ifadesi ile bakiye tanımlanır.
   - Ancak işlem sonrasında `invalidate_user_session_cache(referrer.id)` ve `invalidate_user_session_cache(current_user.id)` çağrılmamaktadır.
   - `get_current_user` bağımlılığı kullanıcının profil ve bakiye verilerini Redis'te 15 dakika (900 saniye) boyunca önbelleğe aldığı için (`session:user:{id}`), her iki kullanıcının da mobil arayüzünde cüzdan bakiyesi 15 dakika boyunca eski kalır; kullanıcılar kazanılan ödülün yatmadığını düşünerek mükerrer destek talepleri oluşturur.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/services/referral_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/referral_service.py#L9-L20) modül başına `from app.utils.i18n import _get_t` ekleyin ve bakiye artırımı sonrasında her iki kullanıcının Redis oturum önbelleğini geçersiz kılın:
```python
from app.utils.i18n import _get_t
from app.core.read_cache import invalidate_user_session_cache

# ... bakiye güncellemesi ve commit sonrası:
await db.commit()
await db.refresh(current_user)

# Redis session önbelleklerini derhal temizle
try:
    await invalidate_user_session_cache(referrer.id)
    await invalidate_user_session_cache(current_user.id)
except Exception as _ce:
    logger.warning("[REFERRAL] Session cache invalidate failed: %s", _ce)
```

---

### SRE-168 · 🔴 P0 (Kritik) · `check_listing_nsfw` İçinde Eksik `ListingStatus` ve Yanlış `push_notification` Import'u Nedeniyle Müstehcen İçeriklerin Otomatik Askıya Alınamaması ve Sansürsüz Yayında Kalması (Missing `ListingStatus` Import in NudeNet Worker & Failure to Auto-Suspend Explicit Content)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/services/ml/nsfw_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/nsfw_service.py#L165-L202) (satırlar 170, 187)

```python
# nsfw_service.py satır 165–174:
        updates: dict = {
            "nsfw_score": max_score,
            "nsfw_checked_at": datetime.now(timezone.utc),
        }
        if max_score >= _NSFW_AUTO_DEACTIVATE:
            updates["status"] = ListingStatus.SUSPENDED.value  # <--- HATA: ListingStatus hiç import edilmemiştir!
            logger.warning(
                "[NSFW] İlan otomatik pasife alındı | listing_id=%d score=%.3f",
                listing_id, max_score,
            )

# nsfw_service.py satır 185–188:
    if max_score >= _NSFW_AUTO_DEACTIVATE:
        try:
            from app.routers.notifications import push_notification  # <--- HATA: Servis katmanı router'a bağımlı kılınmış!
```

1. **`NameError: name 'ListingStatus' is not defined` Nedeniyle Sansürün Devre Dışı Kalması:**
   - NudeNet görsel analiz motoru ilanın fotoğraflarını tarayıp `max_score >= 0.85` (ağır müstehcenlik, açık cinsel organ / pornografik içerik) tespit ettiğinde, satır 170'te ilanı derhal askıya almak üzere `updates["status"] = ListingStatus.SUSPENDED.value` ataması yapılır.
   - Ancak `nsfw_service.py` dosyasında `ListingStatus` hiçbir şekilde import edilmemiştir (`from app.models.enums import ListingStatus` eksiktir).
   - Kod satır 170'e ulaştığı anda Python çalışma zamanı `NameError: name 'ListingStatus' is not defined` hatasıyla çöker. Hata nedeniyle `await db.execute(sa_update(Listing)...)` ve `await db.commit()` satırlarına asla ulaşılamaz.
   - **Kritik Güvenlik ve Mağaza Riski:** Müstehcen ve pornografik içerik taşıyan ilanlar sistem tarafından **askıya alınamaz**, ilan `active` statüsünde kalarak teqlif ana sayfasında, arama sonuçlarında ve keşfet akışında sansürsüz olarak tüm kullanıcılara sergilenmeye devam eder. Bu durum Apple App Store ve Google Play Store "User-Generated Content" (UGC) kurallarının ihlaline ve uygulamanın mağazalardan derhal kaldırılmasına (ban) yol açar.
2. **Ters Mimari Bağımlılık (Router Katmanından Fonksiyon İçe Aktarımı):**
   - Satır 187'de `push_notification` fonksiyonu `from app.routers.notifications import push_notification` şeklinde içe aktarılmıştır. Oysa `push_notification` doğrudan `app.services.notification_service` içinde tanımlıdır. Servis katmanının router katmanına bağımlı hale getirilmesi döngüsel içe aktarım (circular import) ve test izolasyonu sorunları yaratır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/services/ml/nsfw_service.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/services/ml/nsfw_service.py#L12-L21) başına `from app.models.enums import ListingStatus` ve doğru `notification_service` import'unu ekleyin:
```python
from app.models.enums import ListingStatus
from app.services.notification_service import push_notification

# satır 170 güvenle ListingStatus.SUSPENDED.value değerini kullanır
# satır 187'deki lokal hatalı router import'u kaldırılır
```

---

### SRE-169 · 🟠 P1 (Yüksek) · `routers/analytics.py` Pro Analitik Endpoint'lerinde Eksik `_dt` ve `_td` Import'u Nedeniyle Tarih Filtreli İsteklerde HTTP 500 Çökmesi (Missing Global Scope `datetime` Aliases in Pro Analytics Endpoints)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/routers/analytics.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/analytics.py#L1230-L1465) (satırlar 725, 1237–1238, 1356–1357, 1457–1458)

```python
# analytics.py satır 724–726 (daily_metrics içi - LOKAL SCOPE):
@router.get("/daily-metrics")
async def daily_metrics(...):
    from datetime import datetime as _dt, timedelta as _td
    ...

# analytics.py satır 1237–1238 (video_roi içi - GLOBAL ÇAĞRI):
@router.get("/video-roi")
async def video_roi(start_date: Optional[str] = None, end_date: Optional[str] = None, ...):
    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None  # <--- HATA: _dt global scope'ta yok!
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None

# analytics.py satır 1356–1357 (gallery_stats içi - GLOBAL ÇAĞRI):
@router.get("/gallery-stats")
async def gallery_stats(start_date: Optional[str] = None, end_date: Optional[str] = None, ...):
    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None  # <--- HATA: NameError!
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None

# analytics.py satır 1457–1458 (video_perf içi - GLOBAL ÇAĞRI):
@router.get("/video-perf")
async def video_perf(start_date: Optional[str] = None, end_date: Optional[str] = None, ...):
    _sd = _dt.strptime(start_date, '%Y-%m-%d') if start_date else None  # <--- HATA: NameError!
    _ed = (_dt.strptime(end_date, '%Y-%m-%d') + _td(days=1)) if end_date else None
```

1. **Lokal Scope Import'unun Global Zannedilerek Çağrılması:**
   - `analytics.py` dosyasında `_dt` ve `_td` takma adları yalnızca satır 725'te `daily_metrics` fonksiyonunun yerel kapsamı içerisinde import edilmiştir.
   - Ancak daha sonra geliştirilen Pro satıcı analitik endpoint'leri `video_roi` (satır 1237), `gallery_stats` (satır 1356) ve `video_perf` (satır 1457) içinde, `_dt.strptime(...)` ve `_td(days=1)` ifadeleri sanki modül düzeyinde import edilmiş gibi doğrudan kullanılmıştır.
   - Bir Pro satıcı analitik paneline girdiğinde ve tarih aralığı filtresi (`start_date` veya `end_date`) seçtiğinde, Python çalışma zamanı `NameError: name '_dt' is not defined` hatası fırlatarak isteği anında HTTP 500 ile sonlandırır.
2. **Pro Satıcı Güven ve Gelir Kaybı:**
   - Pro paket satın alan kurumsal ve bireysel satıcılar, video ilanlarının yatırım getirisini (ROI), galeri fotoğraflarının tıklama oranlarını ve video performans metriklerini tarih bazında raporlayamaz. Satıcı paneli grafiklerinin patlaması müşteri şikayetlerine ve abonelik iptallerine (churn) yol açar.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/analytics.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/analytics.py#L1-L25) dosyasının en başına modül seviyesinde `from datetime import datetime as _dt, timedelta as _td` ekleyin:
```python
from datetime import datetime, timezone, timedelta
from datetime import datetime as _dt, timedelta as _td
```
ve fonksiyon içlerindeki dağınık yerel import'ları kaldırarak tüm tarih ayrıştırma mantığını modül seviyesindeki standart alias'lar üzerinden yürütün.

> ✅ **Çözüldü** — commit `41cc28ab`, 2026-10-30

---

### SRE-170 · 🟠 P1 (Yüksek) · `worker.py:cleanup_ghost_calls_task` İçinde Eksik `ws_manager` Import'u Nedeniyle Hayalet Arama WebSocket Bildirimlerinin Düşmesi ve Kullanıcıların Arama Ekranında Kilitli Kalması (Missing `ws_manager` Import in Ghost Call Cleanup Task & Stalled Client Call Screens)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/worker.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L2465-L2496) (satırlar 2467, 2468, 2470, 2490, 2491, 2493)

```python
# worker.py satır 2465–2472:
                    # FIX: WS bildirimi — kullanıcılar ekranda takılı kalmasın
                    try:
                        await ws_manager.publish("dm_broadcast", f"dm:{call.caller_id}", {"type": "call_missed", "call_id": call.id})  # <--- HATA: ws_manager tanımsız!
                        await ws_manager.publish("dm_broadcast", f"dm:{call.callee_id}", {"type": "call_missed", "call_id": call.id})
                        logger.info("[CALL_PROCESS][GHOST] WS call_missed sent | caller=%d callee=%d call_id=%d", call.caller_id, call.callee_id, call.id)
                    except Exception as ws_err:
                        logger.warning("Ghost call WS notify failed for %d: %s", call.id, ws_err)  # <--- HATA SESSİZCE YUTULUR!

# worker.py satır 2488–2495:
                        # FIX: WS bildirimi
                        try:
                            await ws_manager.publish("dm_broadcast", f"dm:{call.caller_id}", {"type": "call_ended", "call_id": call.id})  # <--- HATA: ws_manager tanımsız!
                            await ws_manager.publish("dm_broadcast", f"dm:{call.callee_id}", {"type": "call_ended", "call_id": call.id})
                            logger.info("[CALL_PROCESS][GHOST] WS call_ended sent | caller=%d callee=%d call_id=%d", call.caller_id, call.callee_id, call.id)
                        except Exception as ws_err:
                            logger.warning("Ghost call WS notify failed for %d: %s", call.id, ws_err)
```

1. **`NameError` İstisnasının Sessizce Yutulması:**
   - `worker.py` dosyasında periyodik olarak çalışan `cleanup_ghost_calls_task` arka plan görevi, süresi dolmuş çalan aramaları (`ringing`) `missed` statüsüne; LiveKit odası bulunmayan aktif aramaları (`active`) ise `ended` statüsüne alır.
   - Kullanıcıların mobil ekranlarında aramanın sonlandığını anlaması ve zil sesinin / arama modalının kapanması için satır 2467, 2468, 2490 ve 2491'de `ws_manager.publish("dm_broadcast", ...)` çağrısı yapılır.
   - Ancak `ws_manager`, `cleanup_ghost_calls_task` fonksiyonunda import edilmemiştir (yalnızca satır 2298'de başka bir fonksiyon içinde lokal tanımlanmıştır).
   - `await ws_manager.publish(...)` satırı anında `NameError: name 'ws_manager' is not defined` hatası üretir. Satır 2470 ve 2493'teki `except Exception as ws_err:` bloğu hatayı `Ghost call WS notify failed for ...: name 'ws_manager' is not defined` şeklinde warning seviyesinde loglayıp sessizce yutar.
2. **Mobil İstemcilerin Arama Ekranında Kilitli Kalması (Stalled Call Screen):**
   - Veritabanında arama sonlandırılmış olmasına rağmen, WebSocket sinyali hiçbir zaman istemcilere ulaşamaz.
   - Arayan ve aranan kullanıcıların telefonlarında "Çalıyor..." veya "Bağlanıyor..." ekranı takılı kalır, zil sesi çalmaya devam eder ve kullanıcı uygulamayı işletim sistemi seviyesinde zorla kapatıp (force quit) yeniden başlatmak zorunda kalır.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/worker.py:2420-2430`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L2420-L2430) içine, `cleanup_ghost_calls_task` fonksiyonunun başına `from app.core.ws_manager import ws_manager` import'unu ekleyin:
```python
async def cleanup_ghost_calls_task(ctx: dict):
    from app.core.ws_manager import ws_manager  # Eksik import eklendi
    from app.database import AsyncSessionLocal
    # ...
```

> ✅ **Çözüldü** — commit `c5fd0c32`, 2026-10-30

---

### SRE-171 · 🔴 P0 (Kritik) · `flush_interactions_to_db` Arka Plan Görevinde Redis `LTRIM` Komutunun Okunan Eleman Sayısı (`len(raw_items)`) Yerine Sabit `BATCH_LIMIT` (2000) ile Çağrılması Nedeniyle Eşzamanlı Gelen Tüm Kullanıcı Etkileşimlerinin ve Sinyallerinin Kalıcı Olarak Silinmesi (Silent Data Loss via Hardcoded BATCH_LIMIT in Redis LTRIM)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/worker.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L795-L865) (satırlar 795–805, 851–857)

```python
# worker.py satır 795–805:
    QUEUE_KEY = "interaction_queue"
    BATCH_LIMIT = 2000

    try:
        redis = await get_redis()
        raw_items: list[str] = await redis.lrange(QUEUE_KEY, 0, BATCH_LIMIT - 1)
        if not raw_items:
            return
...
# worker.py satır 851–857:
        async with AsyncSessionLocal() as db:
            await db.execute(sa_insert(UserInteraction), pg_rows)
            await db.commit()

        # PG commit başarılı — artık Redis kuyruğundan o batch'i kaldırabiliriz:
        await redis.ltrim(QUEUE_KEY, BATCH_LIMIT, -1)  # <--- KRİTİK VERİ KAYBI!
```

1. **Redis `LTRIM` Spesifikasyonu ve Liste Sıfırlama Mekanizması:**
   - Redis standart dokümantasyonuna göre `LTRIM key start stop` komutunda, şayet `start` parametresi listenin mevcut uzunluğundan büyükse (`start >= len(list)`), komut listenin tüm elemanlarını temizler (liste sıfırlanır / boş liste üretir).
   - Normal operasyon koşullarında, 5 dakikalık periyotta `interaction_queue` listesinde biriken eleman sayısı genellikle 2000'in altındadır (örneğin 100, 250 veya 500 adet).
   - `flush_interactions_to_db` çalıştığında satır 803'te `lrange(0, 1999)` ile mevcut tüm elemanlar (örneğin 150 adet) okunur.
2. **PostgreSQL Transaction Süresince Gelen Verilerin Yok Edilmesi:**
   - 150 adet satır PostgreSQL'e bulk insert edilirken ve commit beklenirken (ortalama 50–200ms süren I/O işlemi), mobil ve web istemcilerinden yeni implicit etkileşimler (`rpush interaction_queue ...`) akmaya devam eder (örneğin kuyruğa 30 yeni kayıt eklenir, liste boyutu 180'e ulaşır).
   - Veritabanı commit'i tamamlandığında satır 856'da `await redis.ltrim(QUEUE_KEY, BATCH_LIMIT, -1)` çalıştırılır. `BATCH_LIMIT = 2000` sabit olduğu için Redis'e `LTRIM interaction_queue 2000 -1` emri gider.
   - Kuyruktaki eleman sayısı 180 olduğu ve `2000 > 180` şartı sağlandığı için, Redis kuyruktaki **tüm elemanları anında siler ve kuyruğu tamamen boşaltır**!
   - Veritabanı işlemi sürerken gelen 30 yeni etkileşim (indeks 150–179) PostgreSQL'e hiç yazılmadan **sessizce ve kalıcı olarak çöpe atılır**.
3. **Makine Öğrenmesi Modelleri ve Analitik Sakatlanması:**
   - Bu zaaf nedeniyle platformdaki kullanıcıların tıklama, izleme süresi (dwell), video atlama (skip) ve teklif verme tereddüt (hesitation) sinyalleri her 5 dakikada bir sistematik olarak kaybedilir.
   - `update_user_preference_embedding` görevleri eksik veriyle çalışır, Thompson Sampling algoritması ve ALS/BPR matris faktörizasyon modelleri kullanıcıların gerçek ilgi alanlarını yansıtamaz.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/worker.py:855-857`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/worker.py#L855-L857) satırındaki sabit `BATCH_LIMIT` parametresini, gerçekten okunan eleman sayısı olan `len(raw_items)` ile değiştirin:
```python
        # PG commit başarılı — yalnızca DB'ye başarıyla yazılan elemanları trim et
        await redis.ltrim(QUEUE_KEY, len(raw_items), -1)
```

> ✅ **Çözüldü** — commit `96411c73`, 2026-10-30

---

### SRE-172 · 🔴 P0 (Kritik) · Canlı Yayın Düğüm Arızasında (`failover_stream`) Yeni Odaya Taşınan Yayının İzleyicilere WebSocket veya Redis Üzerinden Bildirilmemesi ve Tüm İzleyicilerin Ölü Düğümde Kilitli Kalması (Silent Stream Failover Desync & Orphaned Viewers on Node Crash)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/use_cases/streams/commands/failover_stream.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/streams/commands/failover_stream.py#L40-L75) (satırlar 40–75)
  * [`backend/app/routers/streams.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/streams.py#L255-L265) (satırlar 255–264)

```python
# failover_stream.py satır 52–65:
            base_room = _base_room(stream.room_name)
            part_number = _next_part_number(stream.room_name)
            new_room = f"{base_room}{_PART_SEPARATOR}{part_number}"

            stream.room_name = new_room
            stream.livekit_url = node["livekit_url"]
            stream.source_node_id = node.get("node_id")
            await self.uow.session.commit()

        # room_to_stream mapping güncelle
        try:
            redis = await get_redis()
            await redis.set(f"live:room_to_stream:{new_room}", f"{stream_id}:{host_id}", ex=48 * 3600)
        except Exception as exc:
            logger.warning("[Failover] room_to_stream mapping güncellenemedi: %s", exc)
```

1. **İzleyici Koordinasyonunun ve Sinyalizasyonunun Bulunmaması:**
   - Kural 3 uyarınca, canlı yayın sunucusu çöktüğünde veya yayıncı `NODE_UNAVAILABLE` hatası aldığında mobil istemci `POST /api/streams/{stream_id}/failover` endpoint'ini çağırır.
   - `FailoverStreamCommand` yeni bir edge media node tahsis eder, oda adını `_p2` suffix'i ile günceller ve yayıncıya yeni LiveKit bağlantı token'ı döner.
   - Ancak yayını izlemekte olan yüzlerce izleyiciye yönelik hiçbir sinyalizasyon adımı bulunmamaktadır:
     - Ne Redis Pub/Sub üzerinden chat/yayın kanalına `room_failover` bildirimi basılmaktadır.
     - Ne de `stream:meta:{stream_id}` Redis anahtarı güncellenmektedir.
2. **Split-Brain İzleyici İzolasyonu ve 0 İzleyicili Yayın:**
   - Çöken sunucuya bağlı olan tüm izleyiciler donmuş video ekranında ve sessiz WebSocket bağlantısında takılı kalır.
   - Canlı yayına yeni girmek isteyen kullanıcılar eski `stream:meta` verisi yüzünden çöken sunucuya yönlendirilir ve bağlantı hatası alır.
   - Yayıncı yeni sunucuda tek başına konuşurken tüm izleyici kitlesi kopar; açık artırma teklifleri ve canlı hediyeler durur, yayıncı ve platform doğrudan ciro kaybına uğrar.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/use_cases/streams/commands/failover_stream.py:60-70`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/streams/commands/failover_stream.py#L60-L70) içine `stream:meta` güncellemesini ve eski odanın izleyicilerine yeni LiveKit URL ve oda bilgisini taşıyan WebSocket failover broadcast'ini ekleyin:
```python
        # 1. room_to_stream ve stream:meta güncelle
        try:
            redis = await get_redis()
            pipe = redis.pipeline()
            pipe.set(f"live:room_to_stream:{new_room}", f"{stream_id}:{host_id}", ex=48 * 3600)
            pipe.hset(f"stream:meta:{stream_id}", mapping={
                "room_name": new_room,
                "livekit_url": node["livekit_url"],
                "source_node_id": node.get("node_id", ""),
            })
            # 2. İzleyicileri yeni odaya yönlendirmek için Redis Pub/Sub sinyali gönder
            failover_msg = json.dumps({
                "type": "stream_failover",
                "stream_id": stream_id,
                "new_room_name": new_room,
                "new_livekit_url": node["livekit_url"],
            })
            pipe.publish(f"chat:{stream_id}", failover_msg)
            await pipe.execute()
        except Exception as exc:
            logger.warning("[Failover] Redis metadata ve broadcast güncellenemedi: %s", exc)
```

> ✅ **Çözüldü** — commit `603776be`, 2026-10-30

---

### SRE-173 · 🟠 P1 (Yüksek) · Kazanç Bakiyesini TEQlik'e Dönüştürmede (`convert-to-teqlik`) Redis Oturum Önbelleğinin Geçersiz Kılınmaması Nedeniyle Bakiye Tutarsızlığı ve Hatalı Yetersiz Bakiye Reddi (Stale Session Cache on Earnings-to-Teqlik Conversion)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/use_cases/wallet/commands/convert_to_teqlik_command.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/wallet/commands/convert_to_teqlik_command.py#L40-L100) (satırlar 40–100)
  * [`backend/app/routers/wallet.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/wallet.py#L143-L156) (satırlar 143–156)

```python
# wallet.py satır 143–155:
@router.post("/convert-to-teqlik")
async def convert_to_teqlik(
    body: ConvertToTeqlikRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    from app.use_cases.wallet.commands.convert_to_teqlik_command import ConvertToTeqlikCommand
    result = await ConvertToTeqlikCommand(db).execute(
        user_id=current_user.id,
        teqlik_amount=body.teqlik_amount,
    )
    await db.commit()
    return result  # <--- HATA: invalidate_user_session_cache çağrılmaz!
```

1. **Redis Oturum Önbelleği (`session:user:{id}`) Desenkronizasyonu:**
   - Yayıncı kazandığı bakiyeyi +%10 bonus avantajıyla TEQlik'e dönüştürdüğünde (`POST /api/wallet/convert-to-teqlik`), `ConvertToTeqlikCommand` veritabanında `user_wallet_earnings.available` tutarını düşer, `users.teqlik_balance` tutarını artırır ve `wallet_ledger` kayıtlarını atomik olarak yazar.
   - Ancak işlem tamamlandığında `invalidate_user_session_cache(current_user.id)` çağrılmamaktadır.
2. **Kullanıcı İşlemlerinde Yetersiz Bakiye Anomalisi:**
   - `get_current_user` kimlik doğrulama bağımlılığı kullanıcının profil ve bakiye nesnesini Redis'te 15 dakika (900 saniye) boyunca önbelleğe almaktadır.
   - Mobil arayüzde dönüştürme endpoint'inin yanıtı üzerinden bakiye güncel gözükürken, kullanıcının bir sonraki reklam verme (`create_campaign`), hediye gönderme (`send_gift`) veya öne çıkarma (`boost`) isteklerinde `get_current_user` Redis'teki eski bakiyeyi okur.
   - Kullanıcı dönüştürdüğü TEQlik bakiyesini 15 dakika boyunca harcayamaz, sistem `INSUFFICIENT_FUNDS` hatası verir ve kullanıcı parasının kaybolduğunu düşünerek destek talepleri oluşturur.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/routers/wallet.py:153-156`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/wallet.py#L153-L156) içine `invalidate_user_session_cache` çağrısını ekleyin:
```python
    await db.commit()
    from app.utils.auth import invalidate_user_session_cache
    try:
        await invalidate_user_session_cache(current_user.id)
    except Exception as _ce:
        logger.warning("[Wallet] Session cache invalidation failed: %s", _ce)
    return result
```

> ✅ **Çözüldü** — önceden uygulanmış (wallet.py:158), 2026-10-30

---

### SRE-174 · 🟠 P1 (Yüksek) · İlan Teklifi Verildiğinde Satıcıya Push ve WebSocket Bildirimi Gönderilmemesi Nedeniyle Tekliflerin Yanıtsız Kalması ve Satış Döngüsünün Kilitlenmesi (Missing Real-time & Push Notification on Listing Offer Creation)

#### 1. Zaafın Kök Nedeni ve Mekanizması
* **Etkilenen Dosyalar:**
  * [`backend/app/use_cases/listings/commands/create_offer.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/listings/commands/create_offer.py#L20-L60) (satırlar 20–60)
  * [`backend/app/routers/listings.py`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/routers/listings.py#L301-L309) (satırlar 301–309)

```python
# create_offer.py satır 47–59:
            offer = ListingOffer(
                listing_id=listing_id,
                user_id=current_user.id,
                amount=amount,
            )
            self.uow.session.add(offer)
            await self.uow.session.flush()  # offer.id atanır, commit __aexit__'te yapılır

        logger.info(
            "[CreateListingOfferCommand] Teklif verildi | listing_id=%s user_id=%s amount=%s",
            listing_id, current_user.id, amount,
        )
        return {"id": offer.id, "amount": offer.amount}  # <--- BİLDİRİM YOK!
```

1. **Sinyalizasyon ve Bildirim Eksikliği:**
   - Bir alıcı satıcının ilanına fiyat teklifi verdiğinde (`POST /api/listings/{listing_id}/offers`), `CreateListingOfferCommand` yalnızca veritabanındaki `listing_offers` tablosuna satır ekler.
   - İlan sahibi satıcıya in-app bildirim (`Notification`), Firebase FCM push bildirimi veya WebSocket anlık sinyali gönderilmez.
2. **Kör Satıcı Deneyimi ve Satış Tıkanması:**
   - İlan sahibi satıcı, ilanı için gelen tekliflerden tamamen habersizdir. Teklifleri görmek için her seferinde ilan detayına girip manuel olarak teklifler sekmesini yenilemek zorundadır.
   - Alıcılar tekliflerine saatlerce/günlerce yanıt alamayınca platformu terk eder; satıcılar ise ilanlarına talep gelmediğini düşünür. Platformun temel ticaret ve pazarlık döngüsü işlevsiz hale gelir.

#### 2. Çözüm / Refactoring Reçetesi
[`backend/app/use_cases/listings/commands/create_offer.py:48-59`](file:///Users/tucibeyin/Desktop/teqlif/backend/app/use_cases/listings/commands/create_offer.py#L48-L59) içine, işlem commit edildikten sonra satıcıya in-app bildirim oluşturulması, Firebase FCM push bildirimi ve WebSocket sinyali gönderilmesini entegre edin:
```python
        # Satıcıya bildirim gönder (commit sonrası)
        try:
            from app.services.notification_service import push_notification
            from app.core.ws_manager import ws_manager
            
            # 1. FCM Push & In-app DB notification
            await push_notification(
                user_id=listing.user_id,
                notif={
                    "type": "listing_offer_received",
                    "title": "Yeni Teklif Aldınız!",
                    "body": f"{current_user.username} ilanınıza {amount:,.0f} TL teklif verdi.",
                    "related_id": listing_id,
                    "listing_id": listing_id,
                    "extra_data": {"offer_id": str(offer.id), "amount": str(amount)},
                },
            )
            # 2. Canlı WS sinyali
            await ws_manager.publish(
                "dm_broadcast",
                f"dm:{listing.user_id}",
                {"type": "new_listing_offer", "listing_id": listing_id, "amount": amount, "buyer": current_user.username},
            )
        except Exception as _ne:
            logger.warning("[CreateListingOfferCommand] Bildirim gönderilemedi: %s", _ne)
```

> ✅ **Çözüldü** — commit `2ab7eb6c`, 2026-10-30

---

## 🎯 Master Eylem Planı (Uçtan Uca Sıralı Mühendislik Yol Haritası)

Tüm 174 zaafın mimari bağımlılıklarına ve etki büyüklüklerine göre eksiksiz çözüm planı:

### 🔴 Faz 1: Canlı Çökme, Mali İstismar ve Güvenlik Açıkları (P0 Öncelik — 49 Adım)
1. **Adım 1 (`SRE-72`):** `notifications.py` satır 9'a `from app.database import get_db, AsyncSessionLocal` ekle; tüm canlı bildirim WebSocket'lerinin `NameError` ile 1011 çökmesini derhal çöz.
2. **Adım 2 (`SRE-81`):** `request_withdrawal_command.py:103-108` içindeki hatalı `exchange_rates` SQL sorgusunu `ExchangeRates` modeline (`usd_try`, `eur_try`) uygun hale getir; USD ve EUR para çekimlerinin `UndefinedColumn` (HTTP 500) ile çökmesini derhal çöz.
3. **Adım 3 (`SRE-94`):** `cancel_withdrawal_request_command.py` ve `process_withdrawal_command.py` içine `with_for_update()` kilidi ve atomik `status == 'pending'` kontrolü ekle; çekim iptalinde çift iade (double refund) ve çekim-iptal yarışıyla bedava nakit istismarını engelle.
4. **Adım 4 (`SRE-99`):** `auth.py` ve `user.py` içinde tüm DateTime sütunlarını dinamik olarak deserialize et (`pro_expires_at` vb. string kalıp `TypeError` vermesini engelle); cüzdan işlemlerine `invalidate_user_session_cache` ekle.
5. **Adım 5 (`SRE-100`):** `listings.py:mass_notify_listing` içinde `GREATEST(0, ...)`'ı kaldırıp atomik bakiye kontrolü (`WHERE teqlik_balance >= :cost`) ekle; FCM gönderimini bakiye düşüm sonrasına al ve cache invalidation uygula.
6. **Adım 6 (`SRE-105`):** `like_service.py:add_stream_like` içindeki tekil Postgres `INSERT` ve `COMMIT` işlemlerini kaldır, kalpleri Redis `INCRBY` ile topla ve oda izleyicilerine saniyede 1 kez `stream_like_batch` WebSocket sinyali gönder; C10K çökmesini ve Postgres kilitlenmesini durdur.
7. **Adım 7 (`SRE-106`):** `leads.py:send_blast` içindeki 10.000 alıcılık senkron ORM tahsisini ve sıralı 200 iterasyonluk Firebase FCM HTTP döngüsünü ARQ arka plan kuyruğuna delege et; 60-120 saniyelik 504 Gateway Timeout ve worker blokajını engelle.
8. **Adım 8 (`SRE-107`):** `search_alerts.py:delete_alert` satır 103'teki hatalı `'passive'` string atamasını `SearchAlertStatus.DELETED` olarak düzelt; `DataError: invalid input value for enum` (HTTP 500) çökmesini ve silinemeyen zombi alarmları çöz.
9. **Adım 9 (`SRE-111`):** `storage_service.py:delete_object` ve `delete_object_dm` içindeki tekil node fallback'ini kaldırıp tüm edge storage node'larında paralel silme uygulayarak terabaytlarca medya yetim kalmasını engelle.
10. **Adım 10 (`SRE-112`):** `delete_conversation_command.py` içinde `RelationshipStateService.recompute_and_cache` çağrısını `async with self.uow:` içine alarak kapatılmış session üzerinde `IllegalStateChangeError` (500) çökmesini çöz.
11. **Adım 11 (`SRE-117`):** `apple_verifier.py:98`'de consumable ürünler için tekil `transactionId` ata; `verify_purchase_command.py`'da tekrarlayan paket alımlarının `IAP_ALREADY_PROCESSED` ile kilitlenmesini ve velocity expire uzatma hatasını çöz.
12. **Adım 12 (`SRE-118`):** `stream_concat_task.py` içinde yetkili MinIO edge node keşfi ekle, başarılı birleştirme sonrası part dosyalarını sil (`remove_object`) ve dinamik scale ile bozuk video transcode açığını engelle.
13. **Adım 13 (`SRE-119`):** `webhooks.py:_delayed_close_stream` içindeki rastgele `allocate_node` çağrısını kaldırıp odanın ait olduğu yetkili node'u DB'den oku; aktif canlı yayınların zorla kapatılmasını (split-brain termination) engelle.
14. **Adım 14 (`SRE-127`):** `analytics_processor.py:calculate_user_budgets` içindeki 50.000 sıralı tekil `UPDATE` döngüsünü kaldır; 500'lük chunk'lar halinde `UPDATE users ... FROM (VALUES ...)` set-based sorgusuna ve bağımsız kısa transaction'lara dönüştürerek DB kilitlenmesini ve PgBouncer starvation'ı çöz.
15. **Adım 15 (`SRE-128`):** `bid_validation_service.py:validate_troll_bid` içine doğrulanmış hesaplar dahil tüm kullanıcılar için geçerli mutlak tavan (hard ceiling) ve maksimum katlama (15x) kontrolü ekle; onaylı hesapların 1 milyar TL teklifle canlı yayın müzayedelerini sabote etmesini (troll bid) engelle.
16. **Adım 16 (`SRE-129`):** `bootstrap_node1.sh:install_postgresql` içine `postgresql-${PG_VERSION}-pgvector` paket kurulumunu ekle; `database.py:init_extensions` fonksiyonundaki sessiz hatayı (`pass`) kaldırarak `Vector(384)` ve AI embedding sorgularının 500 ile çökmesini engelle.
17. **Adım 17 (`SRE-130`):** `bootstrap_node5.sh` scriptinde `apply_secrets` tarama dizinlerine `/etc/redis` ekle veya staging Redis conf'unu `/project/teqlif/config/redis/` yoluna taşı; `<staging_redis_pass>` placeholder'ının değişmeden kalmasıyla Staging ortamının `WRONGPASS` ile çökmesini derhal çöz.
18. **Adım 18 (`SRE-131`):** `video_tasks.py:capture_hype_highlight` içindeki rastgele `allocate_node` çağrısını kaldırıp odanın ait olduğu yetkili media node'unu sorgula; üretilen 15 saniyelik highlight MP4 dosyalarını yerel disk yerine MinIO nesne depolamasına yükle ve CDN linkini DB'ye kaydet.
19. **Adım 19 (`SRE-139`):** `stream_concat_task.py:153-158` birleştirilmiş kaydı (`is_concat_result=True`) eklerken `available_at = NOW()` kolonunu ekle; `notify_new_recordings_task`'in kaydı atlamasını, `expires_at` değerinin NULL kalmasını ve yaşam döngüsünün kilitlenmesini engelle.
20. **Adım 20 (`SRE-140`):** `utils/i18n.py:_get_t` içindeki senkron `create_engine` ve senkron Redis bağlantılarını kaldır; bellek önbelleğini arka planda asenkron yenile veya `translations` tablosunu global engine ile thread pool'a delege et; connection pool sızıntısını ve Uvicorn 3 saniyelik donmasını çöz.
21. **Adım 21 (`SRE-141`):** `auth.py:request_phone_verification` içinde henüz onaylanmamış telefonu doğrudan `current_user.phone = data.phone` olarak DB'ye yazma mantığını kaldır; yeni numarayı yalnızca `phone_verify:{token}` Redis anahtarında tut ve `confirm_phone_verification` sırasında atomik commit yap; telefon rehin alma (Phone DoS) açığını kapat.
22. **Adım 22 (`SRE-147`):** `auth.py:refresh_token` ve `create_refresh_token` kayıtlarına `token_version` bilgisini ekle (`user.id:user.token_version`); `/refresh` anında kullanıcının mevcut DB versiyonuyla karşılaştırarak şifre sıfırlama veya oturum düşürme sonrası çalınan refresh token'ların kullanılmasını (Session Hijack Persistence) engelle.
23. **Adım 23 (`SRE-155`):** `storage_service.py` içine `get_object_bytes_dm` fonksiyonunu ekle ve `dm_archive_tasks.py:archive_old_dm_task` içindeki yanlış public bucket okumasını düzelt; `NoSuchKey` dışındaki ağ hatalarında exception yutmasını kaldırarak MinIO'daki geçmiş yılların tüm DM arşivlerinin kalıcı ezilmesini ve silinmesini engelle.
24. **Adım 24 (`SRE-156`):** `auth.py:init_context` ve `get_conversations_query.py` içindeki tekil `AsyncSession` üzerinde `asyncio.gather` ile eşzamanlı `execute()` çağrılarını sıralı `await` yürütmesine çevir; mobil açılışta ve mesaj kutusunda yaşanan `IllegalStateChangeError` (HTTP 500) çökmesini çöz.
25. **Adım 25 (`SRE-161`):** `auction_commands.py:accept_bid` ve `auction_redis_repo.py` içine atomik `lock_accept_bid` Lua script'i ekle; teklif kabul sürecinde Redis'in `accepting` durumuna alınmasını sağlayarak eşzamanlı yeni tekliflerle ihalenin gasbedilmesini ve çift kazanan anomalilerini engelle.
26. **Adım 26 (`SRE-162`):** `admin_data.py:purge_user` endpoint'ine `token_version` artırımı, `invalidate_user_session_cache` çağrısı, aktif ilanları pasife çekme ve aktif canlı yayını sonlandırma ekle; anonimize edilip silinen kullanıcının 15 dk boyunca JWT ve Redis oturumunu sürdürmesini engelle.
27. **Adım 27 (`SRE-167`):** `referral_service.py:74, 156, 172` içine `from app.utils.i18n import _get_t` import'unu ekle ve bakiye dağıtımında `invalidate_user_session_cache` çağır; referans kodu kullanımının ve onaylı kullanıcıların e-posta/telefon doğrulamasında `NameError: name '_get_t' is not defined` (HTTP 500) ile çökmesini ve cüzdan bakiyesinin Redis önbelleğinde 15 dk eski kalmasını çöz.
28. **Adım 28 (`SRE-168`):** `nsfw_service.py:170, 187` içine `from app.models.enums import ListingStatus` ve doğru `notification_service` import'unu ekle; NudeNet moderasyonunun `NameError: name 'ListingStatus' is not defined` ile çöküp müstehcen ve pornografik içerikli ilanların sansürsüz yayında kalmasını engelle.
29. **Adım 29 (`SRE-171`):** `worker.py:flush_interactions_to_db` satır 856'da `BATCH_LIMIT` yerine `len(raw_items)` kullan; veritabanı yazımı sürerken gelen tüm kullanıcı tıklama ve dwell etkileşimlerinin Redis'ten kalıcı silinmesini ve ML modellerinin bozulmasını engelle.
30. **Adım 30 (`SRE-172`):** `failover_stream.py` içine Redis `stream:meta` güncellemesini ve oda chat kanalına `stream_failover` WebSocket yayını ekle; çöken sunucudaki izleyicilerin ölü düğümde kilitli kalmasını ve yayının 0 izleyiciyle devam etmesini çöz.
31. **Adım 31 (`SRE-89`):** `calls.py:start_call` içindeki tek taraflı advisory lock'u `min(caller, callee), max(caller, callee)` sıralı çiftine dönüştür; simetrik arama çakışmasında (glare) çift LiveKit odası oluşmasını ve çoklu arama DoS açığını engelle.
32. **Adım 32 (`SRE-68`):** `auth.py:delete_account`, `admin_data.py:delete_user` ve `permanently_delete_user` içine `invalidate_user_session_cache(uid)` ve refresh token silme ekle; silinen kullanıcıların 15 dk zombi kalmasını engelle.
33. **Adım 33 (`SRE-76`):** `read_cache.py:invalidate_cache("user_profile")` global silme çağrısını kullanıcı bazlı `invalidate_user_profile_cache(username)` yapısına dönüştür; tek bir takip aksiyonunda 50.000 kullanıcının önbelleğinin silinmesini (Cache Stampede) durdur.
34. **Adım 34 (`SRE-73`):** `bootstrap_node2.sh` scriptine `postgresql-17` sunucu paketi kurulumunu ve dizin hazırlıklarını ekle; Node1 çöktüğünde PITR restore'un başarısız olmasını engelle.
35. **Adım 35 (`SRE-31`):** `verify_purchase_command.py` ve `wallet.py` içine `await session.commit()` ekle; gerçek parayla alınan Teqlik'lerin rollback olmasını engelle.
36. **Adım 36 (`SRE-32`):** `handle_store_refund_command.py` ve `wallet_tasks.py` içine `await session.commit()` ekle; sonsuz bedava Teqlik / refund exploit'ini kapat.
37. **Adım 37 (`SRE-47`):** `store/factory.py` içine Google Play verifier ekle (`GooglePlayVerifier`); Android Teqlik satın alımlarının HTTP 500 almasını engelle.
38. **Adım 38 (`SRE-48`):** `apple_verifier.py` içine ortam kontrolü ekle (`settings.app_env == 'production'` ise `env == 'Sandbox'` reddet); sahte dekontla sınırsız Teqlik ve nakit çekim açığını kapat.
39. **Adım 39 (`SRE-55`):** `ads.py:create_campaign` içindeki genel `load_active_campaigns_to_redis()` çağrısını kaldırıp tekil `_reload_campaign_to_redis` çağrısına çevir; mevcut kampanyaların bütçe sıfırlanmasını durdur.
40. **Adım 40 (`SRE-65`):** `listings.py:generate_description` içinde LLM proxy çağrısı öncesine atomik TEQlik rezervasyonu / düşümü ve hata durumunda iade mekanizması ekle; TOCTOU yarış durumunu kapat.
41. **Adım 41 (`SRE-57`):** `teqlif.service` içindeki `ExecStartPre` lokasyon/kategori sync scriptlerini kaldır; servis yeniden başlarken 35 saniyelik 502 Bad Gateway kesintisini çöz.
42. **Adım 42 (`SRE-39`):** `teqlif.conf` Nginx dosyasında `client_max_body_size 5m` limitini `60m` yap; story ve medya yüklemelerinin HTTP 413 almasını engelle.
43. **Adım 43 (`SRE-40`):** `runbook.sh` kurtarma scriptinde DNS'i FastAPI/Nginx olmayan node2'ye yönlendirme adımını düzelt; felaket anında sitenin kararmasını engelle.
44. **Adım 44 (`SRE-01`):** `stream_concat_task.py` bozuk dosya sonsuz döngüsünü gider (`retry_count` ve `concat_failed`).
45. **Adım 45 (`SRE-02`):** `faiss_service.py` dosyasında `.tmp` ve `os.replace` ile atomik indeks yazımını uygula.
46. **Adım 46 (`SRE-11`):** `auction_commands.py` içindeki teklif verme mantığını Redis-first yap veya DB commit'i Redis başarısına bağla; reddedilen tekliflerin DB'de kalmasını engelle.
47. **Adım 47 (`SRE-20`):** `models/referral.py` içine `unique=True` ekle; `apply_referral` fonksiyonunu eşzamanlı çift kullanıma karşı koru.
48. **Adım 48 (`SRE-21`):** `teqlif.service` içine `--proxy-headers` ve `--forwarded-allow-ips="127.0.0.1"` ekle; IP bazlı login rate-limit ve shill bidding felaketini çöz.
49. **Adım 49 (`SRE-12`):** `main.py` lifespan içinden `start_flush_loop` ve `direct_sale_scheduler` çağrılarını kaldır; 8 Uvicorn worker'ın çoğaltılmış döngü çalıştırmasını engelle.

### 🟠 Faz 2: Dağıtık Sistem, Ağ ve Veri Bütünlüğü (P1 Öncelik — 78 Adım)
50. **Adım 50 (`SRE-101`):** `direct_sale_commands.py:purchase_sale` ve `cancel_sale` içine `with_for_update()` ve SQL seviyesinde atomik stok düşümü ekle; void edilen siparişler için alıcılara iptal bildirimi gönder.
51. **Adım 51 (`SRE-102`):** `streams.py:get_suggested_streamers` sorgusundaki filtresiz `follows GROUP BY` taramasını kaldır, yayıncı takipçi sayılarını denormalize sütundan oku ve 5 dakikalık Redis önbelleği ekle.
52. **Adım 52 (`SRE-108`):** `relationship_service.py` içindeki `is_busy` kontrolünü 1 saatlik statik izin önbelleğinden (`rel:A:B`) çıkar, anlık canlı meşguliyet değerlendirmesine taşı; 3. şahısların 1 saat boyunca aramadan kilitlenmesini (Cache Poisoning) engelle.
53. **Adım 53 (`SRE-109`):** `ad_service.py` bütçe düşme Lua script'ine `if current <= 0 then return nil end` guard'ı ekle; `pause_campaign` fonksiyonuna `pipe.srem("ad_campaigns:active", str(campaign_id))` ekleyerek duraklatılmış reklamların feed'de dönmesini engelle.
54. **Adım 54 (`SRE-110`):** `turkish_nlp.py:build_stemmed_tsquery` regex temizliğine tek ve çift tırnak karakterlerini ekle (`to_tsquery` syntax error 500 çökmesini durdur); `search.py` endpoint'lerindeki `offset` parametresine `le=1000` doğrulama tavanı getir.
55. **Adım 55 (`SRE-113`):** `delete_message_command.py` içinde herkesten silinen mesajlarda (`scope="everyone"`) `media_url` ve `thumbnail_url` varsa MinIO `delete_object_dm` çağrısını ekle; özel fotoğrafların yetim kalmasını ve KVKK ihlalini engelle.
56. **Adım 56 (`SRE-114`):** `ip_utils.py:mask_ip` içine IPv6 `/64` alt ağ maskelemesi ekle; mobil IPv6 kullanıcılarında shill bidding korumasının by-pass edilmesini durdur.
57. **Adım 57 (`SRE-120`):** `client_log.py` içindeki IP tespitini `CF-Connecting-IP` / `X-Forwarded-For` ile düzelt; `entry.details` sözlüğüne JSON sanitization ve 2.000 karakter sınırı getirerek log injection (CWE-117) açığını kapat.
58. **Adım 58 (`SRE-121`):** `favorites.py:remove_favorite` içindeki ilgisiz `ListingLike` silme kodunu kaldır; `add_favorite` içine double-click yarış koruması ekle ve beğeni işlemlerini `LikeService` ile senkronize et.
59. **Adım 59 (`SRE-122`):** `story_service.py` içindeki senkron FFmpeg video sıkıştırmasını HTTP thread'inden çıkarıp ARQ arka plan kuyruğuna delege et; Uvicorn event loop açlığını ve 504 Gateway Timeout'ları çöz.
60. **Adım 60 (`SRE-123`):** `worker.py` temizlik görevlerindeki `VACUUM ANALYZE` çağrılarını kaldırıp autovacuum'a devret; 30 günlük bildirimleri ve analitikleri 5.000'lik gruplarla (batch delete) sil.
61. **Adım 61 (`SRE-124`):** `influence_service.py` sorgusuna `status = 'accepted'` filtresi ve sparse matris optimizasyonu ekle; Redis pipeline komutlarını 1.000'lik gruplara bölerek OOM ve socket kilitlenmesini durdur.
62. **Adım 62 (`SRE-132`):** `fraud_detection_service.py:_log_fraud_attempt` içindeki global `fraud_log` Redis ZSET'ini ve her seferinde çalışan `zremrangebyscore` temizliğini kaldır; şüpheli teklif kayıtlarını ClickHouse `track_user_event` veya TTL'li Redis Stream'e (`XADD`) taşıyarak Redis dondurma ve OOM riskini engelle.
63. **Adım 63 (`SRE-133`):** `User` modeline `user_devices` (`user_id`, `fcm_token`, `platform`, `last_active_at`) ilişkisini ekle; `device_service.py` içinde geçersiz token olayında sadece ilgili cihazı silerek kullanıcının diğer aktif telefon ve tabletlerindeki bildirimlerin kesilmesini durdur.
64. **Adım 64 (`SRE-134`):** `livekit_service.py:lk_list_all_rooms` ve `lk_broadcast_delete` içindeki sıralı for döngülerini `asyncio.gather(*tasks, return_exceptions=True)` ile paralel hale getir ve 3.0s tavan timeout ekle; 1 erişilemez node yüzünden arka plan temizliğinin 16-60 sn kilitlenmesini çöz.
65. **Adım 65 (`SRE-135`):** `messages.py:_read_streaming` fonksiyonundaki bellekte `b"".join` biriktirmeyi kaldırıp doğrudan geçici dosyaya stream et; `media_processor.py` içindeki senkron Pillow `make_thumbnail` ve FFmpeg video analizini `asyncio.to_thread` ve worker kuyruğuna delege ederek Uvicorn açlığını engelle.
66. **Adım 66 (`SRE-136`):** `upsert_rating.py:UpsertRatingCommand` içindeki kilitsiz `scalar` ve `add` ikilisini PostgreSQL `ON CONFLICT (rater_id, rated_id) DO UPDATE` ifadesine dönüştür; komut içindeki kontrolsüz `commit()` çağrısını kaldırarak Unit of Work oturum bütünlüğünü koru.
67. **Adım 67 (`SRE-142`):** `upload.py:upload_listing_video` içindeki 60 MB bellek biriktirme ve senkron FFmpeg/FFprobe transcode işlemlerini HTTP isteğinden çıkarıp ARQ arka plan kuyruğuna delege et; istemcinin 60s bekleyip 504 Gateway Timeout almasını ve CPU %100 açlığını durdur.
68. **Adım 68 (`SRE-143`):** `admin_data.py:get_dashboard` endpoint'indeki 16 sıralı aggregate SQL ve 7 günlük döngüsel sorguyu tek bir tarih gruplamalı CTE'ye çevir ve sonuçları Redis'te 60 saniye TTL ile önbellekle; Postgres CPU kilitlenmesini çöz.
69. **Adım 69 (`SRE-144`):** `admin_data.py:get_admin_analytics_summary` içindeki `COUNT(DISTINCT session_id)` ve grup sorgularını transactional PostgreSQL yerine doğrudan ClickHouse `user_events` tablosuna yönlendir ve 5 dakikalık Redis önbelleği ekle; buffer cache kirlenmesini ve DB kilitlenmesini durdur.
70. **Adım 70 (`SRE-148`):** `stream_recording_tasks.py:notify_new_recordings_task` içindeki `available_at > NOW() - INTERVAL '6 hours'` katı sınırını kaldır ve `expires_at IS NULL` olan tüm kayıtlara güvenli son kullanma tarihi set eden fallback ekle; geciken video kayıtlarının sonsuza dek askıda kalmasını ve MinIO diskini tüketmesini engelle.
71. **Adım 71 (`SRE-157`):** `worker.py:cleanup_empty_message_threads_task` sorgusuna `AND mt.has_archive = FALSE` koşulunu ekle; 1 yıldan eski mesajları arşivlenmiş konuşmaların boş sanılarak silinmesini, kullanıcı arama izinleri ve arşiv bağlantılarının yok edilmesini engelle.
72. **Adım 72 (`SRE-158`):** `leads.py:send_retargeting` endpoint'inde TEQlik bakiye düşümünü push bildirim gönderiminin önüne al ve 24 saatlik cooldown ekle; yetersiz bakiye veya yarış durumlarında yüzlerce kişiye bedava bildirim sızdırılmasını engelle.
73. **Adım 73 (`SRE-159`):** `calls.py:start_call` içindeki `pg_advisory_xact_lock` kilidini tekil `callee_id` yerine kanonik kullanıcı çifti (`min(caller, callee), max(caller, callee)`) üzerine al; iki kullanıcının birbirini aynı anda aramasıyla oluşan split-brain ve çift LiveKit odası krizini çöz.
74. **Adım 74 (`SRE-149`):** `chat.py:chat_ws` el sıkışmasındaki çift DB oturumunu kaldırıp kullanıcı ve yayın doğrulamasını Redis oturumundan (`session:user:{id}` ve `stream:meta:{id}`) oku; bilateral block auto-mute setine (`mute_key`) 24 saatlik TTL ekleyerek PgBouncer kilitlenmesini ve kalıcı bellek sızıntısını çöz.
75. **Adım 75 (`SRE-150`):** `direct_sale.py:purchase_sale` endpoint'ine `_idem=Depends(idempotency_key("direct_sale_purchase", ttl=30))` ekle; zayıf hücresel bağlantı ve çift tıklamalarda mükerrer sipariş üretilmesini ve stokların haksız yere iki kat düşmesini engelle.
76. **Adım 76 (`SRE-163`):** `admin_data.py:update_user_info` içinde `token_version` artırma koşulunu `(PASSIVE, BANNED, DELETED)` olarak genişlet; yöneticinin banladığı kötü niyetli kullanıcıların JWT oturumlarını iptal etmeyerek API erişimini sürdürmesini engelle.
77. **Adım 77 (`SRE-164`):** `pro_insights_use_case.py` içinde `live_streams` ile `bids` join'ini `LEFT JOIN bids b ON b.stream_id = ls.id` ve `COUNT(DISTINCT b.id)` olarak refactor et; stream-auction-bid kartezyen çarpımıyla satıcı paneline şişirilmiş teklif sayısı gösterilmesini çöz.
78. **Adım 78 (`SRE-169`):** `analytics.py` modül seviyesine `from datetime import datetime as _dt, timedelta as _td` ekle; `video_roi`, `gallery_stats` ve `video_perf` Pro analitik endpoint'lerinin tarih filtreli sorgularda `NameError: name '_dt' is not defined` (HTTP 500) ile çökmesini çöz.
79. **Adım 79 (`SRE-170`):** `worker.py:cleanup_ghost_calls_task` fonksiyonu içine `from app.core.ws_manager import ws_manager` import'unu ekle; hayalet aramaların temizlenmesinde WebSocket bildiriminin `NameError` ile düşmesini ve kullanıcıların arama ekranında kilitli kalmasını engelle.
80. **Adım 80 (`SRE-173`):** `wallet.py:convert_to_teqlik` sonrasına `await invalidate_user_session_cache(current_user.id)` ekle; dönüştürülen TEQlik bakiyesinin 15 dk boyunca önbellekte eski kalmasını ve yetersiz bakiye hatasını engelle.
81. **Adım 81 (`SRE-174`):** `create_offer.py` içine satıcıya yönelik `push_notification` ve `ws_manager.publish` bildirimlerini ekle; ilan tekliflerinin satıcıya iletilmeyerek yanıtsız kalmasını ve satış döngüsünün tıkanmasını çöz.
82. **Adım 82 (`SRE-86`):** `ad_service.py:pause_campaign`, `cancel_campaign` ve `record_ad_click` içine `pipe.srem("ad_campaigns:active", str(campaign_id))` ekle; `feed_queries.py`'da pasif reklamların ilk 50 slotu tıkayıp tüm sponsorlu ilanları dondurmasını engelle.
83. **Adım 83 (`SRE-87`):** `listing_tasks.py:deactivate_expired_listings_task` sonrasına `remove_from_recent_feed_cache(lid)` ve `invalidate_listing(lid)` toplu pipeline çağrılarını ekle; zombi ilanların feed akışında kalmasını ve checkout çökmelerini engelle.
84. **Adım 84 (`SRE-90`):** `calls.py:end_call` içine grup katılımcılarına `call_ended` WS yayını (`broadcast_to_call_participants`) ve `webhooks.py:_on_call_room_finished` içine `clear_presence` ekle; misafirlerin askıda kalmasını ve 10 dakikalık meşgul kilitlenmesini engelle.
85. **Adım 85 (`SRE-91`):** `refresh_stream_token.py` içine `orchestrator.resolve_stream_endpoint(stream)` çağrısını ekle; token yenileyen izleyicilerin relay sunucusundan düşürülüp kaynak sunucuya (origin) hücum etmesini durdur.
86. **Adım 86 (`SRE-93`):** `firebase_adapter.py:send_multicast` içindeki sıralı senkron `requests` döngüsünü kaldırıp asenkron HTTP havuzuna veya Firebase Admin SDK `send_each_for_multicast` toplu gönderimine geçir; takipçi bildirimlerinde `critical` ARQ kuyruğunun 25 dakika kilitlenmesini çöz.
87. **Adım 87 (`SRE-95`):** `convert_to_teqlik_command.py` ve `send_gift_command.py` içine sistem hazine hesabı (`id=0`) bakiyesini `users` tablosunda güncelleyen SQL sorgusunu ekle; mutabakat ve denetim kayıtlarının bozulmasını engelle.
88. **Adım 88 (`SRE-96`):** `wallet.py:send-gift` ve `send_gift_command.py` içine yayın durumu (`stream.status == 'live'`) ve host doğrulaması ekle; kapanmış yayınlar üzerinden bakiye aklanmasını ve sahte hype manipülasyonunu engelle.
89. **Adım 89 (`SRE-97`):** `admin_data.py` kampanya duraklatma ve ilan pasifleştirme endpoint'lerine Redis önbellek temizleme (`srem ad_campaigns:active` ve `invalidate_listing_cache`) çağrılarını ekle; admin aksiyonları ile Redis arasındaki desenkronizasyonu çöz.
90. **Adım 90 (`SRE-82`):** `credit_service.py` ve `leads.py` içindeki TOCTOU yarış durumunu Redis Lua scripti ile atomik check-and-consume işlemine dönüştür; kullanıcıların ücretsiz haklarını (blast, boost, ai) eşzamanlı isteklerle limitsiz tüketmesini engelle.
91. **Adım 91 (`SRE-83`):** `tcmb_service.py:fetch_and_save_tcmb_rates` fonksiyonundaki `ForexBuying` text okumasına `NoneType` kontrolü ve fallback ekle; tatil günlerinde döviz kurlarının `AttributeError` ile çökmesini durdur.
92. **Adım 92 (`SRE-84`):** `relationship_service.py` içindeki `is_busy` kontrolünü 1 saatlik statik izin önbelleğinden çıkarıp `GetThreadStatusQuery` anında dinamik değerlendirmeye taşı; 15 saniyelik bir telefon görüşmesinde arama butonunun 1 saat kilitli kalmasını (Cache Poisoning) engelle.
93. **Adım 93 (`SRE-77`):** `admin_data.py:admin_send_push` içindeki senkron FCM döngüsünü ARQ arka plan kuyruğuna taşı ve Firebase Admin SDK `send_each_for_multicast` toplu gönderimine geçir; Uvicorn worker'ın 25 dakika donmasını önle.
94. **Adım 94 (`SRE-78`):** `cleaner.py` (teqlif-agent) içindeki süresi dolan hikaye temizliğine MinIO nesne silme koordinasyonunu ekle; depolamada yüzlerce GB yetim video birikmesini engelle.
95. **Adım 95 (`SRE-69`):** `auction.py` müzayede WebSocket handler'ını `ws_manager`'a bağla; Uvicorn restart anında soketlerin kirli kopmasını engelle.
96. **Adım 96 (`SRE-70`):** `story_service.py:delete_story` içinde MinIO silme işlemini DB commit sonrasına taşı; hata anında yetim ve bozuk 404 story kayıtlarını önle.
97. **Adım 97 (`SRE-74`):** `search_alerts.py:delete_alert` satır 103'teki `'passive'` string atamasını `SearchAlertStatus.DELETED` olarak düzelt; HTTP 500 çökmesini durdur.
98. **Adım 98 (`SRE-49`):** `apns_service.py` içindeki 60 saniyelik global circuit breaker'ı kaldır; tekil arama hatalarında tüm iOS çağrılarının düşmesini engelle.
99. **Adım 99 (`SRE-50`):** `like_service.py:add_stream_like` içindeki senkron DB commit ve 150.000 WS/sn yayınını Redis sayacına ve batch yayına dönüştür; DB kilitlenmesini çöz.
100. **Adım 100 (`SRE-51`):** `worker.py:delayed_close_stream_task` içindeki `except Exception:` durumunda yayını zorla kapatma mantığını iptal et; geçici ağ dalgalanmasında aktif yayınların kapatılmasını durdur.
101. **Adım 101 (`SRE-52`):** `encoder.py` içindeki FFmpeg ve `mc cp` çağrılarına `asyncio.wait_for` timeout ekle; askıda kalan süreçlerin tüm encoding kuyruğunu kilitlemesini engelle.
102. **Adım 102 (`SRE-53`):** `redis_failover.sh` failover scriptine sanal IP (VIP) veya mesh yönlendirmesi ekle; Node1 çöktüğünde istemcilerin Node2'ye bağlanabilmesini sağla.
103. **Adım 103 (`SRE-56`):** `story_service.py:cleanup_expired_stories` içindeki açık DB oturumunda senkron MinIO silme mantığını iki aşamalı soft-delete ve async drain mimarisine taşı.
104. **Adım 104 (`SRE-58`):** `teqlif.conf` içine canlı yayın ve müzayede WebSocket rotalarını kapsayan location regex'i ekle (`Upgrade` ve `Connection` başlıkları).
105. **Adım 105 (`SRE-59`):** `livekit_subscriber.py` video rotasyon ve VP8 encode işlemlerini `run_in_executor` ile thread pool'a devret; event-loop blokajını kaldır.
106. **Adım 106 (`SRE-61`):** `direct_sale_commands.py:purchase_sale` satıcının kendi ürününü satın almasını engelle (`sale.host_id == user.id`) ve bakiye/ödeme rezervasyonu ekle.
107. **Adım 107 (`SRE-64`):** `upload.py:upload_image` senkron Pillow LANCZOS thumbnail üretimini `run_in_executor` ile arka plana devret; API kilitlenmesini engelle.
108. **Adım 108 (`SRE-66`):** `teqlif-ai-proxy.service` (node5, node6) dinleme adresini `0.0.0.0` yerine WireGuard mesh IP'sine (`10.10.0.x`) çek; dış internete açılmayı engelle.
109. **Adım 109 (`SRE-41`):** `minio_backup.sh` içindeki hardcoded `MINIO_ILM_ID`'yi kaldırıp dinamik kural ID keşfi ekle; video silinme riskini gider.
110. **Adım 110 (`SRE-42`):** Node2 üzerinde `/etc/redis/redis-replica.conf` dosyasını oluştur ve bootstrap scriptine ekle; failover altyapısını çalışır kıl.
111. **Adım 111 (`SRE-43`):** `teqlif-agent` kullanıcısına `sudoers` systemctl izni ver ve `healer.py` çağrılarına `sudo` ekle; otomatik servis iyileştirmesini aktif et.
112. **Adım 112 (`SRE-44`):** `cluster.yaml` transfer penceresini `03:30-06:30` aralığına çekerek Pazar 02:00'deki `pg_basebackup` hat doygunluğunu çöz.
113. **Adım 113 (`SRE-33`):** `wallet_tasks.py:process_store_notification_task` içine Google Play RTDN işleme dalını (`elif platform == "google"`) ekle.
114. **Adım 114 (`SRE-34`):** `analytics.py:track_event` içindeki kapatılmış oturum sorununu gider; `_save_event_async` fonksiyonuna bağımsız `AsyncSessionLocal` bağla.
115. **Adım 115 (`SRE-35`):** `calls.py` ve `ws_manager.py` içine tahmin edilemez `ack_token` UUID doğrulaması ekle; sahte ACK ve arama DoS açığını kapat.
116. **Adım 116 (`SRE-36`):** Streaming node'ları (`node3`, `node4`) `livekit.yaml` dosyasındaki Redis adresini `10.10.0.1:6379` olarak düzelt veya HAProxy kurulumunu tamamla.
117. **Adım 117 (`SRE-37`):** `leads.py:send-blast` döngüsünü ARQ arka plan kuyruğuna taşı ve Firebase Admin SDK `send_each_for_multicast` toplu gönderimine geçir.
118. **Adım 118 (`SRE-19`):** `moderation_service.py` içindeki `remove_from_livekit` fonksiyonuna stream'in gerçek `livekit_url` bilgisini bağla.
119. **Adım 119 (`SRE-23`):** `direct_sale_commands.py` satın alma işleminde DB commit hatası durumunda Redis stok iadesi (compensating transaction) ekle.
120. **Adım 120 (`SRE-24`):** `ad_service.py` içindeki Lua scriptine `current <= 0` kontrolü ekleyerek negatif bütçe sızıntısını durdur.
121. **Adım 121 (`SRE-25`):** `stream_listener.py` içindeki `os.getpid()` kullanımını deterministik worker kimliğiyle değiştir; servis yeniden başlarken mesaj kaybını engelle.
122. **Adım 122 (`SRE-22`):** `story_service.py` içindeki senkron FFmpeg video sıkıştırmasını HTTP isteğinden çıkarıp ARQ video kuyruğuna taşı.
123. **Adım 123 (`SRE-13`):** `database_clickhouse.py` içindeki `_drain` fonksiyonunu en az bir kere garantili (At-least-once) hale getir; insert hatasında verinin Redis'ten silinmesini engelle.
124. **Adım 124 (`SRE-14`):** `thompson_sampling.py` dosyasındaki read-modify-write yapısını Redis `HINCRBYFLOAT` ile tekil atomik işleme dönüştür.
125. **Adım 125 (`SRE-15`):** `send_direct_message.py` içindeki kapatılmış session kullanımını gider.
126. **Adım 126 (`SRE-16`):** `churn_ml_service.py` model kaydını geçici dosya ve atomik rename ile güvenli hale getir.
127. **Adım 127 (`SRE-03`):** `worker.py` içinde video görevleri için bağımsız kuyruk ve uygun timeout yapılandırması tanımla.

### 🟡 Faz 3: Veritabanı, Eşzamanlılık ve Performans Optimizasyonu (P2 Öncelik — 45 Adım)
128. **Adım 128 (`SRE-125`):** `recommendation_service.py` içindeki `SELECT DISTINCT category` sorgusunu kaldırıp kategori önbelleğine bağla; `ORDER BY hashtext()` fonksiyonel sıralamasını Redis ID örneklemesiyle değiştir.
129. **Adım 129 (`SRE-126`):** `reports.py:report_listing` endpoint'ine katı `ReportCreateSchema` ve 1.000 karakterlik `max_length` ekle; `ON CONFLICT DO NOTHING` ile çift tıklama 500 hatasını engelle.
130. **Adım 130 (`SRE-137`):** `follows.py:accept_follow_request` içinde `sa_update(MessageThread)` sonucunda gerçekten bir satır güncellendiyse (`result.rowcount > 0`) ve sayaç sıfırdan büyükse `_redis.decr` çalıştır; okunmamış mesaj istek sayacının negatif sayılara düşmesini engelle.
131. **Adım 131 (`SRE-138`):** `ratings.py:mark_read` içindeki tüm ORM nesnelerini belleğe çekip Python döngüsüyle tek tek güncelleme yapısını kaldır; tek bir toplu `update(Rating)` SQL sorgusuna çevir ve `ratings:unread:{user_id}` Redis önbelleğini sıfırla.
132. **Adım 132 (`SRE-145`):** `leads.py:get_audience_size` içindeki 10.000 ID'lik `id = ANY(:ids)` PostgreSQL sorgusunu satıcı ve ilan filtrelerine göre Redis'te 120 saniye önbellekle; `NOT IN` anti-join yapısını `LEFT JOIN / IS NULL` veya ClickHouse bitmap fonksiyonlarına geçirerek cross-database darboğazını çöz.
133. **Adım 133 (`SRE-146`):** `wallet.py:get_balance` endpoint'inde bakiye bilgisini 15 dakikalık `session:user:{id}` Redis oturumundan değil doğrudan `select(User.teqlik_balance)` ile veritabanından taze oku; bakiye başlığı ile işlem listesi arasındaki 15 dakikalık senkronizasyon kopukluğunu gider.
134. **Adım 134 (`SRE-151`):** `notifications.py:notifications_ws` ilk bağlantı sayım sorgusuna `Notification.type != 'message'` filtresi ekle; DM bildirimlerinin yanlışlıkla sayıma dahil edilmesiyle mobil bildirim rozetinde yaşanan titremeyi (flickering) ve WS bağlantısındaki çift DB oturumunu gider.
135. **Adım 135 (`SRE-152`):** `models/call.py` ve `calls.py:get_call_history` için `ix_calls_caller_started` ve `ix_calls_callee_started` bileşik indekslerini ekle; arama geçmişi çekilirken PostgreSQL'in BitmapOr ve disk üzerinde QuickSort yaparak CPU'yu tüketmesini çöz.
136. **Adım 136 (`SRE-153`):** `feed.py:record_feed_signal` içindeki senkron `np.linalg.norm` vektör işlemlerini ve embedding DB sorgusunu `asyncio.to_thread` havuzuna veya Redis Stream sinyal kuyruğuna aktar; her ilan tıklamasında Uvicorn event loop'unun dondurulmasını engelle.
137. **Adım 137 (`SRE-160`):** `ads.py:CampaignCreate` şemasına `total_budget <= 5000` ve `cpc_bid <= 100` tavan doğrulaması ekle; 50 TEQlik flat boost ücretiyle 1 milyar bütçeli hayali kampanya açılmasını ve açık artırma algoritmasının manipüle edilmesini engelle.
138. **Adım 138 (`SRE-154`):** `admin_nodes.py:get_node` endpoint'inde tüm cluster'ı `keys("edge:metrics:*")` ile tarayan mantığı kaldırıp doğrudan `redis.get(f"edge:metrics:{node_id}")` tekil anahtar okumasına geçir; gereksiz küme taramasını ve Redis tek thread blokajını durdur.
139. **Adım 139 (`SRE-165`):** `onboarding.py:seed_interests` içinde `subcategory=""` varsayılan değerini ekle ve `uq_user_interest` kısıtına `NULLS NOT DISTINCT` kazandır; `NULL` subcategory nedeniyle PostgreSQL unique kısıtının delinmesini ve mükerrer kategori kayıtlarıyla öneri algoritmasının bozulmasını çöz.
140. **Adım 140 (`SRE-166`):** `bpr_service.py:train_bpr` içindeki 200 milyon iterasyonluk kontrolsüz `hard_neg_interactions` kartezyen döngüsünü kaldır veya kullanıcı başına 5 örnekle sınırla; `_WEIGHTS["_hard_neg"]` değerinin `w > 0` filtresiyle çöpe atılarak sunucunun OOM ile çökmesini engelle.
141. **Adım 141 (`SRE-103`):** `story_service.py:get_story_viewers` endpoint'ine zorunlu sayfalama (`limit`/`offset`) ve sadece gerekli sütunları çeken hafif sorgu ekle; OOM çökmesini engelle.
142. **Adım 142 (`SRE-104`):** `video_tasks.py:capture_hype_highlight` çıktısını yerel disk yerine MinIO'ya yükle ve yerel geçici dosyayı temizle; yayın kapanışında MinIO nesnesini sil.
143. **Adım 143 (`SRE-115`):** `chat.py` içindeki `system_join` yayınını 50 izleyicinin üzerindeki popüler yayınlarda kapat ve VIP/Whale filtresi ekle; sohbet soketlerinin kilitlenmesini durdur.
144. **Adım 144 (`SRE-116`):** `nodeMonitor/config/teqlif/prometheus.yml` içine `postgres`, `redis`, `pgbouncer` ve `fastapi` scrape job'larını ekle; altyapıdaki kör izleme durumunu gider.
145. **Adım 145 (`SRE-98`):** `listings.py:get_listing_offers` endpoint'ine `get_current_user` kimlik doğrulaması, ilan sahibi yetki kontrolü ve sayfalama ekle; teklif verenlerin kullanıcı verilerinin ve teklif miktarlarının rakiplerce kazınmasını engelle.
146. **Adım 146 (`SRE-88`):** `teqlif-agent/modules/health.py:_collect_hw_metrics` içindeki senkron `time.sleep(1)` çağrısını kaldırıp delta tabanlı asenkron ölçüme geçir; agent event loop'unun her 5 sn'de 1 saniye donmasını engelle.
147. **Adım 147 (`SRE-92`):** `chat_commands.py:add_viewer` ve `remove_viewer` içindeki sayaç artırımını `sadd` sonucuna (`added == 1`) veya `SCARD` komutuna bağla; `live:viewer_set` anahtarına 24 saatlik TTL ekle; sayacın bozulmasını ve kalıcı RAM sızıntısını çöz.
148. **Adım 148 (`SRE-85`):** `delete_conversation_command.py` ve `get_unread_count_query.py` içine `deleted_for_receiver` ve silinen thread kontrolü ekle; silinen sohbetlerin mobil uygulama üzerinde asla sıfırlanmayan hayalet okunmamış rozet (ghost unread badge) üretmesini engelle.
149. **Adım 149 (`SRE-79`):** `users.py:get_suggested_sellers` sorgusundaki tüm `follows` tablosunu `GROUP BY` yapan alt sorguyu kaldırıp kullanıcı bazlı denormalize takipçi sayısına veya skaler alt sorguya geçir; Postgres CPU %100 yükünü çöz.
150. **Adım 150 (`SRE-80`):** `admin_data.py:admin_delete_listing` satır 323'teki hatalı `listing.status = PASSIVE` atamasını kaldır; admin tarafından silinen ilanların `DELETED` kalmasını sağla.
151. **Adım 151 (`SRE-71`):** `catalog.py:/version` taksonomi sorgusunu Redis tamsayı sayacına çevir; her sürüm kontrolünde tüm DB'nin taranmasını engelle.
152. **Adım 152 (`SRE-75`):** `ratings.py:get_ratings` ve `favorites.py:get_favorites` endpoint'lerine zorunlu sayfalama (`limit`/`offset`) getir; O(N) IN clause şişmesini ve bellek patlamasını engelle.
153. **Adım 153 (`SRE-62`):** `messages.py:get_messages` GET endpoint'inden `MarkMessagesReadCommand` çağrısını kaldır; `POST /{other_user_id}/read` bağımsız endpoint'i açarak Read-Replica çökmesini ve prefetch okundu hatalarını engelle.
154. **Adım 154 (`SRE-63`):** `chat.py:_check_whale_status` mantıksal kontrolünü `host_type != "pro"` olarak düzelt; standart kullanıcıların yayınlarında her izleyici girişinde `Purchase` tablosunun taranmasını durdur.
155. **Adım 155 (`SRE-67`):** `recommendation_service.py:_ids_from_categories` dinamik `ORDER BY hashtext(...)` sıralamasını kaldırıp Redis Set veya hafif aralık örneklemesine geçir; Postgres CPU %100 darboğazını çöz.
156. **Adım 156 (`SRE-45`):** `.env.production` içindeki `ACCESS_TOKEN_EXPIRE_MINUTES` değerini 43200'den (30 gün) 60 dakikaya indir.
157. **Adım 157 (`SRE-46`):** `leader.py` içine 3 ardışık cycle toleransı ekle; split-brain ve mükerrer temizlik/raporlama riskini gider.
158. **Adım 158 (`SRE-54`):** `clickhouse_backup.sh` CLI sözdizimini düzelt ve fallback moduna dinamik tablo listesi ekle; tabloların yedeksiz kalmasını engelle.
159. **Adım 159 (`SRE-60`):** `livekit_relay.py` varsayılan Redis adresini `10.10.0.1:6379` yap; relay hazırlık sinyalinin kaybolmasını engelle.
160. **Adım 160 (`SRE-38`):** `auth.py:refresh_token` rotasyonuna 30 saniyelik grace period ekle; eşzamanlı isteklerde mobil kullanıcıların oturumdan atılmasını engelle.
161. **Adım 161 (`SRE-07`):** `transfer_teqlik.py` içinde satır kilitleme sırasını `min(id), max(id)` olarak düzenle (Deadlock 40P01 çözümü).
162. **Adım 162 (`SRE-28`):** `stream_finalizer.py` chat dump sorgusunu 500'lük chunk'lara bölerek asyncpg 32767 parametre limit çökmesini engelle.
163. **Adım 163 (`SRE-17`):** `listing_tasks.py` içindeki ilan pasifleştirmeyi tek bir `UPDATE ... RETURNING` sorgusuna indirge.
164. **Adım 164 (`SRE-18`):** `analytics_tasks.py` airdrop dağıtımını 500'lük gruplarla chunk'la.
165. **Adım 165 (`SRE-27`):** `recommendation_service.py` içindeki dinamik `SELECT DISTINCT category` sorgusunu kaldırıp kategori önbelleğini kullan.
166. **Adım 166 (`SRE-26`):** `storage_service.py:get_object_bytes` rastgele node seçimi yerine dosyanın yüklendiği yetkili MinIO adresini referans al.
167. **Adım 167 (`SRE-30`):** `hype_manager.py` skor durumunu Redis'e taşıyarak 8 Uvicorn worker arasında veri senkronizasyonunu sağla.
168. **Adım 168 (`SRE-05`):** `foryou_worker.py` içindeki sorguya `last_active_at` filtresi ekle ve Redis çağrılarını pipeline yap.
169. **Adım 169 (`SRE-06`):** `feed_als_ml.py` ve `swipe_live_ml.py` içindeki Redis pipeline'larına 1.000'lik chunk döngüsü ekle.
170. **Adım 170 (`SRE-08`):** `wallet_tasks.py` döngüsel SQL'lerini küme tabanlı batch işlemine dönüştür.
171. **Adım 171 (`SRE-09`):** `schedule.yaml` pazar sabahı görevlerini ardışık bir DAG zincirine bağla.
172. **Adım 172 (`SRE-04`):** `bpr_service.py` ve `feed_als_ml.py` veri çekme sorgularına satır tavanı (`LIMIT`) ve süre kısıtlaması getir.

### 🟢 Faz 4: Mimari İnce Ayar ve Dayanıklılık (P3 Öncelik — 2 Adım)
173. **Adım 173 (`SRE-10`):** ML eğitim fonksiyonlarının başına Redis dağıtık kilit mekanizması yerleştir.
174. **Adım 174 (`SRE-29`):** `stream_finalizer.py` ve `edge_orchestrator.py` içindeki O(N) `redis.keys()` aramalarını `SCAN` veya Redis Set indekslemesine çevir.
