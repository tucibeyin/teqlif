# Scale V1.0 — Task Listesi

**Referans:** `deploy/scale/V1.0/plan.md`  
**Başlangıç:** 2026-09-07  
**Durum:** 🟡 Devam ediyor

> Her task tamamlandığında `[x]` yap ve commit hash'ini yaz.  
> Her adım, önceki adım tamamlanmadan başlamaz — sıra önemli.  
> Uygulama kodu değişikliği yok (plan.md Bölüm 6 teyit etti).

---

## ✅ Tamamlananlar

- [x] Grafana node1'den kaldırıldı — `apt remove --purge`, UFW port 3000 kapatıldı, ~2.3 GB disk geri alındı (`f535a48e`)
- [x] `deploy/` klasörü oluşturuldu — monolith + scale/V1.0 yapısı, tüm config dosyaları (`074fc885`)
- [x] gateway'de git kurulumu ve repo klonlandı → `/var/www/teqlif.com`
- [x] plan.md `deploy/scale/V1.0/plan.md`'ye taşındı

---

## 🔲 Adım 1 — WireGuard Kurulumu

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

## 🔲 Adım 2 — gateway Taban Kurulumu

> WireGuard tüneli aktif olduktan sonra başlanır.

- [ ] **gateway:** Temel paketler kur
  ```bash
  sudo apt update && sudo apt install -y nginx fail2ban curl wget
  ```

- [ ] **gateway:** Prometheus binary kur
  ```bash
  # deploy/scale/V1.0/gateway/systemd/prometheus.service şablonu
  sudo useradd -r -s /sbin/nologin prometheus 2>/dev/null || true
  sudo mkdir -p /etc/prometheus /var/lib/prometheus
  sudo chown prometheus:prometheus /var/lib/prometheus
  # Binary: eski node1'den kopyala veya GitHub releases'ten indir
  ```

- [ ] **gateway:** Loki binary kur
  ```bash
  sudo mkdir -p /etc/loki /var/lib/loki
  # deploy/scale/V1.0/gateway/loki-config.yml → /etc/loki/config.yml
  ```

- [ ] **gateway:** node_exporter binary kur
  ```bash
  # deploy/scale/V1.0/gateway/systemd/node_exporter.service şablonu
  ```

- [ ] **gateway:** promtail binary + GeoIP DB kur
  ```bash
  sudo mkdir -p /usr/share/GeoIP
  # GeoIP DB: node1'den kopyala
  scp tucibeyin@10.10.0.1:/usr/share/GeoIP/GeoLite2-City.mmdb /tmp/
  sudo mv /tmp/GeoLite2-City.mmdb /usr/share/GeoIP/
  # deploy/scale/V1.0/gateway/promtail-config.yml → /etc/promtail-config.yml
  ```

- [ ] **gateway:** Tüm systemd unit'leri kur ve başlat
  ```bash
  # deploy/scale/V1.0/gateway/systemd/ → /etc/systemd/system/
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/systemd/*.service /etc/systemd/system/
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/prometheus.yml /etc/prometheus/prometheus.yml
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/loki-config.yml /etc/loki/config.yml
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/promtail-config.yml /etc/promtail-config.yml
  sudo systemctl daemon-reload
  sudo systemctl enable --now prometheus loki promtail node_exporter
  ```

- [ ] **Doğrulama — gateway monitoring:**
  ```bash
  curl http://localhost:9090/-/healthy   # Prometheus
  curl http://localhost:3100/ready       # Loki
  curl http://localhost:9100/metrics | head -5  # node_exporter
  # node1 metriklerini çekebiliyor mu:
  curl "http://localhost:9090/api/v1/query?query=up" | python3 -m json.tool
  ```

**Commit hash:** _______________

---

## 🔲 Adım 3 — gateway nginx Yapılandırması + SSL

> nginx yapılandırması aktif olana kadar mevcut node1 nginx trafiği taşır — downtime yok.

- [ ] **gateway:** SSL sertifikalarını node1'den kopyala
  ```bash
  sudo apt install -y certbot python3-certbot-nginx
  # Mevcut sertifikaları taşı (DNS henüz gateway'e taşınmadı):
  sudo tar czf /tmp/letsencrypt.tar.gz /etc/letsencrypt/
  scp node1:/tmp/letsencrypt.tar.gz /tmp/
  sudo tar xzf /tmp/letsencrypt.tar.gz -C /
  ```

- [ ] **gateway:** nginx yapılandırmasını kur
  ```bash
  # Rate limit zone'ları nginx.conf http bloğuna ekle (deploy/scale/V1.0/gateway/nginx/nginx-http-zones.conf)
  # Site config:
  sudo cp /var/www/teqlif.com/deploy/scale/V1.0/gateway/nginx/teqlif.conf \
         /etc/nginx/sites-available/teqlif.conf
  sudo ln -sf /etc/nginx/sites-available/teqlif.conf /etc/nginx/sites-enabled/
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t
  sudo systemctl reload nginx
  ```

- [ ] **Doğrulama — DNS değişmeden önce:**
  ```bash
  # /etc/hosts'a geçici kayıt ekle (sadece test için):
  echo "GATEWAY_IP teqlif.com" | sudo tee -a /etc/hosts
  curl -H "Host: teqlif.com" https://GATEWAY_IP/api/health --insecure
  # test sonrası /etc/hosts'dan sil
  ```

**Commit hash:** _______________

---

