# V2.0 Test ve Doğrulama Planı

**Kaynak:** [03_task.md](03_task.md)  
**Amacı:** Kurulumu tamamlanan (veya tamamlanmakta olan) Faz'ların doğruluğunu, komut çıktılarıyla ve sistem testleriyle teyit etmek.

---

## Faz 0 — Kod Hazırlığı (Lokalde)
- [ ] `python -c "from app.config import settings; print(settings.model_fields.keys())"` çalıştırıldı, config hatası dönmedi.
- [ ] `grep -r "edge_orchestrator" backend/app/` sonucu `0` satır (Kalıntı kod yok).
- [ ] `cd mobile && dart analyze` çalıştırıldı, `0 hata` alındı.
- [ ] Mobil `.env` (dart_defines) dosyalarında `UPLOADS_HOST`, `MEDIA_HOST`, `SHARE_BASE_URL` alanları eksiksiz girildi.
- [ ] `teqlif-secrets.env` Vault dosyası oluşturuldu ve 11 sunucunun şifreleri tek yerde toplandı.

---

## Faz 1 — OS Temeli (Tüm Node'lar)
- [ ] **SSH Güvenliği:** `ssh -o PasswordAuthentication=no root@<ip>` ile root girişinin reddedildiği görüldü.
- [ ] **NTP Senkronizasyonu:** `chronyc tracking | grep "System time"` çıktısında senkronizasyon doğrulandı.
- [ ] **Swap (Node5, 6, 7, 8):** `free -h | grep Swap` çıktısında Swap alanının aktif olduğu görüldü.
- [ ] **Journald Limit:** `cat /etc/systemd/journald.conf | grep SystemMaxUse=300M` çıktısı alındı.

---

## Faz 2 — WireGuard Mesh
- [ ] **Mesh İletişimi:** Her node'dan diğer 10 node'a ping atıldı (`ping -c1 10.10.0.x`), %0 packet loss.
- [ ] **Handshake Sağlığı:** `wg show wg0` çıktısında tüm peer'lar için "Latest handshake" süresinin < 5 dakika olduğu görüldü.
- [ ] **PersistentKeepalive:** Tüm `wg0.conf` dosyalarında `PersistentKeepalive = 25` kuralı mevcut (Tünel düşmesi engellendi).

---

## Faz 3 — Rol Bazlı OS Tuning
- [ ] **Sysctl Limitleri:** `sysctl -p /etc/sysctl.d/99-teqlif.conf` çalıştırıldı, kernel hata vermedi.
- [ ] **UFW Güvenlik Duvarı:** `ufw status verbose` çalıştırıldı; dışarıdan gelen gereksiz portlar kapalı, yalnızca Cloudflare ve `wg0` subneti (`10.10.0.0/24`) izinli.

---

## Faz 4 — Veri Katmanı HA (Node5 + Node6)
- [ ] **PostgreSQL Bağlantısı:** `psql -h 127.0.0.1 -U teqlif -d teqlif` başarıyla bağlandı.
- [ ] **Replikasyon (Streaming):** Node5'te `select * from pg_stat_replication` çıktısında `node6_slot` ve lag ~0 görüldü.
- [ ] **Redis Replication:** `redis-cli -h 10.10.0.11 -p 6379 -a <pass> info replication` çıktısında `role:master` ve `connected_slaves:1` görüldü.
- [ ] **Keepalived VIP:** Node5'te `ip addr show wg0` çıktısında `10.10.0.10` ve `10.10.0.11` sanal IP'leri görülüyor.
- [ ] **Split-Brain Koruması:** `wg_vip_failover.sh` betiği içerisinde Node 9 Quorum Ping satırı yer alıyor.

---

## Faz 5 — Core App
- [ ] **App Health:** `curl http://127.0.0.1:8000/v1/ping` -> `200 OK` (node5).
- [ ] **Worker RAM Sınırları:** Systemd MemoryMax (1500M, 1000M vb.) sınırları `systemctl status teqlif` üzerinden teyit edildi.
- [ ] **Guardian Redis Entegrasyonu:** `redis-cli -h 10.10.0.11 -p 6380 -a <pass> keys "edge:metrics:*"` ile Node5 metriklerinin yazıldığı görüldü.
- [ ] **Failover Testi (Uygulama):** Node5 Keepalived durdurulduğunda Node6'nın VIP'leri devraldığı ve API'nin `10.10.0.10` üzerinden çalışmaya devam ettiği doğrulandı.

---

## Faz 6 — Storage (MinIO)
- [ ] **S3 Proxy Health:** `curl -s https://media.teqlif.com/health` -> Nginx yanıt verdi (200).
- [ ] **Active-Active Replication:** Bir dosya yüklendiğinde, her iki node'da da `mc ls` ile eşzamanlı görülebildi (MinIO Site Replication çalışıyor).
- [ ] **Bucket Versioning:** `mc version info minio7/teqlif` komutu `enabled` döndürdü.

---

