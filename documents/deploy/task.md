# Teqlif VPS Kurulum — Görev Takibi

**Hedef VPS:** `135.125.175.223`  
**Başlangıç:** 2026-09-02  
**Durum:** 🔄 Devam ediyor

> Her adımı tamamladıktan sonra çıktıyı paylaş → birlikte doğrulayıp bir sonraki adıma geçeceğiz.

---

## Faz 1 — Sistem Kurulumu

- [x] **1.1** `apt update && apt upgrade -y` + gerekli paketler kuruldu
- [x] **1.2** Python 3.13.5 kurulu (Debian 13 trixie native)
- [x] **1.3** Dizin yapısı oluşturuldu (`uploads/`, `backend/logs/`, `backend/certificates/`, `/var/backups/redis`)
- [x] **1.4** UFW güvenlik duvarı kuralları → aktif, SSH/HTTP/HTTPS/LiveKit/TURN/Grafana kuralları uygulandı
- [x] **1.5** Fail2ban → aktif, 3 jail: `nginx-botscan`, `nginx-req-limit`, `sshd`

## Faz 2 — Servis Kurulumları

- [x] **2.1** PostgreSQL 17 + pgvector kuruldu, online
- [x] **2.1b** DB `teqlif` ve kullanıcı oluşturuldu, `vector` + `pg_trgm` extension'ları aktif
- [x] **2.2** Redis 8.0.2 kuruldu, eski VPS config kopyalandı, `redis-cli ping` → PONG
- [x] **2.3** ClickHouse 26.9.1.530 kuruldu, systemd unit eski VPS'ten kopyalandı, aktif
- [x] **2.4** MinIO kuruldu, systemd aktif, `teqlif` bucket oluşturuldu
- [x] **2.5** Nginx kuruldu, config kopyalandı, SSL sertifikaları aktarıldı, `nginx -t` başarılı

## Faz 3 — Uygulama Kurulumu

- [x] **3.1** Git repo klonlandı (`/var/www/teqlif.com`)
- [x] **3.2-git** Git SSH kuruldu, ownership düzeltildi, `git pull` çalışıyor
- [x] **3.2** venv oluşturuldu, `pip install -r requirements.txt` tamamlandı (hatasız)
- [x] **3.3** `.env` oluşturuldu, `chmod 600` uygulandı, `APNS_USE_SANDBOX=False`
- [x] **3.4** Sertifika dosyaları kopyalandı (`AuthKey_C2PL2A2P6X.p8`, `voip_cert.pem`, `firebase-service-account.json`)
- [x] **3.5** DB şeması eski VPS'ten `pg_dump --schema-only` ile alındı, uygulandı, `alembic stamp head` ile işaretlendi
- [x] **3.5b** Tüm production verisi (`pg_dump --data-only`) eski VPS'ten aktarıldı — 8 kullanıcı, 12020 çeviri, 970 ilçe, 59 alt kategori
- [x] **3.6** Systemd unit'leri kuruldu ve enable edildi (teqlif, workers, redis-backup.timer, PartOf override'ları)

## Faz 4 — LiveKit

- [x] **4.1** LiveKit 1.13.3 binary eski VPS'ten kopyalandı
- [x] **4.2** `/etc/livekit/livekit.yaml` kopyalandı, `node_ip` → `135.125.175.223`
- [x] **4.3** Systemd unit kuruldu, `livekit` kullanıcısı oluşturuldu, servis aktif

## Faz 5 — Nginx + SSL

- [x] **5.1** Nginx config eski VPS'ten kopyalandı (`teqlif.com` + `live.teqlif.com`)
- [x] **5.2** SSL sertifikaları eski VPS'ten kopyalandı (`/etc/letsencrypt/`)
- [x] **5.3** `nginx -t` başarılı, reload yapıldı

## Faz 6 — Monitoring (Opsiyonel)

- [x] **6.1** Loki 3.6.7 kuruldu, aktif
- [x] **6.2** Promtail 3.0.0 kuruldu, aktif
- [x] **6.3** Grafana 13.2.0 kuruldu, aktif, grafana.db eski VPS'ten kopyalandı, ClickHouse plugin kuruldu
- [x] **6.4** Prometheus 2.51.0 kuruldu, aktif
- [x] **6.5** node_exporter 1.8.2 kuruldu, aktif
- [x] **6.6** prometheus-postgres-exporter 0.17.1 kuruldu, pg_up=1, Unix socket bağlantısı
- [x] **6.7** Promtail config kopyalandı, GeoIP DB aktarıldı, aktif — tüm log panelleri çalışıyor

## Faz 6.5 — Squarespace DNS Yönetimi

- [ ] **DNS.1** Squarespace DNS paneline gir
- [ ] **DNS.2** TTL'leri 60 saniyeye düşür (cutover'dan 24 saat önce)
- [ ] **DNS.3** A kayıtlarını `135.125.175.223`'e güncelle:
  - `teqlif.com`
  - `www.teqlif.com`
  - `admin.teqlif.com`
  - `live.teqlif.com`
- [ ] **DNS.4** Yayılmayı doğrula: `dig teqlif.com +short` → `135.125.175.223`

> ⚠️ DNS cutover öncesi yeni VPS'teki tüm servisler çalışır durumda olmalı.

## Faz 7 — Canlıya Alma

- [ ] **7.1** DNS TTL düşürüldü (24 saat önce)
- [x] **7.2** Tüm servisler başlatıldı (teqlif, teqlif-worker, teqlif-worker-critical, livekit, minio, redis, postgresql, clickhouse)
- [ ] **7.3** DNS A kayıtları güncellendi
- [ ] **7.4** `curl -I https://teqlif.com/api/health` → 200

## Faz 8 — Dış Servis Kontrolleri

- [ ] **8.1** Firebase service account → test
- [ ] **8.2** APNs → test
- [ ] **8.3** Brevo SPF kaydı kontrol
- [ ] **8.4** LiveKit bağlantı testi

---

## Tamamlananlar

_(adımlar tamamlandıkça buraya taşınacak)_

---

## Notlar

_(sorunlar, çözümler, önemli kararlar buraya)_
