# Scale V1.0 — Task Listesi

**Referans:** `deploy/scale/V1.0/plan.md`  
**Başlangıç:** 2026-09-07  
**Durum:** ✅ TAMAMLANDI (2026-09-07)

> Her task tamamlandığında `[x]` yap ve commit hash'ini yaz.  
> Her adım, önceki adım tamamlanmadan başlamaz — sıra önemli.  
> Uygulama kodu değişikliği yok (plan.md Bölüm 6 teyit etti).

---

## ✅ Tamamlananlar

- [x] Grafana node1'den kaldırıldı — `apt remove --purge`, UFW port 3000 kapatıldı, ~2.3 GB disk geri alındı (`f535a48e`)
- [x] `deploy/` klasörü oluşturuldu — monolith + scale/V1.0 yapısı, tüm config dosyaları (`074fc885`)
- [x] gateway'de git kurulumu ve repo klonlandı → `/var/www/teqlif.com`
- [x] plan.md `deploy/scale/V1.0/plan.md`'ye taşındı
- [x] **Adım 1 — WireGuard Kurulumu tamamlandı** — node1↔gateway tünel aktif, handshake ✅, ping ✅ (`7c4577ad`)
  - node1: `10.10.0.1` — public key `JEI9uud8kaoK7t3vSSrKeFCvibiOclbf1NhidFlQuyc=`
  - gateway: `10.10.0.2` (94.16.105.135) — public key `7AQbLvVlCdTvDOlFJslZ01PWzgvNhL2r/7f0Lw7ld0Y=`
- [x] **Adım 2 — gateway Taban Kurulumu tamamlandı** — prometheus/loki/promtail/node_exporter active, nginx+fail2ban kurulu ✅
- [x] **Adım 3 — gateway nginx + SSL tamamlandı** — Let's Encrypt cert node1'den kopyalandı, nginx proxy zinciri doğrulandı ✅
- [x] **Adım 4a — node1 teqlif.service + teqlif-staging.service tamamlandı** — `--host 0.0.0.0`, `--forwarded-allow-ips 10.10.0.2` ✅
- [x] **Adım 5 — node1 Firewall Sertleştirme tamamlandı** — gateway→8000/8001/9100/9187/7881 açık, public deny ✅
- [x] **Adım 6 — DNS Değişikliği tamamlandı** — teqlif.com/staging→gateway(94.16.105.135 Proxied), uploads.teqlif.com→node1(DNS Only) ✅
- [x] **Adım 8 — Tam Doğrulama** — teqlif.com ✅ staging ✅ uploads.teqlif.com MinIO direkt ✅
- [x] **Adım 7 — Mobil imgUrl() güncellendi** — `/uploads/` path'leri `kUploadsHost` (uploads.teqlif.com) ile çözülüyor; `chat_panel._resolveImageUrl` de birleştirildi (`207fd8c3`)
- [x] **gateway certbot renewal** — certonly ile teqlif.com+www+staging sertifikası alındı (staging.teqlif.com/ altında), livekit deploy hook silindi, nginx cert path güncellendi (`207fd8c3`)
- [x] **node1 uploads.teqlif.com nginx** — `deploy/scale/V1.0/node1/nginx/uploads.teqlif.com` kopyalandı, certbot ile `uploads.teqlif.com` sertifikası alındı, nginx reload ✅

---

## ✅ Adım 1 — WireGuard Kurulumu — TAMAMLANDI

> Sıfır downtime. `wg0` arayüzü `eth0`'a dokunmaz; SSH bağlantısı kesilmez.

- [ ] **node1:** WireGuard kur, key çifti üret
  ```bash
  sudo apt install -y wireguard
  wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
  sudo chmod 600 /etc/wireguard/privatekey
  sudo cat /etc/wireguard/publickey   # gateway config'ine girecek
  ```

- [ ] **gateway:** WireGuard kur, key çifti üret
  ```bash
  sudo apt install -y wireguard
  wg genkey | sudo tee /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey
  sudo chmod 600 /etc/wireguard/privatekey
  sudo cat /etc/wireguard/publickey   # node1 config'ine girecek
  ```

