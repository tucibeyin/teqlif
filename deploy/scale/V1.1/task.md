# Teqlif Scale V1.1 — Task Log

> Her adım için önce yapılacaklar sunulur, onay alındıktan sonra uygulanır.

---

## Adım 1 — Staging Server Block Güçlendirme

**Durum:** ✅ Tamamlandı

**Değişiklikler (`gateway/nginx/teqlif.conf`):**
- `ssl_session_cache`, `ssl_stapling off` eklendi
- Security header seti eklendi (X-Content-Type-Options, X-Frame-Options, HSTS, Referrer-Policy)
- `/api/auth` → `limit_req zone=auth burst=5`
- `/api/upload` → `client_max_body_size 100M` ayrı location
- `/api/chat/` → WebSocket location (upgrade header'ları)
- `/api/` → `limit_req zone=api burst=300`
- `~* /ws$` → WebSocket location
- `/` → `limit_req zone=general burst=60`
- Production'dan fark: `burst` değerleri biraz daha gevşek (staging az trafik)

**VPS komutu (gateway):**
```bash
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.1/gateway/nginx/teqlif.conf /etc/nginx/sites-available/teqlif.conf
sudo nginx -t && sudo systemctl reload nginx
```

**Commit:** `bec02286` (nginx), `0c021a2f` (proxy_hide_header), `8b07e89a` (backend middleware)  
**VPS uygulandı:** 2026-09-08, gateway + node1  
**Not:** proxy_hide_header çalışmadı — kaynakta düzeltildi. Backend security_headers middleware'den statik başlıklar kaldırıldı, CSP koşullu mantığı kaldı. Duplicate header sorunu giderildi.

---

## Adım 2 — uploads.teqlif.com Cache-Control Düzeltmesi

**Durum:** ✅ Tamamlandı (değişiklik gerekmedi)

**Notlar:**
- V1.1 dosyasında (`node1/nginx/uploads.teqlif.com`) `immutable` zaten mevcut.
- VPS'de doğrulandı (2026-09-08): `/etc/nginx/sites-available/uploads.teqlif.com` satır 33'te `Cache-Control "public, max-age=31536000, immutable"` yazıyor.
- Herhangi bir değişiklik uygulanmadı.

**Commit:** — (değişiklik yok)

---

## Adım 3 — nginx Microcaching

**Durum:** ✅ Tamamlandı

**Değişiklikler:**
- `nginx-http-zones.conf`: `proxy_cache_path /var/cache/nginx/teqlif` eklendi (256MB, keys_zone 10m)
- `teqlif.conf` `/api/` location: `proxy_cache teqlif_cache`, GET/HEAD only, 5s TTL
- Bypass: `Authorization` veya `Pragma` header varsa cache yok — authenticated istekler asla cache'lenmez
- `X-Cache-Status` response header eklendi (HIT/MISS/BYPASS debug için)
- Staging block'a cache eklenmedi (kasıtlı)

**VPS komutu (gateway):**
```bash
sudo mkdir -p /var/cache/nginx/teqlif
sudo chown www-data:www-data /var/cache/nginx/teqlif
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.1/gateway/nginx/nginx-http-zones.conf /etc/nginx/conf.d/http-zones.conf
sudo cp deploy/scale/V1.1/gateway/nginx/teqlif.conf /etc/nginx/sites-available/teqlif.conf
sudo nginx -t && sudo systemctl reload nginx
```

**Commit:** `90aedd4b`  
**VPS uygulandı:** 2026-09-08, gateway  
**Test:** MISS→HIT (auth yok) ✅, BYPASS (Authorization header) ✅

---

## Adım 4 — Alertmanager

**Durum:** ✅ Tamamlandı

**Dosyalar:**
- `deploy/scale/V1.1/gateway/alertmanager.yml` — Telegram receiver, `${TELEGRAM_BOT_TOKEN}` / `${TELEGRAM_CHAT_ID}` placeholder
- `deploy/scale/V1.1/gateway/prometheus-rules.yml` — NodeDown, HighMemory, DiskSpaceLow, HighSwap, HighCPU kuralları
- `deploy/scale/V1.1/gateway/prometheus.yml` — rule_files + alerting bloğu eklendi
- `deploy/scale/V1.1/gateway/systemd/alertmanager.service` — `EnvironmentFile=/var/www/teqlif.com/backend/.env` + `--config.expand-env`

**Not:** Değişkenler (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`) gateway'deki `/var/www/teqlif.com/backend/.env`'den okunur. Ayrı bir env dosyası gerekmez.

**Not:** `--config.expand-env` 0.27.0 build'inde yok. Deploy sırasında `envsubst` ile template'ten gerçek config oluşturulur.

**VPS komutu (gateway):**
```bash
# Binary kurulum (zaten yapıldıysa atla)
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
tar xzf alertmanager-0.27.0.linux-amd64.tar.gz
sudo mv alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager /etc/prometheus/rules

# Config
cd /var/www/teqlif.com && git pull

# Template'ten gerçek config oluştur (credentials .env'den okunur)
set -a && source /etc/alertmanager/alertmanager.env && set +a
envsubst '$TELEGRAM_BOT_TOKEN $TELEGRAM_CHAT_ID' \
  < deploy/scale/V1.1/gateway/alertmanager.yml.template \
  | sudo tee /etc/alertmanager/alertmanager.yml > /dev/null

sudo cp deploy/scale/V1.1/gateway/prometheus-rules.yml /etc/prometheus/rules/teqlif.yml
sudo cp deploy/scale/V1.1/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp deploy/scale/V1.1/gateway/systemd/alertmanager.service /etc/systemd/system/alertmanager.service

# Servis
sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager
sudo systemctl restart prometheus
```

**Commit:** `ef23a889`  
**VPS uygulandı:** 2026-09-08, gateway  
**Test:** `/-/healthy` → OK, 5 kural inactive (sistem sağlıklı) ✅

---

## Özet

| Adım | İçerik | Durum |
|---|---|---|
| 1 | Staging block güçlendirme | ✅ |
| 2 | uploads.teqlif.com immutable | ✅ |
| 3 | nginx microcaching | ✅ |
| 4 | Alertmanager | ✅ |
