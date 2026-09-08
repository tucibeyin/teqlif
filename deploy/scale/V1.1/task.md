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

**Commit:** `bec02286`  
**VPS uygulandı:** 2026-09-08, gateway

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

**Durum:** ⬜ Bekliyor

**Dosyalar:**
- `deploy/scale/V1.1/gateway/alertmanager.yml`
- `deploy/scale/V1.1/gateway/prometheus-rules.yml`
- `deploy/scale/V1.1/gateway/prometheus.yml` (rule_files + alerting bloğu eklenir)
- `deploy/scale/V1.1/gateway/systemd/alertmanager.service`

**VPS komutu (gateway):**
```bash
# Binary kurulum
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
tar xzf alertmanager-0.27.0.linux-amd64.tar.gz
sudo mv alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager

# Config
cd /var/www/teqlif.com && git pull
sudo cp deploy/scale/V1.1/gateway/alertmanager.yml /etc/alertmanager/alertmanager.yml
sudo cp deploy/scale/V1.1/gateway/prometheus-rules.yml /etc/prometheus/rules/teqlif.yml
sudo cp deploy/scale/V1.1/gateway/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp deploy/scale/V1.1/gateway/systemd/alertmanager.service /etc/systemd/system/alertmanager.service

# Servis
sudo systemctl daemon-reload
sudo systemctl enable --now alertmanager
sudo systemctl restart prometheus
```

**Commit:** —

---

## Özet

| Adım | İçerik | Durum |
|---|---|---|
| 1 | Staging block güçlendirme | ✅ |
| 2 | uploads.teqlif.com immutable | ✅ |
| 3 | nginx microcaching | ✅ |
| 4 | Alertmanager | ⬜ |