## Faz 7 — Gateway
- [ ] **Proxy Ping:** `curl -I https://api.teqlif.com/v1/ping` -> `200 OK` ve Cloudflare (CF-RAY) header'ları mevcut.
- [ ] **WebSocket:** Gateway üzerinden WS bağlantısı 10 saniyeden uzun kopmadan açık kalabiliyor.
- [ ] **Presigned Upload Bypass:** Gateway Nginx loglarında (access.log), dosya yükleme (PUT) için `Content-Length > 100KB` bir istek görülmedi.

---

## Faz 8 — Stream + AI Proxy
- [ ] **LiveKit SFU:** `curl -s http://10.10.0.1:7880/` -> `200 OK` (node1/node4).
- [ ] **AI Proxy (Node2):** `curl -s http://10.10.0.3:8001/health` -> `200 OK`.
- [ ] **AI Proxy Orchestrator:** `redis-cli -h 10.10.0.11 -p 6380 -a <pass> get ai_proxy:active_url` komutu `http://10.10.0.3:8001` değerini (veya Node3'ü) döndürdü.

---

## Faz 9 — Guardian Koordinatör
- [ ] **Tüm Ajan Metrikleri:** Redis'teki `edge:metrics:*` anahtarlarında toplam 11 sunucunun (Gateway, Stream, Storage, Monitor vb.) listelendiği teyit edildi.
- [ ] **Storage Failover Testi:** Node8 MinIO servisi durduruldu, sistemin 10-15sn içinde `orch:best:storage_nodes` değerini `["node7"]` olarak güncellediği görüldü.
- [ ] **AI Proxy Failover Testi:** Node2 `teqlif-ai-proxy` durduruldu, sistemin aktif URL'yi Node3 (`http://10.10.0.4:8001`) olarak güncellediği doğrulandı.

---

## Faz 10 — Monitoring + Backup (Node9)
- [ ] **Prometheus:** `curl -s http://10.10.0.13:9090/api/v1/targets` -> `11 target UP` durumu doğrulandı.
- [ ] **Loki (Promtail):** `curl "http://10.10.0.13:3100/loki/api/v1/labels"` -> Node label'ları listelendi (Tüm ağın logları akıyor).
- [ ] **Backup (pg_receivewal):** `systemctl is-active teqlif-pg-receivewal` -> `active` ve `/data/teqlif_backups/postgres/wal/` dizininde WAL dosyaları birikiyor.
- [ ] **Backup (Cron):** `/data/teqlif_backups/postgres/dump/` veya MinIO arşiv dizininde test dump/aynalama dosyası oluştu.
- [ ] **Off-site Sync:** `rclone lsd b2backup:` -> Cloud depolama bucket'ı başarıyla listelendi.
- [ ] **Alertmanager:** Test alarmı tetiklendiğinde Telegram `#ops` kanalına mesaj düştü.

---

## Faz 11 — Staging (Node3)
- [ ] **Health Checks:** 
  - `curl -s http://127.0.0.1:8000/v1/ping` -> `200 OK`
  - `curl -s http://127.0.0.1:8001/health` -> `200 OK` (Lokal AI Proxy)
  - `curl -s http://127.0.0.1:9000/minio/health/live` -> `200 OK` (Lokal MinIO)
- [ ] **Staging Servisleri:** `teqlif-staging`, `redis-staging`, `minio-staging`, `livekit-staging`, `teqlif-ai-proxy` servislerinin tamamı `active`.
- [ ] **Staging MinIO URL:** Uygulamanın `uploads-staging.teqlif.com` S3 presigned PUT adresi üzerinden başarılı medya yükleyebildiği (200) teyit edildi.
- [ ] **Secrets:** `firebase-service-account.json` ve `AuthKey_*.p8` dosyaları `/etc/teqlif/` dizininde (Lokal kasadan kopyalanmış).

---

## Faz 12 — Prodüksiyon + Mobile DNS
- [ ] **DNS Doğrulama:** 
  - `api.teqlif.com` -> Sadece Gateway IP'leri (Cloudflare Proxied).
  - `uploads.teqlif.com` -> Node7 ve Node8 IP'leri (Cloudflare DNS Only).
- [ ] **UFW Doğrulama:** MinIO portuna (9000) internetten direkt ulaşılamadığı (Timeout), ancak Gateway/Nginx portlarına ulaşılabildiği doğrulandı.

---

## Faz 13 — Tam Entegrasyon ve Circuit Breaker
- [ ] **ClickHouse Veri Akışı:** `SELECT count() FROM teqlif.analytics_events` komutunda, uygulamada yapılan aksiyonlarla birlikte satır sayısının arttığı görüldü.
- [ ] **Circuit Breaker:** Node9 kapatıldığında (veya ClickHouse durdurulduğunda), Core App (Node5) canlı kalmaya, hata vermeden çalışmaya ve API isteklerine yanıt vermeye devam etti.
- [ ] **Grafana Dashboard:** `http://10.10.0.13:3000` üzerinden giriş yapılıp, Loki loglarının ve metriklerin tek panelde görülebildiği teyit edildi.
- [ ] **Guardian Liderlik Durumu:** Node9'un `guardian_priority=5` olduğu için kendisini hiçbir zaman lider ilan etmediği, liderin 1 veya 2 numaralı Node'larda (Core) kaldığı Redis üzerinden (`guardian:topology`) teyit edildi.