- [ ] **node1:** `/etc/wireguard/wg0.conf` oluştur (`deploy/scale/V1.0/wireguard/node1-wg0.conf` şablonu)
  - `<NODE1_PRIVATE_KEY>` → `sudo cat /etc/wireguard/privatekey`
  - `<GATEWAY_PUBLIC_KEY>` → gateway'de üretilen public key

- [ ] **gateway:** `/etc/wireguard/wg0.conf` oluştur (`deploy/scale/V1.0/wireguard/gateway-wg0.conf` şablonu)
  - `<GATEWAY_PRIVATE_KEY>` → `sudo cat /etc/wireguard/privatekey`
  - `<NODE1_PUBLIC_KEY>` → node1'de üretilen public key

- [ ] **node1:** UFW'e WireGuard portu ekle
  ```bash
  sudo ufw allow 51820/udp
  ```

- [ ] **Her iki node'da:** WireGuard başlat
  ```bash
  sudo chmod 600 /etc/wireguard/wg0.conf
  sudo systemctl enable --now wg-quick@wg0
  ```

- [ ] **Doğrulama:**
  ```bash
  # gateway'den:
  ping 10.10.0.1   # node1'e ulaşmalı
  # node1'den:
  ping 10.10.0.2   # gateway'e ulaşmalı
  # Tünel durumu:
  sudo wg show
  ```

**Commit hash:** _______________

---

## ✅ Adım 2 — gateway Taban Kurulumu — TAMAMLANDI

> Binary sürümleri: prometheus 2.51.0, loki 3.6.7, promtail 3.0.0, node_exporter 1.8.2 (node1'den scp ile kopyalandı)

- [x] **gateway:** Temel paketler kur
  ```bash
  sudo apt update && sudo apt install -y nginx fail2ban curl wget
  ```

- [x] **gateway:** Binary'leri node1'den kopyala
  ```bash
  scp /usr/local/bin/prometheus /usr/local/bin/loki /usr/local/bin/promtail /usr/local/bin/node_exporter tucibeyin@10.10.0.2:/tmp/
  sudo mv /tmp/prometheus /tmp/loki /tmp/promtail /tmp/node_exporter /usr/local/bin/
  sudo chmod +x /usr/local/bin/prometheus /usr/local/bin/loki /usr/local/bin/promtail /usr/local/bin/node_exporter
  sudo useradd -r -s /sbin/nologin prometheus 2>/dev/null || true
  sudo mkdir -p /etc/prometheus /var/lib/prometheus /etc/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
  sudo chown prometheus:prometheus /var/lib/prometheus /etc/prometheus
  ```

- [x] **gateway:** Config dosyalarını kopyala ve servisleri başlat
  ```bash
  cd /var/www/teqlif.com && git pull
  sudo cp deploy/scale/V1.0/gateway/prometheus.yml /etc/prometheus/prometheus.yml
  sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
  sudo cp deploy/scale/V1.0/gateway/loki-config.yml /etc/loki/config.yml
  sudo cp deploy/scale/V1.0/gateway/promtail-config.yml /etc/promtail-config.yml
  sudo cp deploy/scale/V1.0/gateway/systemd/*.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now prometheus loki promtail node_exporter
  ```

- [x] **Doğrulama:** `curl http://localhost:9090/-/healthy` → "Prometheus Server is Healthy."

**Commit hash:** `f69a3f02`

---

## ✅ Adım 3 — gateway nginx Yapılandırması + SSL — TAMAMLANDI

> SSL sertifikası: node1'den kopyalandı, sonra certbot ile gateway'de yeniden alındı.
> **Önemli:** Cert path `staging.teqlif.com/` altında (teqlif.com+www+staging birleşik).

- [x] **node1'de** sertifikaları paketle ve gateway'e gönder:
  ```bash
  sudo tar czf /tmp/letsencrypt.tar.gz /etc/letsencrypt/
  scp /tmp/letsencrypt.tar.gz tucibeyin@10.10.0.2:/tmp/
  ```

- [x] **gateway'de** sertifikaları aç, certbot kur:
  ```bash
  sudo tar xzf /tmp/letsencrypt.tar.gz -C /
  sudo apt install -y certbot python3-certbot-nginx
  ```

- [x] **gateway'de** nginx config'i kur:
  ```bash
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/nginx/nginx-http-zones.conf /etc/nginx/conf.d/http-zones.conf
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/nginx/teqlif.conf /etc/nginx/sites-available/teqlif.conf
  sudo ln -sf /etc/nginx/sites-available/teqlif.conf /etc/nginx/sites-enabled/teqlif.conf
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
  ```

- [x] **gateway'de** certbot ile kendi sertifikasını al (DNS gateway'e geçtikten sonra):
  ```bash
  sudo certbot certonly --nginx -d teqlif.com -d www.teqlif.com -d staging.teqlif.com
  # "Expand" seçildi — mevcut staging.teqlif.com cert'e diğer domainler eklendi
  sudo rm /etc/letsencrypt/renewal-hooks/deploy/livekit-cert.sh  # node1'den kopyalanan hook, gateway'de livekit yok
  ```

