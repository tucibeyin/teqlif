# Nginx Rate Limiting - Kurulum

## Adım 1: nginx.conf'u düzenleyin

```bash
sudo nano /etc/nginx/nginx.conf
```

http { bölümüne şunları ekleyin:

```nginx
http {
    # ... mevcut ayarlar ...
    
    # Rate limiting - ekleyin
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=5r/m;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
}
```

## Adım 2: teqlif config'i güncelleyin

```bash
sudo nano /etc/nginx/sites-available/teqlif
```

`proxy_pass` olan her `location` bloğuna şu satırları ekleyin:

```nginx
location /api/ {
    limit_req zone=api_limit burst=10 nodelay;

    # ── X-Forwarded-For Spoofing Koruması (ZORUNLU) ──────────────────────
    # İstemcinin gönderebileceği X-Forwarded-For header'ını ezer.
    # Bu olmazsa kötü niyetli kullanıcı sahte IP göndererek rate limit'i bypass eder.
    proxy_set_header X-Real-IP        $remote_addr;
    proxy_set_header X-Forwarded-For  $remote_addr;
    proxy_set_header Host             $host;

    proxy_pass http://127.0.0.1:8000;
    ...
}

location /api/auth {
    limit_req zone=auth_limit burst=5 nodelay;
    limit_conn conn_limit 3;

    proxy_set_header X-Real-IP        $remote_addr;
    proxy_set_header X-Forwarded-For  $remote_addr;
    proxy_set_header Host             $host;

    proxy_pass http://127.0.0.1:8000;
    ...
}
```

## Adım 3: Test ve yeniden başlat

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Test

```bash
# Rate limit test
for i in {1..15}; do curl -I https://teqlif.com/api/categories & done
```

---

## ⚠️ Önemli: CSP Header Yönetimi

Content-Security-Policy **yalnızca FastAPI middleware** (`backend/app/security/middleware.py`) üzerinden yönetilmeli.
Nginx config'de `add_header Content-Security-Policy` satırı OLMAMALI — iki CSP çakışır, nginx'inki kazanır.

Nginx config'de CSP satırı varsa kaldır:
```bash
sudo nano /etc/nginx/sites-enabled/teqlif.com
# add_header Content-Security-Policy ... satırını sil veya yorum satırına al
sudo nginx -t && sudo systemctl reload nginx
```

Zorunlu olarak nginx'te tutulacaksa şu domain'lerin mevcut olduğundan emin ol:
- `script-src`: `https://challenges.cloudflare.com`
- `frame-src`:  `https://challenges.cloudflare.com`
- `connect-src`: `https://challenges.cloudflare.com`