## 🔲 Adım 4 — Deploy Config Değişiklikleri

> 4 config değişikliği (plan.md Bölüm 6). Deploy pipeline değişmez, sadece config.

### 4a — node1 teqlif.service ve teqlif-staging.service

- [ ] `deploy/scale/V1.0/node1/systemd/teqlif.service` → `/etc/systemd/system/teqlif.service`
  (`--forwarded-allow-ips 127.0.0.1` → `10.10.0.2`)
- [ ] `deploy/scale/V1.0/node1/systemd/teqlif-staging.service` → `/etc/systemd/system/teqlif-staging.service`
- [ ] node1'de reload:
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl restart teqlif teqlif-staging
  ```
- [ ] Doğrulama: `journalctl -u teqlif -n 20` — hata yok

### 4b — node1 promtail → gateway Loki

- [ ] `deploy/scale/V1.0/node1/promtail-config.yml` → `/etc/promtail-config.yml`
  (`localhost:3100` → `10.10.0.2:3100`)
- [ ] `sudo systemctl restart promtail`
- [ ] Doğrulama: gateway Loki'de node1 logları geliyor mu:
  ```bash
  curl "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool
  ```

### 4c — node1 Prometheus → gateway'e taşındı

- [ ] node1'de Prometheus durdur:
  ```bash
  sudo systemctl stop prometheus
  sudo systemctl disable prometheus
  ```
- [ ] node1'de Loki durdur:
  ```bash
  sudo systemctl stop loki
  sudo systemctl disable loki
  ```
- [ ] Doğrulama: gateway Prometheus node1'i scrape ediyor:
  ```bash
  curl "http://localhost:9090/api/v1/targets" | python3 -m json.tool | grep health
  ```

### 4d — node1 node_exporter WireGuard IP'de dinle

- [ ] `deploy/scale/V1.0/node1/systemd/node_exporter.service` → `/etc/systemd/system/node_exporter.service`
  (`--web.listen-address=10.10.0.1:9100`)
- [ ] `sudo systemctl daemon-reload && sudo systemctl restart node_exporter`

**Commit hash:** _______________

---

## 🔲 Adım 5 — node1 Firewall Sertleştirme

> WireGuard ve gateway nginx aktif olduktan sonra yapılır.

- [ ] gateway'den node1'e HTTP ve monitoring erişimi:
  ```bash
  sudo ufw allow from 10.10.0.2 to any port 8000
  sudo ufw allow from 10.10.0.2 to any port 9100   # node_exporter
  sudo ufw allow from 10.10.0.2 to any port 9187   # postgres-exporter
  ```

- [ ] Doğrulama: gateway'den node1 API'sine ulaşılıyor:
  ```bash
  curl http://10.10.0.1:8000/api/health
  ```

**Commit hash:** _______________

---

## 🔲 Adım 6 — DNS Değişikliği (Cloudflare)

> Gateway nginx ve WireGuard tüneli çalışıyorken yapılır. En kritik adım.

- [ ] Cloudflare DNS TTL'leri 60 saniyeye düşür (24 saat önce yapılabilir)
- [ ] `teqlif.com` A kaydını → `GATEWAY_PUBLIC_IP` (Proxied) ✏️
- [ ] `uploads.teqlif.com` A kaydı ekle → `135.125.175.223` (DNS only) ✏️
- [ ] `live.teqlif.com` A kaydı → node1'de kalır (değişmez)
- [ ] Yayılmayı izle:
  ```bash
  watch -n 10 "dig teqlif.com +short"
  ```

- [ ] Doğrulama DNS sonrası:
  ```bash
  curl https://teqlif.com/api/health
  ```

**Commit hash:** _______________

---

## 🔲 Adım 7 — Mobil Uygulama Upload URL Güncelleme

> DNS aktif olduktan sonra. Upload trafiği gateway'i atlamalı.

- [ ] Mobil kodda upload endpoint'i `teqlif.com` → `uploads.teqlif.com` olarak güncelle
- [ ] Test: dosya yükleme gateway loglarında değil, node1 loglarında görünmeli
- [ ] Commit + push + `sudo systemctl restart teqlif teqlif-staging`

**Commit hash:** _______________

---

## 🔲 Adım 8 — Tam Doğrulama Checklist

- [ ] `curl https://teqlif.com/api/health` → 200
- [ ] WebSocket bağlantısı kuruluyor (DM, bildirim, feed)
- [ ] LiveKit WebRTC ICE başarılı — sesli/görüntülü arama çalışıyor
- [ ] `/uploads/` dosyaları erişilebilir
- [ ] MinIO presigned DM URL'leri çalışıyor
- [ ] Prometheus gateway'den node1 metriklerini scrape ediyor
- [ ] Loki node1 + gateway loglarını alıyor
- [ ] `uploads.teqlif.com` → node1 doğrudan (gateway log'da upload yok)
- [ ] `staging.teqlif.com` çalışıyor

---

## Rollback Planı

Her adımda sorun çıkarsa:

| Adım | Rollback |
|------|----------|
| WireGuard | `sudo systemctl stop wg-quick@wg0` — SSH etkilenmez |
| gateway nginx | DNS henüz değişmedi — node1 nginx trafiği taşımaya devam eder |
| forwarded-allow-ips | `deploy/monolith/systemd/teqlif.service` → eski haline döndür |
| DNS | Cloudflare'de A kaydını node1'e geri al (TTL 60s → ~1 dakika yayılır) |