- [x] **Doğrulama:** `curl -s https://www.teqlif.com/api/health` → `{"status":"ok","version":"0.1.0"}`

**Commit hash:** `e29e5ddd`

---

## ✅ Adım 4 — Deploy Config Değişiklikleri — TAMAMLANDI

> 4 config değişikliği (plan.md Bölüm 6). Deploy pipeline değişmez, sadece config.

### 4a — node1 teqlif.service ve teqlif-staging.service

> **Düzeltme:** `--host 127.0.0.1` → `--host 0.0.0.0` (gateway WireGuard üzerinden erişebilsin)
> **Düzeltme:** teqlif-staging WorkingDirectory `/var/www/teqlif.com/backend`, EnvironmentFile `.env.staging`

- [x] node1'de:
  ```bash
  cd /var/www/teqlif.com && git pull
  sudo cp deploy/scale/V1.0/node1/systemd/teqlif.service /etc/systemd/system/teqlif.service
  sudo cp deploy/scale/V1.0/node1/systemd/teqlif-staging.service /etc/systemd/system/teqlif-staging.service
  sudo systemctl daemon-reload
  sudo systemctl restart teqlif teqlif-staging
  ```

### 4b — node1 promtail → gateway Loki

- [x] node1'de:
  ```bash
  sudo cp deploy/scale/V1.0/node1/promtail-config.yml /etc/promtail-config.yml
  sudo systemctl restart promtail
  ```

### 4c — node1 Prometheus + Loki durdur

- [x] node1'de:
  ```bash
  sudo systemctl stop prometheus loki
  sudo systemctl disable prometheus loki
  ```

### 4d — node1 node_exporter WireGuard IP'de dinle

- [x] node1'de:
  ```bash
  sudo cp deploy/scale/V1.0/node1/systemd/node_exporter.service /etc/systemd/system/node_exporter.service
  sudo systemctl daemon-reload && sudo systemctl restart node_exporter
  ```
- [x] **Doğrulama (gateway'den):** tüm Prometheus target'ları `up` — livekit dahil

**Commit hash:** `ed96b11b`

---

## ✅ Adım 5 — node1 Firewall Sertleştirme — TAMAMLANDI

> WireGuard ve gateway nginx aktif olduktan sonra yapılır.

- [x] node1'de (gateway'e izin ver):
  ```bash
  sudo ufw allow from 10.10.0.2 to any port 8000
  sudo ufw allow from 10.10.0.2 to any port 8001   # staging
  sudo ufw allow from 10.10.0.2 to any port 9100   # node_exporter
  sudo ufw allow from 10.10.0.2 to any port 9187   # postgres-exporter
  sudo ufw allow from 10.10.0.2 to any port 7881   # livekit metrics
  sudo ufw deny 8000
  sudo ufw deny 8001
  ```
  > UFW kural sırası önemli: `allow from 10.10.0.2` önce, `deny` sonra.
  > Loopback (127.0.0.1) UFW tarafından varsayılan izinli — node1 nginx etkilenmez.

- [x] **Doğrulama (gateway'den):** `curl http://10.10.0.1:8000/api/health` → `{"status":"ok"}`

**Commit hash:** `e29e5ddd`

---

## ✅ Adım 6 — DNS Değişikliği (Cloudflare) — TAMAMLANDI

> Gateway nginx ve WireGuard tüneli çalışıyorken yapılır. En kritik adım.

- [x] Cloudflare'de yapılan değişiklikler:
  - `teqlif.com` A → `94.16.105.135` (Proxied) ✅
  - `staging.teqlif.com` A → `94.16.105.135` (Proxied) ✅
  - `uploads.teqlif.com` A → `135.125.175.223` (DNS Only) ✅ (yeni eklendi)
  - `www.teqlif.com` CNAME → teqlif.com (Proxied, değişmedi)
  - `live.teqlif.com`, `minio.teqlif.com` node1'de kaldı (değişmedi)
  - Cloudflare Redirect Rule (`teqlif.com → www.teqlif.com`) silindi
  - SSL/TLS modu: Full (Strict)

- [x] **node1'de** uploads.teqlif.com nginx kurulumu:
  ```bash
  sudo certbot certonly --nginx -d uploads.teqlif.com
  sudo cp deploy/scale/V1.0/node1/nginx/uploads.teqlif.com /etc/nginx/sites-available/uploads.teqlif.com
  sudo nginx -t && sudo systemctl reload nginx
  ```

- [x] **Doğrulama:**
  - `curl -s https://teqlif.com/api/health` → `{"status":"ok"}`
  - `curl -sI https://uploads.teqlif.com/teqlif/test` → `HTTP/2 404` `server: nginx` `x-minio-error-code: NoSuchKey` ✅

**Commit hash:** `b5d5ddbc`

---

## ✅ Adım 7 — Mobil Uygulama Upload URL Güncelleme — TAMAMLANDI

- [x] `mobile/lib/config/api.dart` — `kUploadsHost` sabiti eklendi, `imgUrl()` güncellendi:
  - `/uploads/abc.jpg` → `https://uploads.teqlif.com/abc.jpg` (gateway bypass)
  - Diğer relative path'ler → `kBaseHost` prefix'i
- [x] `mobile/lib/widgets/chat_panel.dart` — `_resolveImageUrl()` `imgUrl()`'e birleştirildi
- [x] gateway certbot renewal: `staging.teqlif.com` cert altında tüm domainler; livekit hook silindi

**Commit hash:** `207fd8c3`

---

## ✅ Adım 8 — Tam Doğrulama Checklist — TAMAMLANDI

- [x] `curl https://teqlif.com/api/health` → 200 ✅
- [x] `curl https://staging.teqlif.com/api/health` → 200 ✅
- [x] `curl -sI https://uploads.teqlif.com/teqlif/test` → 404 MinIO (node1 direkt) ✅
- [x] Prometheus: tüm target'lar `up` (node-node1, node-gateway, postgres, livekit, prometheus) ✅
- [x] SSL: Let's Encrypt, TLSv1.3, HTTP/2 ✅
- [ ] WebSocket bağlantısı — canlı uygulama ile test edilmeli
- [ ] LiveKit WebRTC ICE — canlı arama ile test edilmeli
- [ ] MinIO presigned DM URL'leri — canlı DM ile test edilmeli

---

## Rollback Planı

Her adımda sorun çıkarsa:

| Adım | Rollback |
|------|----------|
| WireGuard | `sudo systemctl stop wg-quick@wg0` — SSH etkilenmez |
| gateway nginx | DNS henüz değişmedi — node1 nginx trafiği taşımaya devam eder |
| forwarded-allow-ips | `deploy/monolith/systemd/teqlif.service` → eski haline döndür |
| DNS | Cloudflare'de A kaydını node1'e geri al (TTL 60s → ~1 dakika yayılır) |
